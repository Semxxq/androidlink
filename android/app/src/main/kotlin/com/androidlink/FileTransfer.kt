package com.androidlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Chunked file transfer, both directions.
 *   file_offer {fid,name,size,mime} → file_chunk {fid,seq,data} … → file_done {fid,chunks}
 *   receiver → file_ack {fid,seq} every few chunks (sliding window), file_cancel {fid}.
 * Must match lib/bridge/file_transfer.dart.
 */
class FileTransfer(private val svc: LinkService) {

    companion object {
        private const val TAG = "FileTransfer"
        const val CHUNK = 192 * 1024
        private const val WINDOW = 24
        private const val ACK_EVERY = 8
        private const val CHANNEL = "files"

        fun safeName(n: String): String =
            n.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim().take(180).ifBlank { "file" }
    }

    private class Incoming(
        val fid: String, val name: String, val size: Long, val mime: String,
        val tmp: File, val out: FileOutputStream,
    ) {
        var next = 0
        var got = 0L
    }

    private val incoming = ConcurrentHashMap<String, Incoming>()
    private val acked = ConcurrentHashMap<String, Int>()
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private val rxIo = Executors.newSingleThreadExecutor()
    private val txIo = Executors.newSingleThreadExecutor()

    /** Returns true if the message was a file-transfer message. */
    fun onMessage(type: String, p: JSONObject): Boolean {
        val fid = p.optString("fid")
        when (type) {
            "file_offer" -> rxIo.execute { offer(fid, p) }
            "file_chunk" -> { val data = p.optString("data"); val seq = p.optInt("seq"); rxIo.execute { chunk(fid, seq, data) } }
            "file_done" -> rxIo.execute { done(fid) }
            "file_ack" -> acked[fid] = maxOf(acked[fid] ?: -1, p.optInt("seq", -1))
            "file_cancel" -> { cancelled.add(fid); rxIo.execute { drop(fid) } }
            else -> return false
        }
        return true
    }

    // ── receive ──────────────────────────────────────────────────────────

    private fun offer(fid: String, p: JSONObject) {
        val name = safeName(p.optString("name"))
        val tmp = File(svc.cacheDir, "rx-$fid")
        incoming[fid] = Incoming(fid, name, p.optLong("size"), p.optString("mime").ifEmpty { "application/octet-stream" },
            tmp, FileOutputStream(tmp))
        svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", name).put("dir", "in")
            .put("size", p.optLong("size")).put("done", 0).toString())
    }

    private fun chunk(fid: String, seq: Int, data: String) {
        val t = incoming[fid] ?: return
        if (seq != t.next) { Log.w(TAG, "out of order $seq != ${t.next}"); cancel(fid); return }
        val bytes = Base64.decode(data, Base64.NO_WRAP)
        t.out.write(bytes)
        t.got += bytes.size
        t.next++
        if (t.next % ACK_EVERY == 0) svc.send("file_ack", JSONObject().put("fid", fid).put("seq", seq))
        if (t.next % 4 == 0) svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", t.name)
            .put("dir", "in").put("size", t.size).put("done", t.got).toString())
    }

    private fun done(fid: String) {
        val t = incoming.remove(fid) ?: return
        t.out.close()
        svc.send("file_ack", JSONObject().put("fid", fid).put("seq", t.next - 1).put("complete", true))
        val uri = try { publish(t) } catch (e: Exception) { Log.w(TAG, "publish: ${e.message}"); null }
        t.tmp.delete()
        svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", t.name).put("dir", "in")
            .put("size", t.size).put("done", t.size).put("finished", true).toString())
        notifyReceived(t.name, t.mime, uri)
    }

    private fun drop(fid: String) {
        incoming.remove(fid)?.let { it.out.close(); it.tmp.delete() }
    }

    private fun cancel(fid: String) {
        drop(fid)
        svc.send("file_cancel", JSONObject().put("fid", fid))
    }

    private fun publish(t: Incoming): Uri? {
        val r = svc.contentResolver
        if (Build.VERSION.SDK_INT >= 29) {
            val v = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, t.name)
                put(MediaStore.Downloads.MIME_TYPE, t.mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/AndroidLink")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = r.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v) ?: return null
            r.openOutputStream(uri)?.use { o -> t.tmp.inputStream().use { it.copyTo(o) } }
            v.clear(); v.put(MediaStore.Downloads.IS_PENDING, 0)
            r.update(uri, v, null, null)
            return uri
        }
        val dir = svc.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return null
        t.tmp.copyTo(File(dir, t.name), overwrite = true)
        return null
    }

    private fun notifyReceived(name: String, mime: String, uri: Uri?) {
        val nm = svc.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Файлы с Mac", NotificationManager.IMPORTANCE_DEFAULT))
        }
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(svc, CHANNEL) else Notification.Builder(svc)
        b.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Файл с Mac")
            .setContentText(name)
            .setAutoCancel(true)
        if (uri != null) {
            val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            b.setContentIntent(PendingIntent.getActivity(svc, name.hashCode(), view,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        }
        try { nm.notify(name.hashCode(), b.build()) } catch (_: Exception) {}
    }

    // ── send ─────────────────────────────────────────────────────────────

    fun send(uri: Uri) = txIo.execute {
        val r = svc.contentResolver
        var name = "file"
        var size = -1L
        try {
            r.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    name = c.getString(0) ?: name
                    if (!c.isNull(1)) size = c.getLong(1)
                }
            }
        } catch (_: Exception) {}
        if (uri.scheme == "file") uri.path?.let { File(it) }?.let { name = it.name; size = it.length() }
        name = safeName(name)
        val mime = r.getType(uri) ?: "application/octet-stream"
        val fid = LinkCrypto.randomId()
        acked[fid] = -1
        svc.send("file_offer", JSONObject().put("fid", fid).put("name", name).put("size", size).put("mime", mime))
        var seq = 0
        var sent = 0L
        try {
            r.openInputStream(uri)?.use { input ->
                val buf = ByteArray(CHUNK)
                while (true) {
                    val n = readFully(input, buf)
                    if (n <= 0) break
                    var waited = 0
                    while (seq - (acked[fid] ?: -1) > WINDOW) {
                        if (fid in cancelled || LinkService.status != "connected" || waited > 60_000) throw IllegalStateException("aborted")
                        Thread.sleep(15); waited += 15
                    }
                    if (fid in cancelled || LinkService.status != "connected") throw IllegalStateException("aborted")
                    svc.send("file_chunk", JSONObject().put("fid", fid).put("seq", seq)
                        .put("data", Base64.encodeToString(buf, 0, n, Base64.NO_WRAP)))
                    seq++; sent += n
                    if (seq % 4 == 0) svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", name)
                        .put("dir", "out").put("size", size).put("done", sent).toString())
                }
            }
            svc.send("file_done", JSONObject().put("fid", fid).put("chunks", seq))
            svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", name).put("dir", "out")
                .put("size", sent).put("done", sent).put("finished", true).toString())
        } catch (e: Exception) {
            Log.w(TAG, "send $name: ${e.message}")
            svc.send("file_cancel", JSONObject().put("fid", fid))
            svc.emitUi("transfer", JSONObject().put("fid", fid).put("name", name).put("dir", "out")
                .put("failed", true).toString())
        } finally {
            acked.remove(fid); cancelled.remove(fid)
        }
    }

    private fun readFully(input: java.io.InputStream, buf: ByteArray): Int {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) break
            off += n
        }
        return off
    }

    fun shutdown() {
        rxIo.shutdownNow(); txIo.shutdownNow()
        incoming.values.forEach { it.out.close(); it.tmp.delete() }
        incoming.clear()
    }
}
