package com.androidlink

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.File

/** Serves the last image received from the Mac so it can live on the clipboard. */
class ClipProvider : ContentProvider() {
    companion object {
        const val AUTH = "com.androidlink.clip"
        private const val MAX_BYTES = 8 * 1024 * 1024

        fun file(ctx: Context) = File(ctx.cacheDir, "clip").apply { mkdirs() }.let { File(it, "clip.jpg") }

        /** Writes bytes and returns a fresh URI (the query param defeats URI caching in readers). */
        fun store(ctx: Context, bytes: ByteArray): Uri {
            file(ctx).writeBytes(bytes)
            return Uri.parse("content://$AUTH/clip.jpg?t=${System.currentTimeMillis()}")
        }

        /** Reads an image URI and returns JPEG bytes no larger than MAX_BYTES, or null. */
        fun readImage(ctx: Context, uri: Uri): ByteArray? = try {
            val raw = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
            val isJpeg = raw.size > 2 && raw[0] == 0xFF.toByte() && raw[1] == 0xD8.toByte()
            if (isJpeg && raw.size <= MAX_BYTES) raw else {
                var bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return null
                val maxSide = 4096
                if (maxOf(bmp.width, bmp.height) > maxSide) {
                    val k = maxSide.toFloat() / maxOf(bmp.width, bmp.height)
                    bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * k).toInt(), (bmp.height * k).toInt(), true)
                }
                ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 88, it) }
                    .toByteArray().takeIf { it.size <= MAX_BYTES }
            }
        } catch (e: Exception) { null }
    }

    override fun onCreate() = true
    override fun getType(uri: Uri) = "image/jpeg"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("read-only")
        return ParcelFileDescriptor.open(file(context!!), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor {
        val f = file(context!!)
        return MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).apply {
            addRow(arrayOf<Any>("clip.jpg", f.length()))
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}
