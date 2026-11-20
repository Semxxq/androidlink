package com.androidlink

import android.app.Activity
import android.content.ClipboardManager
import android.os.Bundle
import android.widget.Toast
import org.json.JSONObject

/**
 * Non-exported invisible activity launched only by our own PendingIntents
 * (notification action, Quick Settings tile). Android lets apps read the
 * clipboard only while they have window focus — so we take focus for a frame.
 */
class ClipPushActivity : Activity() {
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!LinkPrefs(this).isPaired) { finish(); return }
        LinkService.start(this)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true
        val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val item = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
        val mime = cm.primaryClipDescription?.takeIf { it.mimeTypeCount > 0 }?.getMimeType(0) ?: ""
        val uri = item?.uri
        val msg = if (uri != null && (mime.startsWith("image/") || contentResolver.getType(uri)?.startsWith("image/") == true)) {
            val bytes = ClipProvider.readImage(this, uri)
            if (bytes == null) "Не удалось прочитать изображение" else {
                LinkService.post(this, "clip_image", JSONObject().put("image", android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)))
                "Изображение отправлено на Mac"
            }
        } else {
            val text = item?.coerceToText(this)?.toString()
            if (text.isNullOrEmpty()) "Буфер обмена пуст" else {
                LinkService.post(this, "clipboard", JSONObject().put("text", text))
                "Буфер отправлен на Mac"
            }
        }
        Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
        finish()
    }
}
