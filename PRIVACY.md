# Privacy & Security Architecture (`OtpBridge`)

`OtpBridge` is built from day one with **100% offline privacy** and **zero cloud infrastructure**.

## Core Guarantees

1. **Zero Cloud Servers, Zero Analytics, Zero Telemetry**
   - No backend server, no Firebase, no Crashlytics, no Google Fonts runtime downloads, no external SDKs.
   - No email login / OAuth / IMAP credentials ever requested or stored. Email OTPs are detected purely locally from Android notification previews via `NotificationListenerService`.

2. **Strict Local-Only Network Enforcement (`LocalNetworkGuard`)**
   - **Why does Android declare `android.permission.INTERNET`?**
     At the Linux/Android kernel level (`AID_INET`), Android requires the `INTERNET` permission to open *any* IP socket — including private local Wi-Fi (`192.168.x.x`) and USB loopback (`127.0.0.1`). Android does not provide a separate "local network only" permission.
   - **How OtpBridge guarantees zero internet traffic:**
     - Every single socket in both Dart (`lib/core/security/local_network_guard.dart`) and Android Kotlin (`NativeLocalNetworkGuard.kt`) passes through a hard security gate that **only allows IP literals in RFC1918 private LAN (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), link-local (`169.254.0.0/16`), and loopback (`127.0.0.1`, `::1`)**.
     - **Zero DNS queries:** Hostnames/domains are rejected before socket resolution.
     - **Public IPs throw a `SecurityException` / `LocalNetworkViolationException`.**
     - `network_security_config.xml` sets `cleartextTrafficPermitted="false"`.
     - If you want zero IP sockets entirely, you can disable Wi-Fi LAN and use **Bluetooth RFCOMM** directly.

3. **End-to-End Encryption (E2EE) on ALL Transports**
   - Even over your home/office Wi-Fi, USB, or Bluetooth, every packet is encrypted with **AES-256-GCM** using a 256-bit pre-shared key exchanged directly via QR code.
   - Associated Authenticated Data (`otpbridge:v1`), random 96-bit IV per packet, `±120s` timestamp window, and a seen-nonce replay cache block eavesdropping, tampering, and replay attacks.

4. **Ephemeral Data & Clipboard Privacy**
   - Only the extracted OTP code and service label are transmitted by default (message bodies are NOT sent).
   - Desktop stores received OTPs in RAM only (never written to disk).
   - On Windows, OTPs copied to clipboard include `ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory = 0`, and `CanUploadToCloudClipboard = 0` so sensitive bank/2FA codes do not stay in `Win+V`.
   - Configurable clipboard auto-clear (default 60 seconds, only clearing if the clipboard still holds that OTP).

5. **Store-Compliant Dual Android Flavors**
   - `foss` (GitHub / Cafe Bazaar / Myket): includes optional `RECEIVE_SMS` for hybrid capture.
   - `play` (Google Play): strips `RECEIVE_SMS` completely from the manifest and uses `NotificationListenerService` only.
