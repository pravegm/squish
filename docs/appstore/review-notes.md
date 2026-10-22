# Squish: App Review notes (v1.0)

## Where this goes
App Store Connect → the version → **App Review Information**:
- **Sign-in required:** **No** (there are no accounts).
- **Contact:** founder name, phone and email.
- **Notes:** paste the block below. It's **3,663 characters** (all ASCII). The Notes field is generally 4,000 bytes; I couldn't confirm that on Apple's help pages, so check the counter in the form.
- **Attachment (recommended):** a 20–30 s screen recording of a Duo press, plus a 10 s Pinch Press recording on a non-Duo iPhone. Reviewers may not have a Duo to hand.

Guideline 2.3.1(a) says features must be described "with specificity" (generic notes are rejected). The block below is specific on purpose.

```
Thanks for reviewing Squish, a paid toy with no ads, no in-app purchases, no accounts and no login.

WHAT IT DOES
Squish is a virtual hydraulic press. A virtual object (bubble wrap, rubber duck, egg and so on) appears on the lower half of the screen. Closing the phone lowers an on-screen ram that crushes the object. Reopening reveals a "pressed specimen" card that is saved to an on-device collection.

HOW THE HINGE WORKS (iPhone Duo)
1. Open the phone flat on the inner display, ideally lying on a table (tabletop pose).
2. Slowly push the top half down. Squish reads the public hinge angle API (SwiftUI onHingeChange / UIHingeInteraction). From about 168 degrees down to 48 degrees the angle maps continuously to press depth. All visible crushing happens in that range.
3. Close fully. The normal magnetic close triggers the "ka-chunk" sound/haptic and a "Press sealed" card on the cover display.
4. Reopen to see a short replay and the specimen card.
No extra force is needed or encouraged: the user closes the phone exactly as they normally would.

NO DUO? (any iPhone, or the Simulator)
Squish is a universal iPhone app. On any iPhone without a hinge, Pinch Press is on automatically: drag the yellow ram handle down (or pinch vertically) to press. On iPhone Duo the same mode is at Shelf > cog (Settings) > "Press without folding". Every object, unlock and achievement works in this mode.

UNLOCKS (no hidden features, no purchases)
- 6 objects are open at launch.
- Soda Can: press 3 different objects.
- Gummy Bear: press 6 times in total.
- Glass Bottle: earn one "Perfect Squish" (a slow, steady close with no reversing; about 10 seconds of smooth motion, or a slow drag in Pinch Press).
- The 10th object is a secret: it unlocks after pressing all 9 others and is a comic steel ball that cracks the press instead. Reaching it takes roughly 10 presses (about 5 minutes).

SAFETY (Guidelines 1.4.5 and 2.4.2)
- All objects are virtual and on screen only. Store copy and onboarding never suggest placing anything real between the halves.
- On first run the cover display shows: "Squish is on-screen only. Never close your phone on real things." The description repeats this.
- Fast slams are not rewarded: no badge, achievement or bonus. The Perfect Squish trait rewards slow, steady closing, and repeated slams show a gentle "slowly..." hint.
- Performance is capped (adaptive frame rate, reduced effects at thermal "serious"), and the haptic engine runs only while the press screen is visible, to avoid excess heat and battery drain.
- Bright flashes stay under 3 per second.

PRIVACY
Squish collects no data. There are no third-party SDKs, analytics, ads, accounts or tracking, and the app makes no network requests of its own. The collection is stored only on the device. Sharing a clip or image happens only when the user taps Share, via the system share sheet. The privacy label is "Data Not Collected".

GAME CENTER
10 optional achievements (1,000 points in total), all earned through normal play. None rewards speed or slamming. One ("The Secret") is hidden until earned. There are no leaderboards. If the player is not signed in to Game Center, Squish works fully and simply doesn't report achievements.

OTHER NOTES
- A one-time rating prompt (SKStoreReviewController) may appear after about 10 presses, only after a reveal and never mid-press.
- No notifications are requested.
- Sound uses the ambient audio session, so it respects the silent switch. Haptics still work when muted.
- Content: cartoon objects only, with no creatures, faces or brands. The rubber duck survives every press.

Contact: [founder name], [support email], [phone].
```

## Before pasting, check against the final build

- [ ] The unlock rules match the code (bible §4: Soda Can after 3 different objects, Gummy Bear after 6 presses, Glass after a Perfect Squish, the secret after all 9).
- [ ] The display-off angle from Week 0. The build seals at 48° (PressConfig.endAngle). If the Week-0 display-off angle forces a change, update "48 degrees" here.
- [ ] The Settings path and label wording ("Press without folding") match the UI exactly.
- [ ] The first-run cover hint text matches the build exactly.
- [ ] "No network requests of its own" is true. Grep for `URLSession` and any SDKs; Game Center and StoreKit traffic is Apple's.
- [ ] **Don't add a reviewer shortcut or hidden unlock.** Hidden features break Guideline 2.3.1. The secret is reachable in about 5 minutes of normal play.
- [ ] The `-squishDemo` launch argument is compiled out of Release builds (or reachable only by launch argument, never by any UI). If it ships, mention it in the notes.

## Why the notes are worded this way

- **2.4.2 (hardware compatibility)** asks apps to be "used in a way that does not risk damage to the device". The risk a reviewer will imagine is someone closing the phone on something real, or slamming it. So the notes say up front: virtual only, a normal close, no extra force, slams never rewarded, and an in-app safety line. The heat and battery lines cover the rest of 2.4.2.
- **1.4.5 (physical harm)** forbids urging use that "risks physical harm". There are no challenges, dares or slam rewards.
- **Pre-orders count as submissions** (2.1(a)). The pre-order build gets these same notes and must be final-quality.

## If rejected under 2.4.2 or 1.4.5

Reply in Resolution Center, calmly and specifically:
> "Squish never asks users to place anything on the device or to use more than a normal close. All objects are rendered on screen. We show an explicit on-screen safety line on first run ('Squish is on-screen only. Never close your phone on real things.'), repeat it in the description, and deliberately give no reward for fast closing; the only quality trait rewards slow, gentle closes. We're happy to make the safety line more prominent if you'd like, e.g. on the first inner-display screen as well."

Then offer that change in the next build: add the line to the first inner-display frame too.

---

## Sources

- App Review Guidelines: 2.4.2 Hardware Compatibility, 1.4.5 Physical Harm, 2.1(a) App Completeness (pre-orders included; demo accounts), 2.3.1(a) specific notes and no hidden features, 2.3.7 metadata: https://developer.apple.com/app-store/review/guidelines/
- Apple, *App privacy details* (data processed only on device isn't "collected"; data collected by Apple isn't the developer's to disclose): https://developer.apple.com/app-store/app-privacy-details/
- Bible §2 (slam decision), §3.2 (first-run safety line), §6 (angle mapping), §11 (achievements, review prompt)
