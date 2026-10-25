# Squish: App Store metadata (v1.0, final)

*Final, 23 Oct 2026. `asc-metadata.json` is the source of truth: `tools/appstore/asc.swift push` sends it to App Store Connect. This page mirrors it for people, and the description below is generated from the JSON so the two can't drift. Each choice has a one-line reason in `DECISIONS.md`. Counts are Unicode characters, except keywords, which Apple counts in bytes.*

---

## 1. App name (limit 30)

```
Squish: Fold-to-Crush Press
```
**27 / 30.** If the name is taken when the record is created, use the fallback `Hingepress` (`SUBMISSION.md` §1).

## 2. Subtitle (limit 30): decided

```
The priciest hydraulic press
```
**28 / 30**, the same in en-GB and en-US.
- The £/$2,000 version is retired: Guideline 2.3.7 says subtitles "should not include prices", and a rejection costs a review cycle (`DECISIONS.md` #1).
- If App Review still objects, the reserve is `A hydraulic press for the fold` (29).

## 3. Promotional text (limit 170; editable at any time without a new version)

```
On iPhone Duo, close it slowly and feel each object give. On any other iPhone, drag to press. Ten objects, one shelf of pressed specimens. No ads, no in-app purchases.
```
**167 / 170.** It leads with iPhone Duo, because if the Duo screenshot slot is missing, this text and the description are the only Duo signals (`DECISIONS.md` #13–15).

Rotation ideas for later (count each one before pasting):
- Drop week: "Holiday Object Drop is here: a cracker, a bauble and a snowman join the press. Free, like every drop. Close slowly."
- After a press mention: "As seen in [outlet]: …" (only with a real quote).

## 4. Description (limit 4,000)

**3,382 / 4,000.** en-US is identical except "labeled" for "labelled".

```
Your phone is now a hydraulic press.

Pick an object. It sits on the lower half of the screen. Close the phone slowly and watch, hear and feel it strain, crack and give way, following your hand degree by degree. Shut it: ka-chunk. Open it again to find your object flattened, stamped and filed as a pressed specimen.

No ads. No in-app purchases. No timers, streaks or energy bars. You pay once and the press is yours, including every free object drop we ship.

BUILT FOR THE FOLD. WORKS ON EVERY iPhone.
On iPhone Duo, the two halves of the inner screen are the press plates and the hinge is the lever: the further you close, the harder it presses, in real time. Close it all the way and the outer display shows the sealed press. Open up to see what's left. On any other iPhone, the P-48 press sits under your finger: drag the ram down and feel it give. Same objects, same crunch.

TEN OBJECTS, TEN WAYS TO GIVE
• Bubble Wrap: twenty-four bubbles, popped one at a time
• Rubber Duck: a squeak that climbs with the pressure (he'll be fine, probably)
• Jelly: wobbles, spreads and splats
• Crayon: a clean snap, then a waxy smear
• Egg: a hairline crack, then the yolk
• Cake Slice: the frosting escapes and the candle goes down
• Soda Can: buckles ring by ring, then fizzes
• Gummy Bear: squishes flat, then splits at the seam
• Glass Bottle: a long, slow creak, then it doesn't
• And one more. We'd rather not say. It does not squish.

Six objects are open from your first press. The other four unlock just by playing, usually in your first session. Every press is seeded, so cracks, fragments and surprises change each time, and some objects hide something inside. Now and then a press comes out Golden: 1 in 50, the same odds every time, shown in Settings.

THE PERFECT SQUISH
Close slowly and steadily, without easing off, and your card earns a Perfect Squish mark. Slamming still works. It just isn't the point.

A SHELF OF PRESSED SPECIMENS
Every result is stamped onto a specimen card, like a herbarium for flattened things: where it gave, the tonnage, what broke and a serial number. The shelf keeps the best card for each object and your last 200 presses. Share a short replay clip with sound, or a before-and-after picture, through the share sheet.

SOUND AND FEEL
Every crack has a sound and a haptic that land together. Workshop sound for the full crunch, or Soft for a gentler mix. Haptics Off, Soft or Full.

GAME CENTER
Ten achievements, all earned through normal play and none for speed. Game Center is optional.

ACCESSIBILITY
• Press without folding: on iPhone Duo, turn it on in Settings and press with a drag. Every object, unlock and achievement works this way
• VoiceOver: objects, cards and controls are labelled, and you can press step by step by swiping up and down
• Reduce Motion: no camera shake or slow motion, and debris barely moves
• Captions: comic words like POP! and CRACK! for each sound moment, on automatically if you use closed captions
• A Soft sound style for a gentler mix

PRIVATE BY DESIGN
No accounts. No tracking. No data collected. Squish has no servers, and your collection lives on your device.

A NOTE ON SAFETY
Everything in Squish happens on screen. The objects are virtual, and the press only ever asks you to close your phone the normal way. Never close your phone on anything real.

More objects are on the way as free updates.
```

Copy rules this text keeps:
- **Every feature claim is checked against the code.** `DECISIONS.md` §5 lists what the check changed: drag rather than pinch; 24 bubbles; the odds are shown in Settings; the "flashes" claim cut; the Captions wording.
- **"iPhone Duo" is used only referentially.** It never appears in the name, subtitle or keywords. The "iPhone" mark keeps its exact form, even in the capitalised heading.
- **No stress-relief or health claims**, which keeps the app clear of the "Health or Wellness Topics" age-rating item.
- **The secret object is only teased** ("It does not squish"). Don't name the steel ball anywhere public.

## 5. Keywords (limit 100 bytes, comma-separated, no spaces)

```
smash,squash,flatten,squeeze,satisfying,asmr,fidget,toy,foldable,hinge,bubble,wrap,stress,simulator
```
**99 / 100 bytes.**
- No word repeats the name or subtitle. Squish, fold, crush, press, hydraulic and priciest are already indexed.
- No Apple marks and no competitor or brand names.
- Apple combines terms across fields, so "bubble"+"wrap", "stress"+"toy" and "hydraulic"+"press"+"simulator" all form the phrases people search for.

Alternate set to A/B after 4 weeks of Search data (check the bytes): `smash,squash,flatten,squeeze,satisfying,asmr,fidget,calm,toy,foldable,hinge,bubble,pop,haptic,simulator`

## 6. What's New

App Store Connect has no What's New field for an app's first version. The 1.0 text is for the TestFlight "What to Test" field, the press and social:
```
The press is open. Ten objects, one shelf of pressed specimens, zero ads. Close slowly.
```
1.1, Holiday Object Drop (the object list is a placeholder until the drop is final):
```
Holiday Object Drop: three festive objects join the press, free. A cracker that bangs, a bauble that shatters into glitter, and a snowman who was never going to make it to January anyway. Plus small fixes to make the slow close feel even better.
```

## 7. Category

| Field | Choice |
|---|---|
| Primary | **Games**, with the subcategories **Casual** and **Simulation** (`GAMES`, `GAMES_CASUAL`, `GAMES_SIMULATION`) |
| Secondary | **Entertainment** (`ENTERTAINMENT`) |

## 8. Age rating: 9+

The exact API values are in `asc-metadata.json` → `ageRating`. The reasoning is in `DECISIONS.md` §2.

| Item | Answer |
|---|---|
| Cartoon or Fantasy Violence | **Infrequent**. This one item sets the 9+ |
| Every other content item: profanity/crude humour, horror/fear, mature/suggestive, medical, alcohol/tobacco/drugs, sexual content (both), realistic violence (both), guns/weapons, simulated gambling, contests | **None** |
| Health or Wellness Topics, Gambling, Loot Boxes, Unrestricted Web Access, User-Generated Content, Social Media, Messaging and Chat, Advertising, Parental Controls, Age Assurance | **No** |
| Made for Kids | **No** |

## 9. Other App Store Connect fields

| Field | Value |
|---|---|
| Price | Base **United Kingdom £2.99**, auto-equalised for other storefronts. No launch discount |
| Availability | Every territory **except China mainland** (`DECISIONS.md` #7) |
| Pre-order | **No** (`DECISIONS.md` #5) |
| Release | **Scheduled: Tue 24 Nov 2026, 08:00 UTC** |
| Family Sharing | **On** (permanent once on) |
| Small Business Program | Enrol (15%) |
| Copyright | `2026 <founder's legal name>` (founder-only; `copyrightHolder` is `null` until then) |
| Support URL | `https://pravegm.github.io/squish/support/` |
| Marketing URL | `https://pravegm.github.io/squish/` |
| Privacy Policy URL | `https://pravegm.github.io/squish/privacy/` |
| App Privacy | **Data Not Collected** (`privacy-labels.md`) |
| Accessibility Nutrition Labels | **VoiceOver** and **Reduced Motion** only, published on launch day (`accessibility.md`) |
| Content Rights | Yes, third-party content with the necessary rights: CC0-1.0 recorded sounds (`Squish/Resources/Sounds/LICENSES.md`) |
| Export compliance | `ITSAppUsesNonExemptEncryption` = NO (in `project.yml`) |
| Game Center | On; 10 achievements, 700 points (`achievements.md`) |
| Localisation | English (UK) primary, plus English (US). Every other storefront shows en-GB |

## Sources

- App Store Connect Help, *App information*: name 2–30 characters, subtitle 30, categories, and one or two subcategories for Games. https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- App Store Connect Help, *Platform version information*: promotional text 170, description 4,000, keywords 100 bytes, and What's New isn't available for the first version. https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- App Store Connect Help, *Age ratings values and definitions*. https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- App Review Guidelines 2.3.7: https://developer.apple.com/app-store/review/guidelines/
- Apple, *Guidelines for Using Apple Trademarks*: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
