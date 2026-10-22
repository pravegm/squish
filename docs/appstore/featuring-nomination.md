# Squish: Featuring nomination and In-App Events

## Timing (important)

Apple asks for nominations **at least 3 weeks before launch**. For a 24 Nov release that means **submitted by Tue 3 Nov**, not 7 Nov as in the build plan. Save the nomination as a draft now and submit it as soon as the pre-order page exists. The nomination doesn't need an approved build, but it's stronger with the pre-order link.

| Nomination | Type | Submit by | For |
|---|---|---|---|
| 1. Launch | **App Launch** | **3 Nov 2026** (ideally 30 Oct) | 1.0 release, 20–24 Nov |
| 2. Holiday Object Drop | **New Content** | **19 Nov 2026** | 1.1 + In-App Event from 10 Dec |
| 3. Backorder-wave drop | **New Content** | **Fri 18 Dec 2026** (the 3-week deadline is 28 Dec, but that falls in the holiday shutdown) | 1.2 + In-App Event from 18 Jan |

Where: App Store Connect → Apps → Squish → **Featuring → Nominations** (roles: Account Holder, Admin, App Manager or Marketing).

---

## Nomination 1: App Launch (form fields)

| Field | Value | Count / limit |
|---|---|---|
| Nomination Name | `Squish - App Launch - iPhone Duo hinge press` | 44 / 60 |
| Nomination Type | App Launch | — |
| Related Apps | Squish's Apple ID: [id] | primary + up to 9 more |
| Publish Date (Start) | 2026-11-20 | `YYYY-MM-DD` |
| Publish Date (End) | 2026-11-24 | |
| Relevant Countries or Regions | `GBR, USA, CAN, AUS, IRL, NZL` (add the EU majors if they're live at launch) | ISO 3-letter |
| Launch in certain markets first? | No | |
| Submit a new In-App Event? | Yes (Holiday Object Drop, 10 Dec) | |
| Platforms | `iOS (iPhone)` | |
| Related In-App Events | [event ID once created] | ≤ 25 |
| Localization | `en-GB, en-US` | |
| Supplemental Materials | 1. press page `https://[domain]/press` 2. 30 s trailer link 3. 15 s hands-on teaser link 4. TestFlight public link (optional) | ≤ 5 URLs |
| Pre-order? | Yes | |
| **Nomination Description** | see below | **993 / 1,000** |
| **Helpful Details** | see below | **401 / 500** |

### Nomination Description (993 characters)
```
Squish turns iPhone Duo into a hydraulic press. Pick a virtual object, push the top half down slowly, and watch, hear and feel it strain, crack and give way, following the hinge degree by degree. Snap it shut for a heavy ka-chunk on the cover display, then reopen to reveal a pressed specimen card for your collection.

The hinge is the whole interface: continuous angle drives deformation, sound and haptics in the same frame, with no canned animations. Ten launch objects each fail in their own way, from bubble wrap that pops bubble by bubble to a glass bottle that creaks and shatters.

Built for everyone: Pinch Press brings the same engine to every iPhone and doubles as a motor-accessibility mode that reaches every unlock. VoiceOver labels, Reduce Motion, Soft sound mode, visual sound cues and photosensitivity-safe flashes are in 1.0.

Premium and respectful: one price, no ads, no in-app purchases, no timers or streaks, no data collected. Free object drops follow as In-App Events.
```

### Helpful Details (401 characters)
```
Made by a tiny studio for the new hinge. Every sound is synthesised or CC0 and every object is generated in code, so drops come every 3-4 weeks. A calm, ad-free answer to the crush-game genre: slow, steady closes are quietly rewarded and slams never are. Safety is designed in: objects are clearly virtual, and the app never asks for more than a normal close. Holiday Object Drop planned for December.
```

The four angles the brief asked for, and where each one lands:
- **New hardware:** first line of the description; the hinge as the whole interface.
- **Design craft:** sound and haptics in the same frame; per-object failure modes.
- **Accessibility:** a full paragraph, including the fact that the motor-accessibility mode reaches every unlock.
- **No ads:** the final paragraph, plus the "calm, ad-free" line in Helpful Details.

Before submitting, check that every accessibility claim is true in the build. If visual sound cues or VoiceOver slip, cut them. Apple editorial will check.

**Nominations 2 and 3** reuse this structure with type **New Content**. Description: what's new (3 objects with their behaviours), the In-App Event dates, and one line restating no ads / no IAP / free update.

---

## In-App Event 1: Holiday Object Drop

| Field | Value | Count / limit |
|---|---|---|
| Reference name | `2026-12 Holiday Object Drop (v1.1)` | 34 / 64 |
| **Event name** | `The Holiday Object Drop` | **23 / 30** |
| **Short description** | `Three festive objects join the press, free.` | **43 / 50** |
| **Long description** | `A cracker, a bauble and a snowman arrive on the anvil, each breaking its own way. Free for every Squish owner.` | **110 / 120** |
| Badge | **Major Update** | |
| Event purpose | Appropriate for all users (new + lapsed + active) | |
| Priority | High | |
| Start / end | **Thu 10 Dec 2026, 09:00 local → Sun 3 Jan 2027, 23:59** (25 days; max 31) | |
| Promotion start | **Thu 26 Nov 2026** (the maximum, 14 days before start) | |
| Countries | Same as launch | |
| Deep link | `squish://event/holiday-2026`, which opens with the Christmas Cracker on the anvil (**dev to implement**) | |
| Event card media | 16:9, min 1920 × 1080: the bauble mid-shatter into glitter, no text. Keep the subject in the centre safe zone | |
| Details page media | 9:16 portrait [verify size in App Store Connect]: a short loop of cracker → bauble → snowman reveal cards | |
| Required build | **v1.1 must be approved and live before 10 Dec**. Submit by **Tue 1 Dec** to leave buffer | |

Object content is from the bible §4 seasonal backlog. Snowman tone check (bible §4: no faces on destroyed things): keep it faceless, with no eyes or mouth. Give it a scarf and coal buttons so it reads as a snow sculpture, not a character. Flavour text: "He was never going to make it to January."

## In-App Event 2: January backorder-wave drop

| Field | Value | Count / limit |
|---|---|---|
| Reference name | `2027-01 Backorder Wave Drop (v1.2)` | 34 / 64 |
| **Event name** | `New Year, New Things to Press` | **29 / 30** |
| **Short description** | `Three new objects for your new phone. Free.` | **43 / 50** |
| **Long description** | `Three new objects land on the anvil, free for every owner. New to the fold? Close slowly and feel each one give.` | **112 / 120** |
| Badge | **Major Update** | |
| Event purpose | Attract new users | |
| Start / end | **Mon 18 Jan 2027 → Wed 17 Feb 2027** (31 days, the maximum), timed to the late-January US Duo deliveries | |
| Promotion start | Mon 4 Jan 2027 | |
| Objects (proposal) | One per behaviour family from the backlog: **Ice Cube** (brittle), **Water Balloon** (contents), **Marshmallow** (gooey, slow memory-foam rise on reopen) | |
| Required build | v1.2 live by 15 Jan. Submit by **Fri 8 Jan** | |
| Sale | Bible §12 sets the £1.99 first sale for this drop. **Keep the price out of the event metadata.** Announce it on social and in the promotional text only | |

---

## Sources

- App Store Connect Help, *Nominations template* (Nomination Name ≤ 60; Description ≤ 1,000; Helpful Details ≤ 500; types App Launch / App Enhancements / New Content; publish date; ≤ 5 supplemental URLs; submit ≥ 3 weeks before launch): https://developer.apple.com/help/app-store-connect/reference/nominations/nominations-template
- App Store Connect Help, *Nominate your app for featuring* (roles, drafts): https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring
- App Store Connect Help, *Offer In-App Events* (event name ≤ 30; short description ≤ 50; long description ≤ 120; reference name ≤ 64; up to 10 published and 15 approved at a time; badge): https://developer.apple.com/help/app-store-connect/offer-in-app-events/offer-in-app-events
- Apple Developer, *In-App Events* (events run up to 31 days and can be promoted up to 14 days before start): https://developer.apple.com/app-store/in-app-events/
- Event card media 1920 × 1080 minimum (third-party summary; verify in App Store Connect): https://www.applaunchflow.com/blog/app-store-in-app-events-guide-2026
- Bible §4 (backlog), §11 (drop cadence), §12 (January sale); research 06 §7 (January backorders, holiday shutdown)
