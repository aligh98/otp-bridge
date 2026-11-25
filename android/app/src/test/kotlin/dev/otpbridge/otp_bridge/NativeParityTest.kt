package dev.otpbridge.otp_bridge

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.SecureRandom
import java.util.Base64

class NativeParityTest {

    private fun loadCorpus(): JSONObject {
        val candidates = listOf(
            File("../../test/test_vectors/otp_corpus.json"),
            File("../test/test_vectors/otp_corpus.json"),
            File("test/test_vectors/otp_corpus.json"),
        )
        val file = candidates.firstOrNull { it.exists() }
            ?: error("Could not locate otp_corpus.json from ${File(".").absolutePath}")
        return JSONObject(file.readText(Charsets.UTF_8))
    }

    @Test
    fun nativeOtpEngineMatchesAllTruePositivesAndRejectsAllTrueNegatives() {
        val corpus = loadCorpus()
        val tps = corpus.getJSONArray("true_positives")
        for (i in 0 until tps.length()) {
            val item = tps.getJSONObject(i)
            val id = item.getString("id")
            val title = item.optString("title", "").ifBlank { null }
            val body = item.getString("body")
            val expectedCode = item.getString("expected_code")
            val expectedSender = item.optString("expected_sender", "").ifBlank { null }

            val res = NativeOtpEngine.parse(title = title, body = body)
            assertTrue("Kotlin NativeOtpEngine missed OTP [$id] (score=${res.score})", res.isOtp)
            assertEquals("Kotlin wrong code on [$id]", expectedCode, res.code)
            if (expectedSender != null) {
                assertEquals("Kotlin wrong sender on [$id]", expectedSender, res.sender)
            }
        }

        val tns = corpus.getJSONArray("true_negatives")
        for (i in 0 until tns.length()) {
            val item = tns.getJSONObject(i)
            val id = item.getString("id")
            val title = item.optString("title", "").ifBlank { null }
            val body = item.getString("body")

            val res = NativeOtpEngine.parse(title = title, body = body)
            assertFalse(
                "Kotlin NativeOtpEngine FALSE POSITIVE on [$id]: extracted '${res.code}' (score=${res.score})",
                res.isOtp,
            )
        }
    }

    @Test
    fun nativeLocalNetworkGuardStrictlyBlocksPublicIpsAndHostnames() {
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("127.0.0.1"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("::1"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("192.168.1.42"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("10.0.0.5"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("172.16.0.1"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("172.31.255.254"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("169.254.10.20"))
        assertTrue(NativeLocalNetworkGuard.isAllowedLocalIp("::ffff:192.168.1.5"))

        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("8.8.8.8"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("1.1.1.1"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("::ffff:8.8.8.8"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("172.15.0.1"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("172.32.0.1"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("192.168.1.999"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("google.com"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("google.com:80"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp("localhost"))
        assertFalse(NativeLocalNetworkGuard.isAllowedLocalIp(""))
    }

    @Test
    fun nativeE2eeCryptoRoundtripAndTamperAndReplayRejection() {
        val rng = SecureRandom()
        val keyBytes = ByteArray(32).also { rng.nextBytes(it) }
        val key1 = Base64.getUrlEncoder().withoutPadding().encodeToString(keyBytes)
        val key2Bytes = ByteArray(32).also { rng.nextBytes(it) }
        val key2 = Base64.getUrlEncoder().withoutPadding().encodeToString(key2Bytes)

        val now = System.currentTimeMillis()
        val data = JSONObject().put("code", "649281").put("sender", "بانک ملت")
        val encrypted = NativeE2eeCrypto.encryptEnvelope("otp", data, key1, timestampMs = now)

        val decrypted = NativeE2eeCrypto.decryptEnvelope(encrypted, key1, nowMs = now)
        assertEquals("otp", decrypted.getString("t"))
        assertEquals("649281", decrypted.getJSONObject("data").getString("code"))
        assertEquals("بانک ملت", decrypted.getJSONObject("data").getString("sender"))

        // Wrong key must throw
        try {
            NativeE2eeCrypto.decryptEnvelope(encrypted, key2, nowMs = now)
            fail("Expected failure with wrong key")
        } catch (_: Exception) {
        }

        // Tampered byte must throw
        val tampered = encrypted.copyOf()
        tampered[tampered.size - 4] = (tampered[tampered.size - 4].toInt() xor 0x01).toByte()
        try {
            NativeE2eeCrypto.decryptEnvelope(tampered, key1, nowMs = now)
            fail("Expected failure on tampered ciphertext")
        } catch (_: Exception) {
        }

        // Stale timestamp (>120s) must throw
        val stale = NativeE2eeCrypto.encryptEnvelope("otp", data, key1, timestampMs = now - 300_000L)
        try {
            NativeE2eeCrypto.decryptEnvelope(stale, key1, nowMs = now)
            fail("Expected failure on stale timestamp")
        } catch (_: IllegalArgumentException) {
        }
    }
}
