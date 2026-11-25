# OtpBridge

**100% Offline, Open-Source, End-to-End Encrypted Android → PC (Windows & Linux) OTP Bridge built with Flutter.**

Automatically detects incoming **Persian & English OTP codes** (Iranian bank Ramz Pooya, SMS, Email notifications, RCS, messengers) locally on Android — with **no email login** and **zero cloud servers** — and delivers them straight to your Windows or Linux clipboard with a sleek **"✓ Copied — Ready to paste (Ctrl+V)"** badge.

---

## Highlights

- **Zero Internet / Zero Cloud:** Direct device-to-device transfer only. Enforced by `LocalNetworkGuard` (hard-blocks all public IPs & DNS lookups). See [PRIVACY.md](PRIVACY.md).
- **End-to-End Encrypted (AES-256-GCM):** QR-paired 256-bit key + replay protection across **all 3 transports**.
- **3 Optional Transports:**
  - **Local Wi-Fi (LAN)** — *Default*, with automatic UDP LAN discovery if DHCP changes your PC's IP.
  - **USB Cable (`adb reverse`)** — 100% VPN-proof and Wi-Fi-independent.
  - **Direct Bluetooth Classic (RFCOMM)** — Native Android Kotlin + Linux BlueZ + Windows Winsock2 `AF_BTH`.
- **Hybrid Android Capture (Works Even When UI Is Closed):**
  - Native Kotlin `NotificationListenerService` (Email apps like Gmail/Outlook/Yahoo/Thunderbird, SMS/RCS, messengers — **zero email login**).
  - Optional `RECEIVE_SMS` (`foss` flavor for GitHub/Bazaar/Myket; cleanly omitted in `play` flavor for Google Play).
  - 15-second deduplicator prevents duplicate events.
- **High-Precision Bilingual OTP Engine (Persian + English):**
  - Multi-stage normalization (Persian/Arabic digits, ZWNJ, Arabic Yeh/Kaf, bidi chars), non-OTP entity masking (cards, amounts, IBANs, dates, times, phones, tracking/order/invoice IDs), and contextual scoring.
  - Verified against 85+ real-world Persian & English test vectors (**100% True Positive Recall / 0% False Positives**).
  - Includes an in-app **Parser Lab** to test any SMS/email live.
- **Desktop Auto-Copy & Privacy UX (Windows & Linux):**
  - Auto-Copy enabled by default (toggleable to 1-click copy).
  - Sleek ready-to-paste floating badge + System Tray menu + native OS notifications.
  - Windows `Win+V` Clipboard History exclusion + timed clipboard auto-clear.
- **Optional Device-Aware Android Setup Guide:**
  - Detects Android 13+ (API 33+) Sideload Restricted Settings and device OEM (Xiaomi/HyperOS, Samsung OneUI, Huawei/Honor, Oppo/Realme/OnePlus, Stock Android) with direct deep-link buttons.

---

## Building from Source

### Prerequisites
- Flutter SDK (`>= 3.24` / `3.50+`)
- **Android:** Android SDK (API 34+), JDK 17
- **Linux Desktop:** `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev libbluetooth-dev libnotify-dev`
- **Windows Desktop:** Visual Studio 2022 ("Desktop development with C++")

### Run Tests
```bash
flutter test
```

### Build Android APKs
```bash
# GitHub / Cafe Bazaar / Myket (Hybrid NotificationListener + optional RECEIVE_SMS)
flutter build apk --release --flavor foss

# Google Play compliant (NotificationListener only, zero SMS permissions)
flutter build apk --release --flavor play
```

### Build Desktop Apps
```bash
# Linux
flutter build linux --release

# Windows
flutter build windows --release
```

---

## License

MIT License — see [LICENSE](LICENSE).
