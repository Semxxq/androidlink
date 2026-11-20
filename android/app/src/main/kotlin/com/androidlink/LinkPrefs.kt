package com.androidlink

import android.content.Context
import android.net.Uri
import android.util.Base64
import java.util.UUID

/** Pairing data (shared key with the Mac) stored in app-private prefs. */
class LinkPrefs(ctx: Context) {
    private val sp = ctx.applicationContext.getSharedPreferences("androidlink", Context.MODE_PRIVATE)

    val deviceId: String
        get() = sp.getString("device_id", null)
            ?: UUID.randomUUID().toString().also { sp.edit().putString("device_id", it).apply() }

    val key: ByteArray?
        get() = sp.getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) }

    val macId: String? get() = sp.getString("mac_id", null)
    val macName: String? get() = sp.getString("mac_name", null)
    val port: Int get() = sp.getInt("port", 41234)
    val pairId: String? get() = sp.getString("pair_id", null)
    val isPaired: Boolean get() = key != null && macId != null

    /** Known Mac addresses, most recently working first. */
    val hosts: List<String>
        get() = sp.getString("hosts", "")!!.split(',').filter { it.isNotBlank() }

    fun rememberHost(ip: String, port: Int = this.port) {
        val list = (listOf(ip) + hosts.filter { it != ip }).take(4)
        sp.edit().putString("hosts", list.joinToString(",")).putInt("port", port).apply()
    }

    var smsLastId: Long
        get() = sp.getLong("sms_last_id", 0L)
        set(v) = sp.edit().putLong("sms_last_id", v).apply()

    fun setMacName(name: String) = sp.edit().putString("mac_name", name).apply()
    fun clearPairId() = sp.edit().remove("pair_id").apply()

    /** androidlink://pair?h=ip1,ip2&p=41234&k=<b64url key>&i=<pairId>&m=<macId>&n=<name> */
    fun pair(qr: String): Boolean {
        val u = Uri.parse(qr)
        if (u.scheme != "androidlink" || u.host != "pair") return false
        val k = u.getQueryParameter("k") ?: return false
        val m = u.getQueryParameter("m") ?: return false
        val i = u.getQueryParameter("i") ?: return false
        val key = try {
            Base64.decode(k, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        } catch (e: Exception) { return false }
        if (key.size != 32) return false
        sp.edit()
            .putString("key", Base64.encodeToString(key, Base64.NO_WRAP))
            .putString("mac_id", m)
            .putString("mac_name", u.getQueryParameter("n") ?: "Mac")
            .putString("pair_id", i)
            .putString("hosts", u.getQueryParameter("h") ?: "")
            .putInt("port", u.getQueryParameter("p")?.toIntOrNull() ?: 41234)
            .apply()
        return true
    }

    fun clear() {
        val id = deviceId
        sp.edit().clear().putString("device_id", id).apply()
    }
}
