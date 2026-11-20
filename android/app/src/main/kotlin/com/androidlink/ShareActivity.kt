package com.androidlink

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import org.json.JSONObject

/**
 * Exported share-sheet target ("Поделиться → Отправить на Mac"): text goes to
 * the Mac clipboard, files to ~/Downloads. Only content:// URIs from other
 * apps are accepted — never file:// or our own provider (no confused deputy).
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!LinkPrefs(this).isPaired) {
            toast("Сначала подключи Mac в AndroidLink"); finish(); return
        }
        LinkService.start(this)
        handleShare()
        finish()
    }

    private fun isForeignContent(u: Uri): Boolean =
        u.scheme == "content" && u.authority != null && !u.authority!!.startsWith(packageName)

    private fun handleShare() {
        val i = intent ?: return
        val uris = mutableListOf<Uri>()
        when (i.action) {
            Intent.ACTION_SEND -> streamExtra(i)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamListExtra(i))
        }
        uris.retainAll { isForeignContent(it) }
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
