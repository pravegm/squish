# Squish: App Store metadata (v1.0)

*Prepared 22 Oct 2026 from the Design Bible (§0, §4, §11, §12, §15) and research 04/06. Character counts were measured by script (Unicode characters; keyword count is in bytes, because Apple limits that field in bytes). Paste each field exactly as it appears inside its code block.*

---

## 1. App name (limit 30)

```
Squish: Fold-to-Crush Press
```
**27 / 30**

---

## 2. Subtitle (limit 30)

| Storefront | Subtitle | Count |
|---|---|---|
| UK (en-GB) and other £ storefronts | `The £2,000 hydraulic press` | **26 / 30** (27 bytes; the limit counts characters) |
| US (en-US), CA, AU | `The $2,000 hydraulic press` | **26 / 30** |
| **Fallback if App Review objects** | `The priciest hydraulic press` | **28 / 30** |

> **Risk to decide on (founder).** Guideline 2.3.7 says names, subtitles, screenshots and previews "should not include prices". "£2,000" is the phone's price, not ours, and the joke is the hook (Toastie's subtitle, "World's Most Expensive Toaster", makes the same joke without a number). A strict reviewer could still read it as pricing information. **Recommendation:** submit the £/$ version. If it's flagged, swap to the fallback in the same review cycle; a subtitle edit doesn't need a new build. Euro storefronts: `La presse hydraulique à 2 000 €` and similar only if we localise. For v1.0, use the en-GB/en-US text for everyone else.

---

## 3. Promotional text (limit 170; editable at any time without a new build)

```
Close your phone slowly and feel it give. Ten objects, ten ways to break, one shelf of pressed specimens. No ads, no in-app purchases, no timers. Just ka-chunk.
```
**160 / 170**

Rotation ideas for later (check the count before you paste each one):
- Drop week: "Holiday Object Drop is here: a cracker, a bauble and a snowman join the press. Free, like every drop. Close slowly."
- After a press mention: "As seen in [outlet]: …" (only with a real quote).

---

## 4. Description (limit 4,000)

**3,106 / 4,000**

```
Your phone is now a hydraulic press.

Pick an object. It sits on the lower half of the screen. Push the top half down slowly and watch, hear and feel it strain, crack and give way, following your hand degree by degree. Snap it shut: ka-chunk. Open it again to find your object flattened, stamped and filed as a pressed specimen.

No ads. No in-app purchases. No timers, streaks or energy bars. You pay once and the press is yours, including every free object drop we ship.

MADE FOR THE FOLD. WORKS ON EVERY IPHONE.
On iPhone Duo, the hinge is the lever: the further you close, the harder it presses, in real time, with nothing canned. On every other iPhone, Pinch Press puts the same press under your fingers: drag the ram down and feel it give. Same engine, same objects, same crunch.

TEN OBJECTS, TEN WAYS TO GIVE
• Bubble Wrap: a ripple of pops, one bubble at a time
• Rubber Duck: a squeak that climbs with the pressure (the duck is fine, honestly)
• Jelly: wobbles, spreads and splorts out of the sides
• Crayon: a clean snap, then a waxy smear
• Egg: hairline cracks, then the yolk
• Cake Slice: oozing frosting, a bent candle, sprinkles everywhere
• Soda Can: buckles ring by ring, then fizzes
• Gummy Bear: splits at the seam and glows where it's thin
• Glass Bottle: a long, slow creak, then the biggest moment in the app
• And one more. We'd rather not say. It does not squish.

Six objects are open from your first press. The rest unlock simply by playing, usually in your first session. Every press is seeded, so cracks, fragments and surprises change each time. Some objects hide something inside. Now and then, a press comes out Golden (1 in 50; the odds are listed in Credits).

THE PERFECT SQUISH
Close slowly and steadily, without hesitating, and your card earns a quiet Perfect Squish mark. Slamming still works. It just isn't the point.

A SHELF OF PRESSED SPECIMENS
Every result is stamped onto a specimen card, like a herbarium for flattened things: crush angle, tonnage, fragment count, serial number. Your shelf keeps the best card for each object and your last 200 presses. Share a short replay clip or a before-and-after image with the system share sheet.

SOUND AND FEEL, IN THE SAME FRAME
Every crack has a sound and a haptic that land together. Workshop sound for the full crunch, or Soft for a gentler, filtered mix. Haptics Off, Soft or Full. No music in the press: just the object, the ram and you.

ACCESSIBILITY
• Press without folding: every object, unlock and achievement works with a simple drag
• VoiceOver labels for objects and outcomes
• Reduce Motion support: fragments fade instead of flying
• Optional visual sound cues for major events
• Flashes stay below three per second

PRIVATE BY DESIGN
No accounts. No tracking. No data collected. Your collection lives on your device. Game Center achievements are optional.

A NOTE ON SAFETY
Everything in Squish happens on screen. The objects are virtual, and the press only ever asks you to close your phone the normal way. Please never close your phone on anything real.

More objects are on the way as free updates.
```

Copy notes:
- "IPHONE" appears in capitals only in the section heading. If you'd rather keep Apple's mark in its exact form, change that heading to `MADE FOR THE FOLD. WORKS ON EVERY iPhone.` (the count doesn't change).
- "iPhone Duo" is used referentially ("On iPhone Duo …"). That is allowed under Apple's third-party trademark guidelines because it isn't part of our product name and implies no endorsement.
- The secret is only teased ("It does not squish"). Don't name the steel ball anywhere public.
- Claims are deliberately calm ("satisfying" is implied, not promised). There are **no stress-relief or health claims**, which keeps us out of the "Health or Wellness Topics" age-rating item and away from "anger therapy" framing.
- Check every accessibility claim against the build before submitting. If something slips (for example visual sound cues), cut that line.

---

## 5. Keywords (limit 100 bytes, comma-separated, no spaces)

```
smash,squash,flatten,squeeze,satisfying,asmr,fidget,relax,toy,foldable,hinge,bubble,wrap,pop,stress
```
**99 / 100 bytes**

Rules applied:
- **Nothing from the name or subtitle is repeated.** Squish, fold, crush, press and hydraulic are already indexed from those fields. "Foldable" is a different word from "fold" and catches searches like "foldable games".
- **No Apple marks.** No "iphone" and no "duo". Research 06 recommends keeping "iPhone Duo" in the description and promo text only, and Guideline 2.3.7 bars packing metadata with trademarked terms.
- **No competitor or brand names** (no Hydraulic Press Channel, no Squishmallow, no Toastie).
- Apple combines keywords across fields, so "bubble" + "wrap" covers "bubble wrap", and "stress" + "toy" covers "stress toy".

Alternate set to A/B after 4 weeks of Search data (99 bytes): `smash,squash,flatten,squeeze,satisfying,asmr,fidget,relax,calm,toy,foldable,hinge,bubble,pop,haptic`

---

## 6. What's New in this version

> App Store Connect does **not** show the What's New field for an app's first version. It's required from the second version onward. The 1.0 text below is for TestFlight "What to Test", the press kit and social. The 1.1 text is ready for the December drop.

**1.0 (TestFlight / press use): 87 characters (limit 4,000)**
```
The press is open. Ten objects, one shelf of pressed specimens, zero ads. Close slowly.
```

**1.1, Holiday Object Drop: 245 characters (limit 4,000)** *(the object list is a placeholder until the drop is final; bible §4 backlog)*
```
Holiday Object Drop: three festive objects join the press, free. A cracker that bangs, a bauble that shatters into glitter, and a snowman who was never going to make it to January anyway. Plus small fixes to make the slow close feel even better.
```

---

## 7. Category

| Field | Choice | Why |
|---|---|---|
| **Primary** | **Games**, subcategories **Casual** + **Simulation** | Toastie charts at #10 Top Paid Casual (US) with very few ratings, so the chart is shallow enough to climb. The Games category also suits Game Center |
| **Secondary** | **Entertainment** | Matches the "toy, not a game" framing for people browsing outside Games |

Alternative: put Entertainment first if the founder wants to avoid "game" expectations. The cost is the shallow Casual chart, which is the best visibility lever we have.

---

## 8. Age rating questionnaire: target 9+

Apple's tiers are 4+, 9+, 13+, 16+ and 18+. On Apple's published mapping, **infrequent cartoon or fantasy violence** and **infrequent profanity or crude humour** each land at 9+. Answer as follows:

| Section | Item | Answer | Note |
|---|---|---|---|
| In-app controls | Parental Controls | No | |
| | Age Assurance | No | |
| Capabilities | Unrestricted Web Access | No | No web views. Support and privacy links open in Safari |
| | User-Generated Content | No | Clips leave the app only through the system share sheet. There's no in-app feed |
| | Social Media | No | |
| | Messaging and Chat | No | |
| | Advertising | No | |
| Mature themes | Profanity or Crude Humor | **Infrequent** | Cheeky flavour text, e.g. Cake: "It wasn't your birthday anyway." No swearing |
| | Horror/Fear Themes | None | |
| | Alcohol, Tobacco or Drug Use or References | None | The glass bottle is unlabelled (fictional labels, no alcohol cues). **Dev: check the label art** |
| Medical or wellness | Medical or Treatment Information | None | |
| | Health or Wellness Topics | None | No stress-relief claims in the copy (§4) |
| Sexuality or nudity | All three items | None | |
| Violence | Cartoon or Fantasy Violence | **Infrequent** | Stylised destruction of inanimate cartoon objects. "None" is arguable, but answering Infrequent is the honest and safe choice and matches the 9+ target |
| | Realistic Violence | None | No creatures, no faces on destroyed objects, no gore-coloured ooze (bible §4) |
| | Prolonged Graphic or Sadistic Realistic Violence | None | |
| | Guns or Other Weapons | None | |
| Chance-based | Gambling | No | |
| | Simulated Gambling | None | |
| | Contests | None | |
| | Loot Boxes | No | Golden variants (1 in 50) are free, random cosmetic outcomes. Nothing is bought, and the odds are disclosed in Credits |
| Kids | Made for Kids | **No** | Once approved it can't be undone, and it would put the Kids category rules on every update |

**Expected result: 9+.** If both content items are answered "None", the result is 4+. That's fine too, but 9+ better matches the copy's tone.

---

## 9. Other App Store Connect fields

| Field | Value |
|---|---|
| Price | Tier for £2.99 / $2.99. **No launch discount** (bible §12) |
| Family Sharing | **On** (permanent once enabled) |
| Small Business Program | Enrol (15% commission) |
| Pre-order | Yes, publish around 7 Nov with release on [20–24 Nov] |
| Copyright | `2026 [Studio legal name]` |
| Support URL | `https://[domain]/support` (see `support.md`; must show real contact information) |
| Marketing URL | `https://[domain]` |
| Privacy Policy URL | `https://[domain]/privacy` (see `privacy-policy.md`; required for every app) |
| App Privacy | **Data Not Collected** |
| Game Center | Enabled; 10 achievements (see `achievements.md`) |
| Accessibility Nutrition Labels | Declare only what passes Apple's evaluation criteria on the final build: likely **Reduced Motion**, **VoiceOver** (press, shelf, card and settings), **Sufficient Contrast** and **Larger Text** (if the shelf and settings support Dynamic Type). Don't declare an item we haven't tested |
| Localisation (v1.0) | English (UK) primary, English (US) with the $ subtitle. Other languages are post-launch |

---

## Sources

- App Store Connect Help, *App information* (name 2–30 characters; subtitle 30 characters; categories and subcategories; age rating): https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- App Store Connect Help, *Platform version information* (promotional text 170 characters; description 4,000; keywords 100 bytes; What's New 4,000 and "isn't available for the first version"): https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- App Store Connect Help, *Age ratings values and definitions* (4+/9+/13+/16+/18+ mapping; infrequent cartoon violence and infrequent crude humour map to 9+): https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- App Review Guidelines 2.3.7 (no prices or trademark packing in metadata), 2.3.10, 1.4.5, 2.4.2: https://developer.apple.com/app-store/review/guidelines/
- Apple, *Guidelines for Using Apple Trademarks* (referential "for/runs on" use; no Apple marks in product names; no abbreviations): https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- Apple, *App privacy details* (on-device processing isn't "collection"; privacy policy URL required): https://developer.apple.com/app-store/app-privacy-details/
- Market context (Toastie listing, keyword advice, Hydraulic Press Channel avoidance): `research/06-market.md`
