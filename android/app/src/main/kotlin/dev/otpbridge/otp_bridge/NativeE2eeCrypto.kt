package dev.otpbridge.otp_bridge

import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.abs

/**
 * AES-256-GCM E2EE envelope compatible byte-for-byte with Dart `E2eeCrypto`.
 *
 * Uses standard `java.util.Base64` (available on Android API 26+ and JVM unit tests)
 * with fallback decoding so cross-platform JUnit parity tests run cleanly on JVM.
 *
 * Envelope: [0x01][12-byte IV][ciphertext][16-byte GCM tag]
 * AAD: UTF-8("otpbridge:v1")
 */
object NativeE2eeCrypto {
    private const val VERSION_BYTE: Byte = 0x01
    private const val NONCE_LEN = 12
    private const val TAG_BITS = 128
    private const val MAX_REPLAY_WINDOW_MS = 120_000L
    private val AAD = "otpbridge:v1".toByteArray(Charsets.UTF_8)
    private val rng = SecureRandom()

    fun decodeKey(keyBase64Url: String): ByteArray {
        val cleaned = keyBase64Url.trim()
        val raw = try {
            Base64.getUrlDecoder().decode(cleaned)
        } catch (_: Throwable) {
            android.util.Base64.decode(
                cleaned,
                android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
            )
        }
        require(raw.size == 32) { "Expected 32-byte AES-256 key, got ${raw.size}" }
        return raw
    }

    fun encryptEnvelope(
        type: String,
        data: JSONObject,
        sharedKeyBase64: String,
        timestampMs: Long = System.currentTimeMillis(),
    ): ByteArray {
        val keyBytes = decodeKey(sharedKeyBase64)
        val iv = ByteArray(NONCE_LEN).also { rng.nextBytes(it) }
        val replayBytes = ByteArray(16).also { rng.nextBytes(it) }
        val replayHex = replayBytes.joinToString("") { "%02x".format(it) }

        val envelopeJson = JSONObject().apply {
            put("t", type)
            put("ts", timestampMs)
            put("nonce", replayHex)
            put("data", data)
        }
        val plaintext = envelopeJson.toString().toByteArray(Charsets.UTF_8)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(keyBytes, "AES"),
            GCMParameterSpec(TAG_BITS, iv)
        )
        cipher.updateAAD(AAD)
        val cipherAndTag = cipher.doFinal(plaintext)

        val out = ByteArray(1 + NONCE_LEN + cipherAndTag.size)
        out[0] = VERSION_BYTE
        System.arraycopy(iv, 0, out, 1, NONCE_LEN)
        System.arraycopy(cipherAndTag, 0, out, 1 + NONCE_LEN, cipherAndTag.size)
        return out
    }

    fun decryptEnvelope(
        encrypted: ByteArray,
        sharedKeyBase64: String,
        checkTimestamp: Boolean = true,
        nowMs: Long = System.currentTimeMillis(),
    ): JSONObject {
        require(encrypted.size >= 1 + NONCE_LEN + 16 + 2) { "Frame too short" }
        require(encrypted[0] == VERSION_BYTE) { "Unsupported version" }

        val keyBytes = decodeKey(sharedKeyBase64)
        val iv = encrypted.copyOfRange(1, 1 + NONCE_LEN)
        val cipherAndTag = encrypted.copyOfRange(1 + NONCE_LEN, encrypted.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(keyBytes, "AES"),
            GCMParameterSpec(TAG_BITS, iv)
        )
        cipher.updateAAD(AAD)
        val plaintext = cipher.doFinal(cipherAndTag)
        val obj = JSONObject(String(plaintext, Charsets.UTF_8))

        if (checkTimestamp) {
            val ts = obj.optLong("ts", 0L)
            require(ts > 0L && abs(nowMs - ts) <= MAX_REPLAY_WINDOW_MS) {
                "Rejected stale packet (clock skew)"
            }
        }
        return obj
    }

    fun wrapFrame(payload: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(4 + payload.size)
        buf.putInt(payload.size)
        buf.put(payload)
        return buf.array()
    }
}
