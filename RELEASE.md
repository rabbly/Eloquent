# Eloquent — App Store Release Guide

This document tracks what's done and what remains to ship Eloquent on the Mac App Store.

---

## ⚠️ Critical decision first: call-detection method

Eloquent currently detects calls by enumerating **all system audio processes** via CoreAudio
(`kAudioHardwarePropertyProcessObjectList`) and reading other apps' bundle IDs and mic-input
state (`kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningInput`) in
`Eloquent/CallDetection/MicActivityWatcher.swift`.

**This will very likely be rejected by Mac App Store review.** It's an undocumented/private API
used for cross-app monitoring — App Review treats this as both a private-API violation and a
privacy violation, and there is no entitlement that authorizes it.

> **The app currently runs with App Sandbox OFF** (`Eloquent/App/Eloquent.entitlements` is an
> empty `<dict/>`). That is what allows the CoreAudio process-enumeration detection to work today.
> The Mac App Store **requires** App Sandbox to be enabled — and enabling it will break the
> current detection method. This is the core tension: **the feature as built and App Store
> distribution are mutually exclusive.**

### Options
1. **Ship outside the App Store** (Developer ID + notarization, distribute via your own website).
   The CoreAudio approach works fine here, sandbox stays off. Lowest friction, keeps the feature.
   **Recommended given how the app works today.**
2. **Rework detection for the App Store**: enable App Sandbox + microphone entitlements (see the
   commented block below), drop per-app detection, and rely on manual mode only or detect the
   app's *own* mic tap. Loses automatic call detection.
3. **Hybrid**: App Store build uses manual mode + own-mic; a direct-download build keeps auto-detect.

Decide this before investing in App Store submission — it likely points you to Developer ID instead.

---

## 📦 Current distribution: .dmg (Developer ID path)

Run `./package.sh` to produce `build/Eloquent.dmg` — a Release build with a drag-to-`/Applications`
installer layout. The script prints the signing/notarization commands at the end.

- **On your own Mac:** the unsigned `.dmg` installs and runs as-is.
- **For other people's Macs:** you must sign + notarize, or Gatekeeper will block it:
  1. Sign the `.app` with a **Developer ID Application** certificate (requires Apple Developer
     Program membership) using `codesign --options runtime` (Hardened Runtime is already on).
  2. `xcrun notarytool submit build/Eloquent.dmg --keychain-profile NOTARY --wait`
  3. `xcrun stapler staple build/Eloquent.dmg`

Sandbox stays **off** for this path, so the CoreAudio call-detection keeps working.

### If you choose the App Store path, these are the entitlements to restore
`Eloquent/App/Eloquent.entitlements` (currently empty) would need:
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.microphone</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
```
…and `MicActivityWatcher.swift` must be reworked, because process enumeration fails under sandbox.

---

## ✅ Done in the project

- App renamed to **Eloquent** (target, scheme, product, folders, bundle strings).
- App icon set (1024→16px) in `Assets.xcassets/AppIcon.appiconset`.
- Menu bar template icon (`MenuBarIcon.imageset`).
- Privacy usage strings in `Info.plist` (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).
- **Privacy manifest** `Eloquent/App/PrivacyInfo.xcprivacy` — declares no tracking, no data
  collection, and the UserDefaults access reason (CA92.1). Bundled into `Contents/Resources/`.
- App category (`public.app-category.productivity`) and copyright in `Info.plist`.
- Version wired to `MARKETING_VERSION` (1.0) and build to `CURRENT_PROJECT_VERSION` (1) in `project.yml`.
- Hardened Runtime enabled.
- ⚠️ App Sandbox is currently **OFF** (empty entitlements) — required for the current detection
  method to work, but incompatible with the App Store. See the critical decision above.

---

## ☐ You must do (requires your Apple account / decisions)

### 1. Apple Developer Program
- Enrol at developer.apple.com ($99/yr).
- Note your 10-character **Team ID**.

### 2. Identifiers & signing (edit `project.yml`, then `xcodegen generate`)
- `PRODUCT_BUNDLE_IDENTIFIER`: change `com.yourname.Eloquent` → reverse-DNS you own (e.g. `com.yourcompany.eloquent`).
- `DEVELOPMENT_TEAM`: set to your Team ID.
- In App Store Connect, register the matching App ID / bundle identifier.
- Confirm the app name **"Eloquent"** is available (App Store Connect will tell you; it may be taken).

### 3. App Store Connect record
- Create the app; set primary language, category (Productivity), etc.
- **Screenshots** (required) — at least one 2560×1600 (or supported size) showing the menu + a banner.
- **Description, subtitle, keywords, support URL, marketing URL.**
- **Privacy policy URL** (required even for no-data apps — state that all processing is on-device
  and nothing is collected or transmitted).
- **App Privacy "nutrition label"**: select "Data Not Collected."

### 4. Build & submit
- In Xcode: select the **Eloquent** scheme → Any Mac (Apple Silicon/Intel) → Product ▸ Archive.
- In the Organizer, **Distribute App ▸ App Store Connect ▸ Upload** (Mac App Store distribution
  handles signing + notarization).
- Attach the build to your App Store Connect version and **Submit for Review**.
- In review notes, explain the microphone + on-device speech usage plainly.

### 5. Increment on each upload
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every new build uploaded.

---

## Notes on the on-device story (use it as a selling point)

Everything runs locally via Apple's `SpeechAnalyzer` / on-device `SFSpeechRecognizer`. No audio,
transcript, or usage data leaves the machine. Emphasise this in the description and privacy label —
it's a genuine differentiator and simplifies the privacy review.

## If you go the Developer ID (non-App-Store) route instead

- Keep the current CoreAudio detection.
- Sign with a **Developer ID Application** certificate, enable Hardened Runtime (already on),
  and **notarize** with `notarytool`, then **staple** the ticket.
- Distribute the `.app` (in a `.dmg` or `.zip`) from your own site. No App Review.
