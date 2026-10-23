# Squish: App Privacy answers (v1.0)

**Answer: Data Not Collected.** Verified against the code on 23 Oct 2026 (grep results below). Keep this file in step with `Squish/PrivacyInfo.xcprivacy` and the privacy policy (`privacy-policy.md`, live at https://pravegm.github.io/squish/privacy/).

## What to click (App Store Connect → the app → App Privacy)

1. **Privacy Policy URL:** `https://pravegm.github.io/squish/privacy/`. The tool pushes this too, as `privacyPolicyUrl`.
2. **Get Started:** "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
3. **Save**, then **Publish**. The product page shows **"Data Not Collected"**.

There is no tracking question to answer once you choose "No". For the record, Squish does not track: there's no IDFA, no `AppTrackingTransparency` and no data brokers.

## How to answer for Game Center (and other Apple services)

- **Answer:** declare nothing for Game Center. The "No" above stands.
- **Why:** Apple's guidance says: "You are not responsible for disclosing data collected by Apple." When the player signs in, GameKit sends their sign-in and achievement progress to Apple's Game Center servers. That is Apple collecting it, under Apple's privacy policy. Squish never receives or sends that data itself.
  - The one thing Squish reads back is the player's display name, shown only on the device in Settings ("Signed in · NAME", `Squish/UI/SettingsView.swift:169-171`). It never leaves the app, so under Apple's definition it isn't "collected".
- **The limit to watch:** Apple adds that if *you* collect data from Apple frameworks or services, you must declare it. Squish doesn't. If a future version ever sends Game Center player IDs to our own server, that would change the answer.
- **The same reasoning covers these:**
  - the **rating prompt** (`SKStoreReviewController` via SwiftUI `requestReview`, `Squish/UI/RootView.swift:38,428`). This is Apple's.
  - **App Store / TestFlight crash and diagnostics** that users opt into. These are Apple's; we have no crash SDK.
  - the **system share sheet** (`Squish/UI/SpecimenSharing.swift:172-173`). The user sends a picture or clip wherever they choose. It never comes to us.
- **Support contact:** support requests (GitHub issue forms, linked from the support page) happen outside the app. They aren't app data collection, and the privacy policy covers them.

## Evidence: grep of `Squish/` at `main`

| Looked for | Found |
|---|---|
| Networking: `URLSession`, `URLRequest`, `NWConnection`, `import Network`, `CFNetwork`, sockets | **None** |
| Web content: `WKWebView`, `SFSafariViewController`, `openURL`, SwiftUI `Link(` | **None**. The app has no outbound links at all |
| Analytics / crash / attribution SDKs: Firebase, Crashlytics, Sentry, Mixpanel, Amplitude, AdSupport, `ASIdentifierManager` | **None**. "Amplitude" only appears as the word in a synth comment (`Squish/Feedback/Synth.swift:65`) |
| Tracking: `AppTrackingTransparency`, `ATTrackingManager` | **None** |
| Cloud: `CloudKit`, `NSUbiquitousKeyValueStore` | **None**. The collection is local JSON and PNG files (`Squish/Collection/CollectionStore.swift`) |
| Notifications: `UNUserNotificationCenter`, remote registration | **None** |
| Frameworks imported (whole target) | AVFoundation, Combine, CoreGraphics, CoreHaptics, CoreImage, CoreMedia, CoreVideo, Foundation, GameKit, Metal, Observation, os, QuartzCore, RealityKit, simd, StoreKit (review prompt only), SwiftUI, UIKit. **No third-party packages** (`project.yml` has no package dependencies) |
| Logging | `os.Logger` only (`CollectionStore.swift:33`, `GameCenter.swift:25`). It writes to the device's unified log and is never uploaded by us |
| Privacy manifest | `Squish/PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no tracking domains, **no collected data types**. Required-reason APIs: UserDefaults `CA92.1`, file timestamp `C617.1`, system boot time `35F9.1` |

## Re-check before every submission

Run the same grep (`URLSession|URLRequest|NWConnection|WKWebView|SFSafari|openURL|Link\(|ATTrackingManager|ASIdentifier|CloudKit|Firebase|Sentry`), and check `project.yml` for new packages. If anything appears, this answer and the privacy manifest must change **before** upload.

**Saving to Photos** (see `DECISIONS.md` §6 #1, the missing `NSPhotoLibraryAddUsageDescription`) is an on-device write. Adding that key does not change the label.

## Source

- Apple, *App privacy details on the App Store*: https://developer.apple.com/app-store/app-privacy-details/
  - "Collect" means transmitting data off the device beyond what's needed to service a request in real time.
  - "You are not responsible for disclosing data collected by Apple."
