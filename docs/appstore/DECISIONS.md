# Squish 1.0: launch decisions (final)

*Made 23 Oct 2026 by Claude, acting as launch lead with the founder's delegation ("take full ownership… make the decisions"). Each line is the decision plus the one reason that settled it. The machine-readable form is `asc-metadata.json`; the clicks are in `SUBMISSION.md`. Only the founder's legal identity and Apple-login actions are left to the founder (`SUBMISSION.md` §0).*

## 1. The decisions

| # | Topic | Decision | Reason |
|---|---|---|---|
| 1 | **Subtitle** | **`The priciest hydraulic press`** (28/30), in both en-GB and en-US. The £/$2,000 joke is dropped | Guideline 2.3.7 says subtitles "should not include prices", and a currency figure is the one thing a strict reviewer can point to. A rejection near a fixed launch costs a review cycle, and a later subtitle change needs a new version. The fallback keeps the joke without a number (Toastie's "World's Most Expensive Toaster" shipped the same way) |
| 2 | **Keywords** | `smash,squash,flatten,squeeze,satisfying,asmr,fidget,toy,foldable,hinge,bubble,wrap,stress,simulator` (**99/100 bytes**) | No word repeats the name or subtitle (squish, fold, crush, press, hydraulic and priciest are already indexed from them). There are no Apple marks or brands. "simulator" picks up "hydraulic press simulator", and it replaces "relax" (a wellness word) and "pop" (a crowded "bubble pop" field) |
| 3 | **Categories** | Primary **Games**, subcategories **Casual** + **Simulation**. Secondary **Entertainment** | Casual is Toastie's shallow paid chart, Simulation is the genre's own search intent, and Games is where Game Center lives. Entertainment catches the "toy, not a game" browsers |
| 4 | **Release** | **Scheduled** (`SCHEDULED`) for **Tue 24 Nov 2026, 08:00 UTC** (08:00 UK, 00:00 US Pacific). Submit 1.0 for review by **Wed 11 Nov** (hard cut Mon 16 Nov) | One fixed worldwide moment before US Thanksgiving week, with 13 days of review buffer |
| 5 | **Pre-orders** | **No** pre-order for 1.0 | A pre-order needs a final, approved 1.0 build about 3 weeks out. The founder only got the Duo on 23 Oct, and the real-device tuning (display-off vs `endAngle`, haptics, `closed` above 90°) is the biggest quality lever left. A £2.99 impulse toy gains little from a charge-on-release pre-order, and the featuring nomination doesn't need one (Apple's App Launch type covers launches as well as pre-orders) |
| 6 | **Price** | Base territory **United Kingdom, £2.99**. Apple auto-equalises every other storefront from it (expect $2.99 in the US). **No launch discount**. Family Sharing **on** | The founder's price. Letting Apple equalise avoids hand-maintaining 174 prices |
| 7 | **Territories** | **Every territory except China mainland** | Paid games in China mainland need a government ISBN licence that we don't have. The EU stays in, but the founder must declare Digital Services Act trader status (founder-only, `SUBMISSION.md`). If the founder won't publish trader contact details, the fallback is to untick the 27 EU storefronts. That is the only reason to drop them |
| 8 | **Age rating** | **9+**: cartoon or fantasy violence **Infrequent**, every other content item **None**, every capability **No**, not Made for Kids (`asc-metadata.json` → `ageRating`) | See §2 for the judgement |
| 9 | **Profanity or crude humour** | **None** (was Infrequent in the draft) | The flavour text is cheeky ("You monster.", "It wasn't your birthday anyway.") but has no swearing and nothing crude. The honest answer is None, and the rating stays 9+ through item 8 |
| 10 | **App Preview** | Planned, optional, 6.9" only: one 15–30 s **IPHONE_67** preview at 886×1920, poster frame 00:08.0. It ships in 1.0 **only if** it is delivered by **Mon 9 Nov** and passes the same truth check as the frames. Otherwise 1.0 ships without one and it goes into 1.0.1. **No Duo preview in 1.0** | Previews lock with the version at approval, so a late or wrong preview costs a whole version. The API has no Duo preview type (§3), and the 6.9" cut is the one being rendered now |
| 11 | **Frame 1: photo vs render** | Ship the **render** (`01-hero-duck`, FoldStoreShot) in 1.0. Shoot a real-Duo photo of frame 1 for **1.0.1** (target: submitted Fri 27 Nov) | The render is true to the app and approved (FOLD-REVIEW-9: SHIP). A real-hand photo is the only lever above ~8.7 (+~0.3), but it needs the founder's hardware and time, and screenshots can only change with a new version |
| 12 | **Screenshot set** | **Signed off: the 19 frames and captions in §4**, from "App Store screenshots" run **39952047687** (head `16e74e6`, green, 0 missing / 0 flagged) | Every frame got a SHIP verdict in FOLD-REVIEW-9. P5's only fix (no "No purchases.") landed in `16e74e6` (`ci/scenarios.txt:111`), the commit that run built |
| 13 | **Duo screenshot slots** | Upload the **6.9" and 6.1" sets with the tool**, and upload the **Duo inner (7) and outer (2) sets by hand** in the App Store Connect web UI if the iPhone Duo slot is shown. If it isn't, 1.0 ships with the iPhone sets plus the Duo mention in the description and promo text, and the Duo sets go into **1.0.1** | The API has no Duo screenshot type, so the tool can't upload them (§3). Screenshots lock at approval, so "add them later by metadata edit" (the old plan) is not possible. It takes a new version |
| 14 | **Duo mention** | Description opens its second section with how the press works on iPhone Duo, and the promo text leads with "On iPhone Duo, close it slowly…" | Without a Duo slot, that copy is the only Duo signal on the product page. "iPhone Duo" is used referentially, never in the name, subtitle or keywords (Apple trademark rules; 2.3.7) |
| 15 | **Promotional text** | `On iPhone Duo, close it slowly and feel each object give. On any other iPhone, drag to press. Ten objects, one shelf of pressed specimens. No ads, no in-app purchases.` (167/170) | It does the Duo job (#14) and the "works everywhere" job in one line, and it can be changed any time without a version |
| 16 | **Description** | Rewritten from the draft and checked line by line against the code (§5): 3,382/4,000 | Several draft claims weren't true of the build (§5) |
| 17 | **Achievements** | The 10 from `achievements.md`, **700 points**, The Secret hidden, none repeatable. The IDs were verified against `Achievement.gameCenterID` | 300 points stay reserved for the holiday and January drops, under the 1,000 cap. Two descriptions were corrected to match the code (§5) |
| 18 | **App Privacy** | **Data Not Collected** (`privacy-labels.md`) | Grep finds no network, analytics, ads, tracking or third-party SDKs. Game Center data is Apple's to disclose, not ours |
| 19 | **Accessibility Nutrition Labels** | Declare **VoiceOver** and **Reduced Motion** only (`accessibility.md`). Publish on launch day, because Apple only allows publishing once a version is live | Those two are the only labels the code fully earns. Larger Text, Differentiate Without Color and Sufficient Contrast each fail on a specific line, and the fixes are listed for 1.0.1 |
| 20 | **Export compliance** | `ITSAppUsesNonExemptEncryption` = **NO** (already in `project.yml:37`) | The app uses no encryption of its own and has no networking. No French declaration is needed |
| 21 | **Content rights** | "Does your app contain, show or access third-party content?" **No** | All objects and sounds are made in code (no audio files in the repo). The Settings credits line saying otherwise is wrong (§6, item 3) |
| 22 | **Review contact and sign-in** | No demo account. Contact = the founder (founder-only values) | No accounts exist |
| 23 | **Featuring** | Nomination 1 (**App Launch**, publish date 24 Nov) submitted **by Tue 3 Nov**, with "optimised for iPhone Duo" in Helpful Details (Apple's Duo guidance). Text in `featuring-nomination.md` and `SUBMISSION.md` §9 | Apple asks for at least 3 weeks' lead time |
| 24 | **Small Business Program** | Enrol now | Proceeds adjust to 15% fifteen days after the end of the fiscal month in which enrolment is approved, so enrolling in October covers launch day |

## 2. The age-rating judgement (cartoon or fantasy violence)

**Choice: Infrequent. Result: 9+.**

- **Apple's definition.** Apple's item is "depictions of violence involving cartoon characters or fantasy settings". Nine of the ten objects are inanimate (bubble wrap, jelly, crayon, egg, cake, can, gummy bear, bottle, steel ball), and crushing an object isn't violence against anyone. The press loop itself therefore isn't "frequent violence". Answering Frequent would push the app to 13+, which the content doesn't warrant.
- **Why not None.** The **Rubber Duck** reads as a character: it has eyes, a squeak, "He'll be fine. Probably." and "Bath time is cancelled". It is flattened, comically and without gore, and it survives every press. That is mild cartoon violence against a character, and it is one object of ten. That makes "Infrequent" the honest answer. Answering None would rest on a reviewer agreeing the duck is just an object, and an under-rated app is a rejection risk, which an over-cautious 9+ is not.
- **Nothing else applies.** There is no gore, nothing coloured like blood, and no creatures (bible §4). Realistic violence and prolonged/graphic violence are None.
- **API value.** The script sends `INFREQUENT`, matching the questionnaire's current wording. If the API refuses it for this field, send `INFREQUENT_OR_MILD`, which is the same answer in the older enum. The API accepts both values.
- **Health or wellness topics:** `false`. The copy makes no stress-relief claims. The keyword "stress" is a search term ("stress toy"), not a content claim.
- **Loot boxes:** `false`. Golden (1 in 50) and the surprises are free random outcomes of normal play. Nothing is bought, and the odds are shown in Settings.

## 3. Research: iPhone Duo on the App Store (checked 23 Oct 2026)

**Confirmed from Apple's documentation:**
- **Screenshots.** The screenshot spec has an **iPhone Duo** row:
  - **inner display 2007×2853** portrait (2853×2007 landscape);
  - **outer display 1398×2034** portrait (2034×1398 landscape).
  - From **April 2027**, Duo screenshots "will be required for any app using the iOS 27.1 SDK or later". Until then they're optional. Submitting them adds a Duo **badge** to the product page.
  - Sources: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications and https://developer.apple.com/iphone-duo/prepare/.
- **App Previews.** The preview spec lists iPhone Duo, with an accepted upload size of **886×1920 portrait / 1920×886 landscape**, the same as the 6.9" class. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications.
- **The API has no Duo type.** App Store Connect's `ScreenshotDisplayType` (33 values) and `PreviewType` (16 values) have **no iPhone Duo value**. The iPhone values are APP_IPHONE_67/65/61/58/55/47/40/35 and IPHONE_67/…/35. **Consequence: `tools/appstore/asc.swift` can't upload Duo assets.** They are a manual web-UI step, if the slot exists. Sources: developer.apple.com/tutorials/data/documentation/appstoreconnectapi/screenshotdisplaytype.json and …/previewtype.json.
- **Size-to-type mapping.** **1320×2868 → APP_IPHONE_67** (the "6.9-inch" / Dynamic Island large class) and **1206×2622 → APP_IPHONE_61** (Dynamic Island medium). That mapping is used in `asc-metadata.json`.
  - The spec page says the iPhone minimum is "at least one screenshot for iPhone with Dynamic Island (medium display)". We ship both sets, so either reading is covered.
  - Sources: the spec page above; fastlane's size table (https://github.com/fastlane/fastlane, `deliver/lib/deliver/app_screenshot.rb`).
- **Apple's "Prepare for iPhone Duo" page:**
  - "Use the new preview tool in App Store Connect" to check how assets look on iPhone Duo.
  - For featuring, say in Helpful Details that the app is "optimized for iPhone Duo".
- **HIG, Designing for iPhone Duo** (https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo):
  - Games should "fill the screen as the device pose changes" and "prefer changing the aspect ratio over letterboxing or pillarboxing".
  - The centre band is a reserved folding region.
  - Relevant to us: the open book-pose letterbox check (FOLD-REVIEW-9 N6) is a HIG item, not just polish.
- **Review guidance: none Duo-specific.** The App Review Guidelines have no Duo, foldable or hinge wording. The guidelines that apply are the general ones (2.4.2 hardware use, 1.4.5 physical harm, 2.3 accurate metadata). `review-notes.md` is written to those.

**Third-party / forum (not Apple policy):**
- **Forum thread 845505** (https://developer.apple.com/forums/thread/845505). Developers report no Duo option in the web UI device selector. Apple DTS answered that uploading iPhone Duo assets "will be available later this year".
- **Forum thread 847849** (https://developer.apple.com/forums/thread/847849). A community user reported the Duo screenshot option appearing about two weeks later. This is unconfirmed by Apple.
- **9to5Mac, 5 Oct 2026** (https://9to5mac.com/?p=1072806). It ties the badge to building with Xcode 27.1. Apple's own spec page ties it to submitting Duo screenshots, and we follow Apple.

**Decision (see #13):**
- Upload day: check the web UI for the Duo slot, and use the new preview tool.
- If the slot is there: upload `duoInner` 01–07 and `duoOuter` O1–O2 by hand, then submit.
- If it isn't: submit with the iPhone sets (the description and promo text carry the Duo story), and put the Duo sets in 1.0.1.

## 4. Screenshot sign-off: the 19 frames

Source: the latest green "App Store screenshots" run, **39952047687** (23 Oct, head `16e74e6`; artifacts `store-duo`, `store-69`, `store-61`, not expired). Paths are relative to a folder where `gh run download 39952047687 -R pravegm/squish -D <dir>` puts each artifact in its own sub-folder.
- **Upload the captioned files.** In the iPhone sets these are under `store/`. The raw `P*.png` at the artifact root are uncaptioned capture sources: never upload them.
- **Order** is as listed. The first three of each set must sell alone, and they do.

| Set | # | File | Caption (headline / sub-line) | Verdict |
|---|---|---|---|---|
| Duo inner 2007×2853 | 01 | `store-duo/duo-screens/store/duo-inner/01-hero-duck.png` | Close your phone. Feel it *give*. / Squish turns the fold into a hydraulic press. | SHIP |
| | 02 | `…/duo-inner/02-pair-can.png` | The hinge is the *lever*. | SHIP |
| | 03 | `…/duo-inner/03-reveal-duck.png` | Open up. File the *evidence*. / Every press becomes a specimen. | SHIP |
| | 04 | `…/duo-inner/04-hero-glass.png` | It creaks. Then it *doesn't*. | SHIP |
| | 05 | `…/duo-inner/05-variety.png` | *Ten* objects. Ten ways to give. | SHIP |
| | 06 | `…/duo-inner/06-shelf.png` | A shelf of pressed *specimens*. / No ads. No in-app purchases. | SHIP |
| | 07 | `…/duo-inner/07-settings.png` | Press without folding. Hear it *softer*. / Accessibility built in. | SHIP |
| Duo outer 1398×2034 | O1 | `store-duo/duo-screens/store/duo-outer/O1-sealed.png` | Ka-chunk. Now *open* it. | SHIP |
| | O2 | `…/duo-outer/O2-cover-launch.png` | Pick on the cover. Press *inside*. | SHIP |
| 6.9" 1320×2868 (`APP_IPHONE_67`) | P1 | `store-69/store/P1-duck-mid.png` | Drag it down. Feel it *give*. / A hydraulic press for every iPhone. | SHIP |
| | P2 | `store-69/store/P2-reveal-duck.png` | Open up. File the *evidence*. | SHIP |
| | P3 | `store-69/store/P3-can-buckle.png` | Cans buckle *ring* by ring. | SHIP |
| | P4 | `store-69/store/P4-shelf.png` | Collect every pressed *specimen*. | SHIP |
| | P5 | `store-69/store/P5-settings.png` | No ads. No upsells. *Just* the press. / Sound styles, haptic levels, Reduce Motion. | SHIP |
| 6.1" 1206×2622 (`APP_IPHONE_61`) | P1–P5 | `store-61/store/P1-duck-mid.png` … `P5-settings.png` | as 6.9" | SHIP |

**Truth check of the captions against the code:**
- **P5, "No upsells":** there are no in-app purchases (no StoreKit purchase code; only the review prompt, `RootView.swift:1,428`).
- **07, "Hear it softer":** the Soft sound style exists (`Contracts.swift:29-38`).
- **P1, "Every iPhone":** the drag press runs whenever there is no hinge (`SettingsView.swift:87-94`).
- No caption shows a price, a folded non-Duo phone, or anything the app doesn't render.

**Never upload:**
- `verify/` frames;
- `V4-glass-crack`;
- `*-eye` composites;
- `*-112` singles;
- raw `*-tabletop-*` frames;
- any `9A–9D` / `90–99` frame.

**Caveat, stated plainly:** I signed off from the critic's frame-by-frame review (FOLD-REVIEW-9 §3) and from the run's green status at `16e74e6`. I did not download the 555 MB of artifacts. The release engineer's push run should look at **P5 at both sizes** once, because the new caption hasn't been looked at by a person yet. If it wraps badly, re-run `store.yml` before uploading.

## 5. What the code check changed in the copy

| Draft claim | Code says | Now |
|---|---|---|
| "Pinch Press… drag the ram down (or pinch vertically)" | The touch press is a `DragGesture` only (`RootView.swift:234-248`). The UI calls it "Press by dragging" and the machine is the P-48 | "the P-48 press… drag the ram down" |
| Bubble wrap "≈ 48 bubbles each" (achievements.md) | 24 bubbles (`ObjectCatalog.swift:80`) | "twenty-four bubbles". Pop Star takes ~21 presses |
| What's Inside?: "Find a surprise" | Needs **two different** surprises (`CollectionStore.swift:255`) | "Find two different surprises hidden inside objects." |
| "Golden… odds listed in Credits" | Shown in Settings → About, "Golden variants · 1 IN 50" (`SettingsView.swift:111-112`) | "shown in Settings" |
| "Flashes stay below three per second" | There is no flash-rate limiter in the code (`PressScene.swift:751-755` only decays the light) | Cut. Not claimed anywhere |
| "Gummy Bear… glows where it's thin" | Not verifiable in code | Cut |
| "Optional visual sound cues" | The Captions toggle shows comic words, and defaults on with system closed captions (`SettingsView.swift:84-85`, `PressDirector.swift:69`) | "Captions: comic words like POP! and CRACK!…" |
| "Reduce Motion: fragments fade instead of flying" | Debris motion ×0.25, no camera kick, no slow motion, no drop (`Particles.swift:363`, `PressScene.swift:266,322-327,638`) | "no camera shake or slow motion, and debris barely moves" |
| Review notes: "1,000 points" | 25+75+75+50+50+100+75+100+100+50 = **700** | 700 |
| Review notes: Perfect Squish "about 10 seconds" | `duration >= 2`, peak ≤ 100°/s, no easing off or slam (`PressEngine.swift:532`) | "2 seconds or more" |
| Review notes: press "from about 168 degrees" | Arms anywhere from 168° to 130° (`PressConfig.swift:8-10`) | "between 168 and 130 degrees" |
| Nomination: "Every sound is synthesised or CC0" | No audio files in the repo; all sound is synthesised (CLAUDE.md, code map) | "Every sound is synthesised in code" |

## 6. Problems found that other owners must fix (not mine to edit)

| # | Severity | Owner | Problem | Fix |
|---|---|---|---|---|
| 1 | **Blocker** (likely crash on a reviewer's first Share → Save) | `project.yml` / Squish | The share sheet (`Squish/UI/SpecimenSharing.swift:172-173`, a plain `UIActivityViewController`) offers **Save Image / Save Video**, but `project.yml` has **no `NSPhotoLibraryAddUsageDescription`**. iOS terminates an app that writes to Photos without that purpose string | Add `NSPhotoLibraryAddUsageDescription: "Squish saves your specimen pictures and clips to Photos when you choose Save."` under `info.properties`, then check Save on device. Saving to Photos is on-device, so the privacy label is unchanged |
| 2 | **Blocker for upload** | `project.yml` | `MARKETING_VERSION: "0.1.0"` | Set to `1.0` (and `CURRENT_PROJECT_VERSION` per upload) before archiving |
| 3 | High (false statement in the app) | `Squish/UI/SettingsView.swift:118` | The credits say "Sounds from Sonniss GDC bundles and Freesound (CC0)", but the app ships no audio files | Change to "Every sound is synthesised in code." This also keeps Content Rights = No true |
| 4 | Medium | HIG / FOLD-REVIEW-9 N6 | Book-pose Settings/Shelf letterbox risk (`Supported: landscapeLeft`) | Real-Duo check. The HIG says prefer reflow over letterboxing |

## Sources

- Research report, 23 Oct 2026. The URLs are inline in §3, plus:
  - https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
  - https://developer.apple.com/tutorials/data/documentation/appstoreconnectapi/ageratingdeclaration/attributes-data.dictionary.json
  - https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order
  - https://developer.apple.com/app-store/small-business-program/
  - https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring
- App Review Guidelines 2.3.7: https://developer.apple.com/app-store/review/guidelines/

## §6 follow-up: fixed before the release build (23 Oct 2026)

- **Photos permission:** `NSPhotoLibraryAddUsageDescription` is now in `project.yml` ("Squish saves your specimen card and press clip to Photos only when you tap Save."). Share → Save Image or Save Video can no longer crash the app.
- **Version:** `MARKETING_VERSION` is 1.0.
- **Settings credits:** they now say every sound is synthesised in code, with no recordings.
- **Selected chips:** they carry a graphite outline and the `.isSelected` trait, so Differentiate Without Color and Sufficient Contrast are now Supported (`accessibility.md`).
- **Privacy manifest:** added as `Squish/PrivacyInfo.xcprivacy`. CI fails if it is missing from the built app.
