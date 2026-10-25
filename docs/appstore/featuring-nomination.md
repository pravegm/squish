# Squish: Featuring nomination and In-App Events

*Nomination 1 is final as of 23 Oct 2026, ready to paste. The founder submits it, because it needs an App Store Connect login.*

## Timing (important)

Apple asks for nominations "as early as possible, with a minimum lead time of 3 weeks". For a 24 Nov release, nomination 1 must be **submitted by Tue 3 Nov 2026**. Aim to submit as soon as the app record exists (`SUBMISSION.md` §1); there's no reason to wait.
- The nomination doesn't need an approved build or a pre-order. Squish has no pre-order (`DECISIONS.md` #5), and the App Launch type covers a launch.

| Nomination | Type | Submit by | For |
|---|---|---|---|
| 1. Launch | **App Launch** | **Tue 3 Nov 2026** (ideally this week) | 1.0 release, Tue 24 Nov |
| 2. Holiday Object Drop | **New Content** | **Thu 19 Nov 2026** | 1.1 + In-App Event from 10 Dec |
| 3. Backorder-wave drop | **New Content** | **Fri 18 Dec 2026** (the 3-week deadline is 28 Dec, but that falls in the holiday shutdown) | 1.2 + In-App Event from 18 Jan |

Where: App Store Connect → Apps → Squish → **Featuring → Nominations → Create Nomination**. Roles allowed: Account Holder, Admin, App Manager or Marketing.

---

## Nomination 1: App Launch (paste these)

| Field | Value | Count / limit |
|---|---|---|
| Nomination Name | `Squish - App Launch - iPhone Duo hinge press` | 44 / 60 |
| Nomination Type | **App Launch** | — |
| Description | the block below | **965 / 1,000** |
| Publish Date | **Specific day: 2026-11-24** | — |
| Related Apps | Squish only (auto-filled) | up to 10 |
| Platforms | iOS | — |
| Countries or Regions | leave the auto-selection (all territories the app is in; `DECISIONS.md` #7) | — |
| Localizations | leave the auto-selection (English (UK), English (U.S.)) | — |
| In-App Events | none yet. The Holiday event is nominated with nomination 2 | — |
| Supplemental Materials | 1. `https://pravegm.github.io/squish/` 2. `https://pravegm.github.io/squish/press/` 3. the founder's 15 s hands-on teaser post URL (once posted) 4. the TestFlight public link (once external testing is approved) | up to 5 URLs |
| Helpful Details | the block below | **415 / 500** |

### Description (965 characters)
```
Squish turns iPhone Duo into a hydraulic press. The two halves of the inner screen are the press plates: pick a virtual object, close the phone slowly, and watch, hear and feel it strain, crack and give way, following the hinge degree by degree. Shut it for a heavy ka-chunk on the outer display, then reopen to reveal a pressed specimen card for your shelf.

The hinge is the whole interface: the live angle drives deformation, synthesized sound and haptics in the same frame. Ten launch objects each fail their own way, from bubble wrap that pops bubble by bubble to a glass bottle that creaks, then shatters.

Built for everyone: the same press works on every iPhone with a drag, and Press without folding brings it to Duo owners who can't or don't want to fold. Every unlock works either way. VoiceOver can press step by step, and Reduce Motion calms every effect.

One price, no ads, no in-app purchases, no timers, no data collected. Free object drops follow.
```

### Helpful Details (415 characters)
```
Optimized for iPhone Duo: tabletop and book poses, inner and outer displays (the sealed press and an object picker live on the cover). Built with Xcode 27.1 on the public hinge API. A one-person studio: every object is generated in code and every sound is synthesized live from the hinge, layered with CC0 foley, so free drops can come every few weeks (Holiday Object Drop planned for December). Slow, steady closes are quietly rewarded; slams never are.
```

**What changed from the draft, all checked against the code (`DECISIONS.md` §5):**
- "synthesised or CC0" became "synthesized live", then (25 Oct) "synthesized live from the hinge, layered with CC0 foley": recorded CC0 samples now ship.
- "photosensitivity-safe flashes" and "visual sound cues" were cut, because there's no flash-rate limiter to point to.
- Apple's Duo guidance asks you to say in Helpful Details that the app is "optimized for iPhone Duo", so it now leads with that.
- The pre-order line is gone.
- The publish date is the single launch day.

The four angles, and where each lands:
- **New hardware:** the first line, plus "Optimized for iPhone Duo".
- **Design craft:** sound and haptics in the same frame, and per-object failure.
- **Accessibility:** a full paragraph, with only the claims the labels back (`accessibility.md`).
- **No ads:** the final line.

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
