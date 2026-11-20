package com.androidlink

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM. Wire frame = base64(nonce[12] || ciphertext || tag[16]).
 * Must match lib/features/bridge/services/link_crypto.dart.
 */
object LinkCrypto {
    private val rnd = SecureRandom()

    fun seal(key: ByteArray, plain: String): String {
        val nonce = ByteArray(12).also { rnd.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(nonce + ct, Base64.NO_WRAP)
    }

    fun open(key: ByteArray, frame: String): String? = try {
        val b = Base64.decode(frame, Base64.NO_WRAP)
        if (b.size < 28) null else {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, b, 0, 12))
            String(c.doFinal(b, 12, b.size - 12), Charsets.UTF_8)
        }
    } catch (e: Exception) {
        null
    }

    fun randomId(): String {
        val b = ByteArray(12).also { rnd.nextBytes(it) }
        return Base64.encodeToString(b, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
