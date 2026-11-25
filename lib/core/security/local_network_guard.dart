import 'dart:io';

/// Strict zero-internet network guard.
///
/// Even though operating systems require socket permissions for local Wi-Fi,
/// OtpBridge enforces at the application layer that ONLY private RFC1918 LAN,
/// link-local, or loopback IP literals are ever contacted. Public IPs and DNS
/// hostnames are unconditionally rejected.
class LocalNetworkGuard {
  LocalNetworkGuard._();

  /// Returns true ONLY if [host] is an explicit IP literal in loopback,
  /// RFC1918 private LAN, IPv4 link-local, or IPv6 ULA/link-local ranges.
  ///
  /// Any domain name (to prevent DNS leakage) or public IP returns false.
  static bool isAllowedLocalAddress(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return false;

    final parsed = InternetAddress.tryParse(trimmed);
    if (parsed == null) {
      // Never allow hostnames / DNS resolution.
      return false;
    }

    return isAllowedInternetAddress(parsed);
  }

  static bool isAllowedInternetAddress(InternetAddress address) {
    if (address.isLoopback) return true;

    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final b0 = bytes[0];
      final b1 = bytes[1];

      // 127.0.0.0/8 - Loopback (USB adb reverse)
      if (b0 == 127) return true;

      // 10.0.0.0/8 - RFC1918 Class A private
      if (b0 == 10) return true;

      // 172.16.0.0/12 - RFC1918 Class B private
      if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;

      // 192.168.0.0/16 - RFC1918 Class C private
      if (b0 == 192 && b1 == 168) return true;

      // 169.254.0.0/16 - RFC3927 Link-local (direct hotspot / ad-hoc)
      if (b0 == 169 && b1 == 254) return true;

      return false;
    }

    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      // IPv4-mapped IPv6 (::ffff:a.b.c.d) -> evaluate embedded IPv4 strictly
      var isIpv4Mapped = true;
      for (var i = 0; i < 10; i++) {
        if (bytes[i] != 0) {
          isIpv4Mapped = false;
          break;
        }
      }
      if (isIpv4Mapped && bytes[10] == 0xff && bytes[11] == 0xff) {
        final b0 = bytes[12];
        final b1 = bytes[13];
        return b0 == 127 ||
            b0 == 10 ||
            (b0 == 172 && b1 >= 16 && b1 <= 31) ||
            (b0 == 192 && b1 == 168) ||
            (b0 == 169 && b1 == 254);
      }

      // fe80::/10 - Link-local
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;

      // fc00::/7 - Unique Local Address (ULA)
      if ((bytes[0] & 0xfe) == 0xfc) return true;

      return false;
    }

    return false;
  }

  /// Throws [LocalNetworkViolationException] if [host] is not a strict
  /// local/private IP address.
  static InternetAddress assertAllowedHost(String host) {
    final parsed = InternetAddress.tryParse(host.trim());
    if (parsed == null || !isAllowedInternetAddress(parsed)) {
      throw LocalNetworkViolationException(
        'Blocked non-local destination "$host". OtpBridge strictly forbids '
        'public IPs and DNS lookups to guarantee zero internet traffic.',
      );
    }
    return parsed;
  }

  /// Lists all active local private IPv4 addresses on this machine, sorted with
  /// standard home/office LAN ranges (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
  /// prioritized ahead of virtual/link-local interfaces.
  static Future<List<String>> getLocalPrivateIpv4Addresses() async {
    final results = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final lowerName = iface.name.toLowerCase();
        // Skip common container/VPN tunnel interfaces when advertising LAN IP.
        if (lowerName.startsWith('docker') ||
            lowerName.startsWith('br-') ||
            lowerName.startsWith('veth') ||
            lowerName.startsWith('virbr') ||
            lowerName.startsWith('tun') ||
            lowerName.startsWith('wg')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (isAllowedInternetAddress(addr) && !addr.isLoopback) {
            results.add(addr.address);
          }
        }
      }
    } catch (_) {
      // Fallback gracefully if interface enumeration fails.
    }

    results.sort((a, b) => _ipPriority(a).compareTo(_ipPriority(b)));
    return results.toSet().toList();
  }

  static int _ipPriority(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    if (ip.startsWith('172.')) return 2;
    return 3;
  }
}

class LocalNetworkViolationException implements Exception {
  LocalNetworkViolationException(this.message);
  final String message;

  @override
  String toString() => 'LocalNetworkViolationException: $message';
}
