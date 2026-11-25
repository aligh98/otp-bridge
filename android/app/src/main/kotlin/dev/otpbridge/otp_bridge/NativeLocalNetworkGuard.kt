package dev.otpbridge.otp_bridge

import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Strict Zero-Internet Guard on Android.
 *
 * Only allows numeric IPv4/IPv6 literals inside RFC1918 LAN, link-local, or
 * loopback ranges. Rejects ALL public IPs and rejects hostnames (zero DNS queries).
 */
object NativeLocalNetworkGuard {
    private val ipv4Literal = Regex("""^\d{1,3}(\.\d{1,3}){3}$""")
    private val ipv6Literal = Regex("""^[0-9a-fA-F:]+(?:\d{1,3}(?:\.\d{1,3}){3})?$""")

    fun isAllowedLocalIp(host: String): Boolean {
        val trimmed = host.trim()
        if (trimmed.isEmpty()) return false

        // Strictly require a pure numeric IPv4 or hex IPv6 literal BEFORE calling
        // InetAddress.getByName so Android NEVER performs a DNS query (e.g. "evil.com:80").
        val looksIpv4 = ipv4Literal.matches(trimmed)
        val looksIpv6 = trimmed.contains(':') && ipv6Literal.matches(trimmed)
        if (!looksIpv4 && !looksIpv6) {
            return false
        }

        if (looksIpv4) {
            val parts = trimmed.split('.')
            if (parts.any { (it.toIntOrNull() ?: 256) !in 0..255 }) return false
        }

        return try {
            val addr = InetAddress.getByName(trimmed)
            isAllowedAddress(addr)
        } catch (_: Exception) {
            false
        }
    }

    fun isAllowedAddress(addr: InetAddress): Boolean {
        if (addr.isLoopbackAddress) return true
        val b = addr.address
        if (addr is Inet4Address && b.size == 4) {
            return isAllowedIpv4Bytes(b[0].toInt() and 0xFF, b[1].toInt() and 0xFF)
        }
        if (addr is Inet6Address && b.size == 16) {
            // IPv4-mapped IPv6 (::ffff:a.b.c.d)
            var isMapped = true
            for (i in 0 until 10) {
                if (b[i].toInt() != 0) {
                    isMapped = false
                    break
                }
            }
            if (isMapped && (b[10].toInt() and 0xFF) == 0xFF && (b[11].toInt() and 0xFF) == 0xFF) {
                return isAllowedIpv4Bytes(b[12].toInt() and 0xFF, b[13].toInt() and 0xFF)
            }

            val b0 = b[0].toInt() and 0xFF
            val b1 = b[1].toInt() and 0xFF
            if (b0 == 0xFE && (b1 and 0xC0) == 0x80) return true // fe80::/10
            if ((b0 and 0xFE) == 0xFC) return true               // fc00::/7
            return false
        }
        return false
    }

    private fun isAllowedIpv4Bytes(b0: Int, b1: Int): Boolean {
        if (b0 == 127) return true                         // 127.0.0.0/8 (USB adb reverse)
        if (b0 == 10) return true                          // 10.0.0.0/8
        if (b0 == 172 && b1 in 16..31) return true         // 172.16.0.0/12
        if (b0 == 192 && b1 == 168) return true            // 192.168.0.0/16
        if (b0 == 169 && b1 == 254) return true            // 169.254.0.0/16
        return false
    }

    fun requireAllowedAddress(host: String): InetAddress {
        if (!isAllowedLocalIp(host)) {
            throw SecurityException(
                "OtpBridge blocked non-local destination '$host' (zero-internet enforcement)"
            )
        }
        return InetAddress.getByName(host.trim())
    }
}
