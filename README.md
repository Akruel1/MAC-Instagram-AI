<p align="center">
  <img src="Resources/AppIcon/app-icon-256.png" width="128" height="128" alt="Instagram AI Studio icon">
</p>

<h1 align="center">Instagram AI Studio</h1>

<p align="center">
  <strong>A native macOS studio for local Instagram creative work</strong><br>
  Graphite interface · muted amber accents · Keychain-backed credentials · on-device first
</p>

<p align="center">
  macOS&nbsp;14+ · Intel&nbsp;x86_64 · Apple&nbsp;Silicon&nbsp;arm64
</p>

<p align="center">
  <a href="https://github.com/Akruel1/MAC-Instagram-AI/releases/download/v0.3.0/InstagramAIStudio-0.3.0-macOS-Intel-x86_64.dmg"><strong>Download for Intel Mac</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Akruel1/MAC-Instagram-AI/releases/download/v0.3.0/InstagramAIStudio-0.3.0-macOS-AppleSilicon-arm64.dmg"><strong>Download for Apple Silicon</strong></a>
</p>

<p align="center">
  <sub>Direct links to the v0.3.0 release assets. Filenames must match exactly.</sub>
</p>

---

## What it is

Instagram AI Studio is a **native SwiftUI** macOS application for managing local creative workflows around Instagram content. It emphasizes honest empty states, local persistence, and optional connections — never fabricated AI replies or forced cloud accounts.

## Capabilities

| Area | Status |
|------|--------|
| Overview & setup guidance | Available |
| Assistant (Claude, when configured) | Available — no fabricated replies if Claude is missing |
| Analytics (observed Instagram metrics) | Available when Instagram is connected |
| Integrations & dependency diagnostics | Available |
| Settings, Keychain credentials, local preferences | Available |
| Optional donations (crypto addresses + local QR) | Available |
| **Studio video editor** | **Coming soon** — intentionally gated in this release |

## Installation

1. Download the DMG that matches your Mac architecture.
2. Open the DMG and drag **Instagram AI Studio** into **Applications**.
3. Launch from Applications (see Gatekeeper notes below).

### Choose the correct build

| Your Mac | Download |
|----------|----------|
| Intel (x86_64) | `InstagramAIStudio-0.3.0-macOS-Intel-x86_64.dmg` |
| Apple Silicon (M-series) | `InstagramAIStudio-0.3.0-macOS-AppleSilicon-arm64.dmg` |

Checksums ship with each GitHub Release (`SHA256SUMS.txt`).

## Gatekeeper & signing

This release is **not signed with an Apple Developer ID** and has **not been notarized by Apple**. macOS may block the first launch. Use one of the methods below — do **not** disable Gatekeeper, run `spctl --master-disable`, or strip quarantine attributes.

### Method A — Control-click

1. Download the DMG for your Mac architecture.
2. Open the DMG and drag **Instagram AI Studio** into **Applications**.
3. In **Finder**, Control-click (right-click) the app and choose **Open**, if macOS offers this option.
4. Confirm **Open** when prompted.

### Method B — Privacy & Security

1. Attempt to open **Instagram AI Studio** from Applications.
2. If macOS blocks it, open **System Settings → Privacy & Security**.
3. Select **Open Anyway** when it appears for Instagram AI Studio.
4. Confirm the launch when asked.

When a Developer ID–signed and notarized build is published, this section will be updated.

## Feature availability & limitations

- **Studio** remains visible in the sidebar but is marked **Coming soon**. The editor UI is not offered in this release.
- **Claude** and **Instagram** connections are optional. Live API flows require your own credentials and are **not pre-verified** in CI.
- No account registration is required for personalization; your display name stays on this Mac.
- Donations are optional. No payment processing, wallet connection, or seed-phrase requests.

## Local dependencies

| Dependency | Required? | Notes |
|------------|-----------|-------|
| macOS 14+ | Yes | Intel or Apple Silicon |
| FFmpeg / FFprobe | Optional tooling | Detected from MacPorts (`/opt/local`), Homebrew Apple Silicon (`/opt/homebrew`), Homebrew Intel (`/usr/local`), or `PATH`. **Not bundled.** |
| Claude API key | Optional | Stored in Keychain when you add it |
| Meta / Instagram credentials | Optional | For Analytics sync when configured |

Use **Integrations** inside the app for discovery and install guidance.

## Privacy

- Secrets use the macOS **Keychain** (`com.instagramaistudio` service namespace).
- Local state uses on-disk SQLite under Application Support.
- Display names and preferences are local only.
- Donation wallet addresses are immutable app configuration — never fetched remotely.
- Clipboard contents from “Copy address” are not logged.

## Develop / build from source

Requirements: Xcode 16+ (or matching Swift toolchain), macOS 14+.

```bash
git clone https://github.com/Akruel1/MAC-Instagram-AI.git
cd MAC-Instagram-AI

swift build
swift test
swift run TestHarness

# Generate .icns from Resources/AppIcon/AppIcon-master.png
Scripts/generate_app_icon.sh

# Architecture-specific app + DMG (local; does not publish)
Scripts/package_macos_app.sh release x86_64
Scripts/package_dmg.sh x86_64
Scripts/package_macos_app.sh release arm64
Scripts/package_dmg.sh arm64
```

Release automation: `.github/workflows/release.yml` (tag `v*`). Publishing still requires maintainer approval.

## Support the project

Optional crypto donations are available from the in-app **Donate** button. Networks and addresses are shown in the app with local QR codes — always verify the network before sending.

## License

No license file is published in this repository yet. All rights reserved until a license is added.
