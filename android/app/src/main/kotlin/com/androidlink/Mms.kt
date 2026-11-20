package com.androidlink

import android.content.Context
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** MMS (pictures, group chats) mapped onto the same JSON shape as SMS. */
object Mms {
    private const val TAG = "AndroidLink.Mms"
    private val MMS = Uri.parse("content://mms")
    private const val FROM = 137

    fun maxId(ctx: Context): Long = try {
        ctx.contentResolver.query(MMS, arrayOf("_id"), null, null, "_id DESC")
            ?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
    } catch (e: Exception) { 0L }

    /** Newest [limit] MMS (newest first) or rows with _id > [after] (oldest first). */
    fun query(ctx: Context, limit: Int, after: Long = -1): List<Pair<Long, JSONObject>> {
        val names = HashMap<String, String?>()
        val out = ArrayList<Pair<Long, JSONObject>>()
        try {
            val sel = if (after >= 0) "_id > ?" else null
            val args = if (after >= 0) arrayOf(after.toString()) else null
            val order = if (after >= 0) "_id ASC" else "date DESC"
            ctx.contentResolver.query(MMS, arrayOf("_id", "thread_id", "date", "msg_box", "read"), sel, args, order)?.use { c ->
                while (out.size < limit && c.moveToNext()) {
                    val id = c.getLong(0)
                    json(ctx, id, c.getLong(1), c.getLong(2) * 1000, c.getInt(3), c.getInt(4) == 1, names)?.let { out.add(id to it) }
                }
            }
        } catch (e: Exception) { Log.w(TAG, "query: ${e.message}") }
        return out
    }

    private fun json(ctx: Context, id: Long, thread: Long, ts: Long, box: Int, read: Boolean,
                     names: MutableMap<String, String?>): JSONObject? {
        val incoming = box == 1
        // Participants: everyone except our own number placeholder.
        val addrs = ArrayList<String>()
        var sender: String? = null
        try {
            ctx.contentResolver.query(Uri.parse("content://mms/$id/addr"), arrayOf("address", "type"), null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val a = c.getString(0) ?: continue
                    if (a.isBlank() || a == "insert-address-token") continue
                    if (c.getInt(1) == FROM) { sender = a; if (!incoming) continue }
                    if (addrs.none { PhoneNorm.same(it, a) }) addrs.add(a)
                }
            }
        } catch (e: Exception) { return null }
        if (addrs.isEmpty()) return null
        var text = ""
        var image: String? = null
        try {
            ctx.contentResolver.query(Uri.parse("content://mms/part"), arrayOf("_id", "ct", "text"), "mid = ?",
                arrayOf(id.toString()), null)?.use { c ->
                while (c.moveToNext()) {
                    val ct = c.getString(1) ?: ""
                    when {
                        ct == "text/plain" -> text += (c.getString(2) ?: "")
                        ct.startsWith("image/") && image == null -> image = thumb(ctx, c.getLong(0))
                    }
                }
            }
        } catch (e: Exception) { Log.w(TAG, "parts: ${e.message}") }
        if (text.isEmpty() && image == null) return null
        val o = JSONObject()
            .put("id", "mms:$id")
            .put("thread", thread)
            .put("address", addrs.joinToString(","))
            .put("body", text)
            .put("ts", ts)
            .put("in", incoming)
            .put("read", read)
            .put("status", when (box) { 1 -> "received"; 4 -> "sending"; 5 -> "failed"; else -> "sent" })
        if (incoming && sender != null) o.put("sender", sender)
        image?.let { o.put("image", it) }
        if (addrs.size == 1) names.getOrPut(addrs[0]) { Contacts.name(ctx, addrs[0]) }?.let { o.put("name", it) }
        else {
            val ns = JSONObject()
            for (a in addrs + listOfNotNull(sender)) names.getOrPut(a) { Contacts.name(ctx, a) }?.let { ns.put(a, it) }
            o.put("names", ns)
        }
        return o
    }

    private fun thumb(ctx: Context, partId: Long): String? = try {
        val uri = Uri.parse("content://mms/part/$partId")
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
        var sample = 1
        while (maxOf(opts.outWidth, opts.outHeight) / (sample * 2) >= 640) sample *= 2
        val bmp = ctx.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        }
        bmp?.let { b ->
            val out = ByteArrayOutputStream()
            b.compress(Bitmap.CompressFormat.JPEG, 75, out)
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        }
    } catch (e: Exception) { null }

    /** Pushes new MMS live (incoming pictures, group messages). */
    class Observer(private val ctx: Context, h: Handler, private val onNew: (JSONObject) -> Unit) : ContentObserver(h) {
        private var lastId = maxId(ctx)
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            for ((id, o) in query(ctx, 50, lastId)) {
                // Incoming MMS may still be downloading (no parts yet); retry on next change.
                if (o.optString("status") == "sending") break
                lastId = maxOf(lastId, id)
                onNew(o)
            }
        }
        fun register() = try {
            ctx.contentResolver.registerContentObserver(Uri.parse("content://mms-sms/"), true, this)
        } catch (e: Exception) { Log.w(TAG, "observer: ${e.message}") }
        fun unregister() = ctx.contentResolver.unregisterContentObserver(this)
    }
}

object PhoneNorm {
    fun digits(a: String) = a.filter { it.isDigit() }.takeLast(10)
    fun same(a: String, b: String) = digits(a).isNotEmpty() && digits(a) == digits(b)
}
