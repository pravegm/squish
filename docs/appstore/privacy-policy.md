# Squish Privacy Policy

*Effective: 23 October 2026 · Live at **https://pravegm.github.io/squish/privacy/** (source: `site/privacy/index.html`; keep the two in step). Paste that URL into App Store Connect as the Privacy Policy URL.*

**The short version: Squish doesn't collect any data about you.** There are no accounts, no ads, no analytics and no tracking, and the app makes no network requests of its own. Your collection stays on your phone.

## What Squish collects
Nothing. Squish has no sign-up and no login. It doesn't include advertising, analytics, crash-reporting or tracking code from anyone, and it doesn't ask for access to your camera, microphone, photos, contacts or location.

## What stays on your device
Your pressed specimens, shelf, unlocks, achievements in progress and settings are saved **only on your iPhone**. We can't see them. If you delete the app, they're deleted too. *(If a later version adds iCloud sync, it'll use your own iCloud account, and we'll update this policy first.)*

## Sharing
When you tap **Share**, Squish makes a short clip or image on your phone and hands it to the iOS share sheet. Where it goes next is up to you. Nothing is sent to us.

## Game Center (optional)
If you're signed in to Game Center, your achievements are handled by Apple under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). We don't receive your Game Center profile.

## Crash reports
If you've chosen in iOS Settings to share analytics with app developers, Apple may pass us anonymous crash reports. We use them only to fix bugs. You can turn this off at any time in **Settings → Privacy & Security → Analytics & Improvements**.

## Tracking
Squish doesn't track you across apps or websites, and it never asks for tracking permission.

## Children
Squish collects no personal information from anyone, including children.

## This website
The site has no cookies, analytics, trackers, embedded videos, external fonts or scripts. It is hosted on GitHub Pages. GitHub may log visitors' IP addresses for security purposes, under the [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## If you contact us
Support requests go through [GitHub Issues](https://github.com/pravegm/squish/issues). Anything posted there is **public** and is handled by GitHub under its privacy statement, so please don't include personal details you don't want others to see. We only use what you send to reply to you and fix the problem. We never add you to a mailing list. If you posted something personal by mistake, say so in the issue and we'll remove it.

## Changes
If this policy ever changes, we'll update this page and the dates at the top before the change takes effect in the app. The page's full history is public in the project repository.

## Contact
Squish, an independent app by GitHub user [pravegm](https://github.com/pravegm). Privacy questions: [open a support request](https://github.com/pravegm/squish/issues/new?template=support.yml).

*(Founder to decide: if a legal entity name or postal address is ever required, for example for EU trader status, add it here and on the live page. It's deliberately left off for now.)*

---

<!-- INTERNAL: delete everything below this line before publishing -->

## Internal: App Privacy ("nutrition label") answers in App Store Connect

| Question | Answer | Why |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** → the product page shows **"Data Not Collected"** | No SDKs and no network calls of our own. Apple defines "collect" as transmitting data off the device where you or partners can access it beyond real-time servicing; data processed only on device isn't "collected" |
| Game Center achievements | Not declared | Collected by Apple, not us. Apple says developers aren't responsible for disclosing data collected by Apple. We use no Game Center saves or multiplayer, so "Gameplay Content" doesn't apply |
| Crash logs via Apple's opt-in "Share with App Developers" | Not declared | Apple-collected. We add no third-party crash SDK. **If one is ever added, the label must change to declare Crash Data** |
| Tracking (ATT) | None. No `NSUserTrackingUsageDescription` in Info.plist | |
| Code check (23 Oct 2026) | No `URLSession`, `URLRequest`, `Network` framework, `URL(string:)`, web views, analytics or crash SDKs in `Squish/`. Only GameKit (Game Center) and local storage (UserDefaults, Application Support). No `NS*UsageDescription` keys in `project.yml` | Re-run the grep before each submission |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | Done: `Squish/PrivacyInfo.xcprivacy`. No tracking, no collected data types; required-reason APIs UserDefaults CA92.1, file metadata C617.1, elapsed time 35F9.1 | ✅ |

Re-check before every update: does any new code send anything off the device? If so, update the label **before** submitting.

Sources: Apple, *App privacy details*: https://developer.apple.com/app-store/app-privacy-details/ · Toastie's "Data Not Collected" listing as precedent (research 06 §1).
