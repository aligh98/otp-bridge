# OtpBridge Technical Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                         ANDROID (Kotlin + Flutter)                    │
│                                                                       │
│  ┌──────────────────────────────┐  ┌───────────────────────────────┐  │
│  │ OtpNotificationListenerSvc   │  │ SmsBroadcastReceiver (foss)   │  │
│  │ (Email, SMS, RCS, Messengers)│  │ (Optional direct SMS hybrid)  │  │
│  └──────────────┬───────────────┘  └───────────────┬───────────────┘  │
│                 └──────────────┬───────────────────┘                  │
│                                ▼                                      │
│                    NativeOtpEngine (Kotlin)                           │
│           [Normalizer → EntityMasker → SignalGate → Scorer]           │
│                                │                                      │
│                   15s Deduplicator (NativePrefsStore)                 │
│                                │                                      │
│                 NativeE2eeCrypto (AES-256-GCM + AAD)                  │
│                                │                                      │
│         ┌──────────────────────┼──────────────────────┐               │
│         ▼                      ▼                      ▼               │
│  Local Wi-Fi LAN         USB Loopback            Bluetooth Classic    │
│  (RFC1918 + UDP)       (127.0.0.1:47831)        (RFCOMM SPP UUID)     │
│  [NativeLocalNetworkGuard blocks all public IPs & DNS lookups]        │
└─────────┼──────────────────────┼──────────────────────┼───────────────┘
          │                      │                      │
          ▼                      ▼                      ▼
┌───────────────────────────────────────────────────────────────────────┐
│                    DESKTOP: WINDOWS & LINUX (Flutter + C++)           │
│                                                                       │
│  DesktopLanServer ◄──(Wi-Fi & USB adb reverse)   Native C++ RFCOMM    │
│  (LocalNetworkGuard + AES-256-GCM + Replay)      (Win32 / BlueZ)      │
│                                │                                      │
│                      15s Deduplicator                                 │
│                                │                                      │
│            ┌───────────────────┴───────────────────┐                  │
│            ▼                                       ▼                  │
│   DesktopClipboardService               DesktopTrayController +       │
│   • Auto-Copy (default ON)              OtpReadyToastCard             │
│   • Win+V History Exclusion (Win32)     • "✓ کپی شد — آماده پیست"     │
│   • Timed Auto-Clear (default 60s)      • System Tray 1-click history │
└───────────────────────────────────────────────────────────────────────┘
```

## Wire Protocol

Every frame across Wi-Fi LAN, USB Loopback, and Bluetooth RFCOMM uses the exact same binary framing:

```
[4 bytes: big-endian uint32 payload_length]
[1 byte : protocol_version = 0x01]
[12 bytes: random AES-GCM IV/nonce]
[N bytes : AES-256-GCM ciphertext of JSON envelope]
[16 bytes: GCM authentication tag]
```

- **AAD:** `UTF-8("otpbridge:v1")`
- **Plaintext JSON Envelope:**
  ```json
  {
    "t": "otp",
    "ts": 1764000000000,
    "nonce": "32-hex-random-bytes",
    "data": {
      "id": "uuid",
      "code": "649281",
      "sender": "بانک ملت",
      "source": "sms",
      "ts": 1764000000000,
      "transport": "wifiLan",
      "confidence": 0.99
    }
  }
  ```
- **Replay Protection:** Desktop rejects packets whose `ts` differs by more than `±120s` or whose `nonce` was already seen.

## OTP Parser Precision & Recall Engineering

The parser (`lib/core/otp_parser/` & `NativeOtpEngine.kt`) uses a deterministic 6-stage pipeline rather than a single naive regex:

1. **Normalization:** Persian (`۰-۹`), Arabic-Indic (`٠-٩`), and fullwidth digits → ASCII `0-9`; strips invisible bidi marks & diacritics; unifies ZWNJ and Arabic `ي`/`ك`/`أ`/`إ` variants.
2. **Standard Matchers:** WebOTP (`@domain.tld #123456`) and Google explicit (`G-123456` → strips `G-` for direct paste).
3. **Entity Masking:** Replaces URLs, emails, IBANs, masked/full card numbers (`6104****4821`), dates (Jalali & Gregorian), times, currency amounts (`2,500,000 ریال`, `$149.99`), durations (`120 ثانیه`), phone numbers, USSD codes, and non-OTP named IDs (`کد پیگیری`, `کد رهگیری`, `شماره سفارش`, `کد تخفیف`, `Order #`, `Invoice #`, `Tracking #`) with same-length placeholders.
4. **Signal & Negative Gate:** Rejects any message lacking OTP/auth keywords, and rejects transactional/promotional/tracking messages that lack a strong OTP keyword.
5. **Candidate Extraction:** Extracts 4–8 digit codes, 3+3 split codes (`482-910` → `482910`), and tightly keyword-bound alphanumeric codes (`K7M9P2`).
6. **Contextual Scoring:** Scores proximity to strong/medium keywords, delimiter binding, length priors, standalone lines, anti-sharing disclaimers, calendar year penalties, and local negative proximity penalties.
