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
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString()
        val msg = if (text.isNullOrEmpty()) "Буфер обмена пуст" else {
            LinkService.post(this, "clipboard", JSONObject().put("text", text))
            "Буфер отправлен на Mac"
        }
        Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
        finish()
    }
}
