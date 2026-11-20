package com.androidlink

import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Reads SMS / call log / contacts for history sync with the Mac. */
object PhoneData {
    private const val TAG = "PhoneData"
    private const val BATCH = 200

    // ── SMS ──────────────────────────────────────────────────────────────

    private val smsCols = arrayOf(
        Telephony.Sms._ID, Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS,
        Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ,
    )

    private fun smsJson(c: Cursor, names: MutableMap<String, String?>, ctx: Context): JSONObject {
        val addr = c.getString(2) ?: ""
        val type = c.getInt(5)
        val o = JSONObject()
            .put("id", "sms:${c.getLong(0)}")
            .put("thread", c.getLong(1))
            .put("address", addr)
            .put("body", c.getString(3) ?: "")
            .put("ts", c.getLong(4))
            .put("in", type == Telephony.Sms.MESSAGE_TYPE_INBOX)
            .put("read", c.getInt(6) == 1)
            .put("status", when (type) {
                Telephony.Sms.MESSAGE_TYPE_FAILED -> "failed"
                Telephony.Sms.MESSAGE_TYPE_OUTBOX, Telephony.Sms.MESSAGE_TYPE_QUEUED -> "sending"
                Telephony.Sms.MESSAGE_TYPE_INBOX -> "received"
                else -> "sent"
            })
        val name = names.getOrPut(addr) { Contacts.name(ctx, addr) }
        if (name != null) o.put("name", name)
        return o
    }

    fun maxSmsId(ctx: Context): Long = try {
        ctx.contentResolver.query(Telephony.Sms.CONTENT_URI, arrayOf(Telephony.Sms._ID), null, null,
            "${Telephony.Sms._ID} DESC LIMIT 1")?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
    } catch (e: Exception) { 0L }

    /** Latest [limit] SMS, newest first, delivered in batches. */
    fun syncSms(ctx: Context, limit: Int, emit: (String, JSONObject) -> Unit) {
        val names = HashMap<String, String?>()
        var arr = JSONArray()
        try {
            ctx.contentResolver.query(Telephony.Sms.CONTENT_URI, smsCols, null, null,
                "${Telephony.Sms.DATE} DESC LIMIT $limit")?.use { c ->
                while (c.moveToNext()) {
                    arr.put(smsJson(c, names, ctx))
                    if (arr.length() >= BATCH) {
                        emit("sms_batch", JSONObject().put("items", arr).put("done", false)); arr = JSONArray()
                    }
                }
            }
        } catch (e: Exception) { Log.w(TAG, "sms sync: ${e.message}") }
        for ((_, o) in Mms.query(ctx, minOf(limit / 5, 300))) {
            arr.put(o)
            if (arr.length() >= 50) {
                emit("sms_batch", JSONObject().put("items", arr).put("done", false)); arr = JSONArray()
            }
        }
        emit("sms_batch", JSONObject().put("items", arr).put("done", true))
    }

    /** Rows with _id > [after], oldest first. */
    fun smsAfter(ctx: Context, after: Long): List<Pair<Long, JSONObject>> {
        val names = HashMap<String, String?>()
        val out = ArrayList<Pair<Long, JSONObject>>()
        try {
            ctx.contentResolver.query(Telephony.Sms.CONTENT_URI, smsCols, "${Telephony.Sms._ID} > ?",
                arrayOf(after.toString()), "${Telephony.Sms._ID} ASC LIMIT 100")?.use { c ->
                while (c.moveToNext()) out.add(c.getLong(0) to smsJson(c, names, ctx))
            }
        } catch (e: Exception) { Log.w(TAG, "sms after: ${e.message}") }
        return out
    }

    /**
     * Observes the SMS provider: every new row (incoming or sent from any app)
     * is pushed live, so phone and Mac show the same conversation.
     */
    class SmsObserver(
        private val ctx: Context, h: Handler, private val prefs: LinkPrefs,
        private val onNew: (JSONObject) -> Unit,
    ) : ContentObserver(h) {
        private var lastId = prefs.smsLastId.takeIf { it > 0 } ?: maxSmsId(ctx).also { prefs.smsLastId = it }
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            for ((id, o) in smsAfter(ctx, lastId)) {
                // Outbox rows turn into "sent" moments later — wait for that.
                if (o.optString("status") == "sending" &&
                    o.optLong("ts") > System.currentTimeMillis() - 300_000) break
                lastId = maxOf(lastId, id)
                onNew(o)
            }
            prefs.smsLastId = lastId
        }
        fun register() = try {
            ctx.contentResolver.registerContentObserver(Uri.parse("content://sms"), true, this)
        } catch (e: Exception) { Log.w(TAG, "observer: ${e.message}") }
        fun unregister() = ctx.contentResolver.unregisterContentObserver(this)
    }

    // ── Call log ─────────────────────────────────────────────────────────

    fun syncCalls(ctx: Context, limit: Int, emit: (String, JSONObject) -> Unit) {
        val arr = JSONArray()
        try {
            ctx.contentResolver.query(CallLog.Calls.CONTENT_URI, arrayOf(
                CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION,
            ), null, null, "${CallLog.Calls.DATE} DESC")?.use { c ->
                while (arr.length() < limit && c.moveToNext()) {
                    val o = JSONObject()
                        .put("id", "log:${c.getLong(0)}")
                        .put("address", c.getString(1) ?: "")
                        .put("type", when (c.getInt(3)) {
                            CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                            CallLog.Calls.MISSED_TYPE -> "missed"
                            CallLog.Calls.REJECTED_TYPE -> "rejected"
                            else -> "incoming"
                        })
                        .put("ts", c.getLong(4))
                        .put("dur", c.getLong(5))
                    c.getString(2)?.takeIf { it.isNotEmpty() }?.let { o.put("name", it) }
                    arr.put(o)
                }
            }
        } catch (e: Exception) { Log.w(TAG, "calls sync: ${e.message}") }
        emit("call_batch", JSONObject().put("items", arr).put("done", true))
    }

    // ── Contacts ─────────────────────────────────────────────────────────

    fun syncContacts(ctx: Context, emit: (String, JSONObject) -> Unit) {
        val byName = LinkedHashMap<String, MutableSet<String>>()
        try {
            ctx.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            ), null, null, "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC")?.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(0) ?: continue
                    val num = c.getString(1) ?: continue
                    byName.getOrPut(name) { LinkedHashSet() }.add(num.replace(" ", ""))
                }
            }
        } catch (e: Exception) { Log.w(TAG, "contacts: ${e.message}") }
        var arr = JSONArray()
        for ((name, nums) in byName) {
            arr.put(JSONObject().put("name", name).put("numbers", JSONArray(nums.toList())))
            if (arr.length() >= 500) {
                emit("contacts_batch", JSONObject().put("items", arr).put("done", false)); arr = JSONArray()
            }
        }
        emit("contacts_batch", JSONObject().put("items", arr).put("done", true))
    }
}
