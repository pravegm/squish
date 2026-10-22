# Squish Privacy Policy

*Effective: [release date, e.g. 24 November 2026] · Publish at `https://[domain]/privacy` and paste that URL into App Store Connect.*

**The short version: Squish doesn't collect any data about you.** There are no accounts, no ads, no analytics and no tracking. Your collection stays on your phone.

## What Squish collects
Nothing. Squish has no sign-up and no login, and it doesn't include advertising, analytics or tracking code from anyone.

## What stays on your device
Your pressed specimens, shelf, unlocks and settings are saved **only on your iPhone**. We can't see them. If you delete the app, they're deleted too. *(If a later version adds iCloud sync, it'll use your own iCloud account, and we'll update this policy first.)*

## Sharing
When you tap **Share**, Squish makes a short clip or image on your phone and hands it to the iOS share sheet. Where it goes next is up to you. Nothing is sent to us.

## Game Center (optional)
If you're signed in to Game Center, your achievements are handled by Apple under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). We don't receive your Game Center profile.

## Crash reports
If you've chosen in iOS Settings to share analytics with app developers, Apple may pass us anonymous crash reports. We use them only to fix bugs. You can turn this off at any time in **Settings → Privacy & Security → Analytics & Improvements**.

## Tracking
Squish doesn't track you across apps or websites, and it never asks for tracking permission.

## Children
Squish is rated 9+. It collects no personal information from anyone, including children.

## If you email us
If you contact support, we'll use your email address and message only to reply to you, and we delete them once the conversation is over. We never add you to a mailing list.

## Changes
If this policy ever changes, we'll update this page and the date at the top before the change takes effect in the app.

## Contact
[Studio legal name] · [support email] · [postal address if required by local law]

---

<!-- INTERNAL: delete everything below this line before publishing -->

## Internal: App Privacy ("nutrition label") answers in App Store Connect

| Question | Answer | Why |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** → the product page shows **"Data Not Collected"** | No SDKs and no network calls of our own. Apple defines "collect" as transmitting data off the device where you or partners can access it beyond real-time servicing; data processed only on device isn't "collected" |
| Game Center achievements | Not declared | Collected by Apple, not us. Apple says developers aren't responsible for disclosing data collected by Apple. We use no Game Center saves or multiplayer, so "Gameplay Content" doesn't apply |
| Crash logs via Apple's opt-in "Share with App Developers" | Not declared | Apple-collected. We add no third-party crash SDK. **If one is ever added, the label must change to declare Crash Data** |
| Tracking (ATT) | None. No `NSUserTrackingUsageDescription` in Info.plist | |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | Dev: include it with `NSPrivacyTracking = false`, no collected data types, and the required-reason API entries actually used (e.g. `UserDefaults` CA92.1, file timestamp) | |

Re-check before every update: does any new code send anything off the device? If so, update the label **before** submitting.

Sources: Apple, *App privacy details*: https://developer.apple.com/app-store/app-privacy-details/ · Toastie's "Data Not Collected" listing as precedent (research 06 §1).
