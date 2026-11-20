package com.androidlink

import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import org.json.JSONObject

/**
 * Invisible activity:
 *  - share sheet target ("Поделиться → AndroidLink"): text goes to the Mac
 *    clipboard, files are sent to ~/Downloads;
 *  - ACTION_PUSH_CLIPBOARD (notification button / quick tile): reads the phone
 *    clipboard (allowed only while an activity has focus) and sends it.
 */
class ShareActivity : Activity() {

    companion object {
        const val ACTION_PUSH_CLIPBOARD = "com.androidlink.PUSH_CLIPBOARD"
    }

    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!LinkPrefs(this).isPaired) {
            toast("Сначала подключи Mac в AndroidLink"); finish(); return
        }
        LinkService.start(this)
        if (intent?.action != ACTION_PUSH_CLIPBOARD) { handleShare(); finish() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled || intent?.action != ACTION_PUSH_CLIPBOARD) return
        handled = true
        val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString()
        if (text.isNullOrEmpty()) toast("Буфер обмена пуст")
        else {
            LinkService.post(this, "clipboard", JSONObject().put("text", text))
            toast("Буфер отправлен на Mac")
        }
        finish()
    }

    private fun handleShare() {
        val i = intent ?: return
        val uris = mutableListOf<Uri>()
        when (i.action) {
            Intent.ACTION_SEND -> streamExtra(i)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamListExtra(i))
        }
        if (uris.isNotEmpty()) {
            val svc = LinkService.instance
            if (svc == null || LinkService.status != "connected") { toast("Mac не подключён"); return }
            uris.forEach { svc.files.send(it) }
            toast(if (uris.size == 1) "Отправляю файл на Mac…" else "Отправляю ${uris.size} файлов на Mac…")
            return
        }
        val text = i.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrEmpty()) {
            LinkService.post(this, "clipboard", JSONObject().put("text", text).put("shared", true))
            toast("Скопировано на Mac")
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(i: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun toast(s: String) = Toast.makeText(applicationContext, s, Toast.LENGTH_SHORT).show()
}
