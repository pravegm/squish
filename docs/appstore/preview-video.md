# Squish: App Preview and social teaser scripts

## Rules this script obeys

| Rule | Source | How we comply |
|---|---|---|
| 15–30 s, ≤ 30 fps, H.264 (10–12 Mbps) or ProRes 422 HQ, stereo AAC 256 kbps at 44.1/48 kHz, ≤ 500 MB, up to 3 previews per device size and language | Apple, App preview specifications | A **30 s** cut, H.264 `.mp4` at 30 fps, −16 LUFS / −1 dBTP (bible §8) |
| **Accepted resolution for iPhone Duo, 6.9" and 6.5": 886 × 1920 portrait (or 1920 × 886 landscape)** | Apple, App preview specifications | Portrait 886 × 1920. The Duo inner display (2007 × 2853, aspect 0.70) doesn't fill a 0.46 frame, so we **scale the inner screen to 886 px wide (≈ 1,260 px tall), centre it, and use the off-white bands above and below for captions**. Never crop into the UI |
| Show only the app; **"Don't film people interacting with a device"**; capture on device | Apple, App Previews guidelines | **No hands in the App Preview.** The fold is shown by the app's own ram descending plus an overlaid fold glyph (allowed in the same way as Apple's "touch hotspots"). Real hands go in the social teaser only |
| Previews autoplay **muted**; copy must be legible and stay on screen long enough | Apple | Every beat has a caption, ≤ 6 words, each on screen ≥ 1.5 s |
| No prices and no seasonal or timely references | Apple | No "£2,000", "holiday" or dates in the preview |
| Appropriate for all ages: no violence or profanity | Apple | Objects only. Glass stays chunky. No flavour-text jokes in the preview |
| Poster frame defaults to 5 s; you can choose a different one | Apple | **Set the poster frame to 00:08.0** (Rubber Duck mid-squash, matching screenshot 1) |
| First 3 seconds must show a fold and a burst | Squish brief, research 04 §6 (average watch time is about 4–6 s) | Cold open on a press already moving; first pop at 0.3 s; full burst by 2.4 s. **No logo intro** |

**Capture plan (dev + founder):**
1. The founder performs real presses on the Duo while the app records its **hinge timeline + seed** (the share-clip system already stores these, bible §10).
2. The dev re-renders each take **on device** with the offline renderer in a "preview" mode: inner-display framing at native resolution, 30 fps, sound included. This is the app's own rendering of a real press, so the hand's timing is genuine. Backup: QuickTime screen capture of the inner display over USB, per Apple's guidance.
3. Capture outer-display shots (cover card) separately and cut them in.
4. Assemble at 886 × 1920. Captions use SF Pro Rounded Heavy, graphite on `#F3EEE6`, with one yellow `#FFB81C` word per caption.

**Fold glyph:** a small flat line-drawing of a generic phone folding shut, bottom-left in the lower caption band, animated in sync with the ram. It's a generic glyph, not a rendering of Apple's device.

---

## A. App Preview 1: "Feel it give" (30 s, iPhone Duo, 886 × 1920)

Audio: the app's own sound throughout (hiss, gauge ticks climbing the pentatonic scale, pops, ka-chunk, reveal sting). **No music**, as in the app. Dissolves and fades only; no transition implies a feature the app doesn't have.

| Time | Picture (in-app) | Caption (top band) | Sound (for unmuted viewers) |
|---|---|---|---|
| **00.0–00.3** | Cold open, no logo. Bubble Wrap is already on the anvil and the yellow ram is already descending from the top half. The fold glyph starts closing | **Close your phone.** | Pneumatic hiss, already open |
| **00.3–01.6** | The first bubble pops at 0.3 s. A ripple of individual pops runs front to back. The contact shadow spreads and the gauge needle climbs | **Close your phone.** (held) | Distinct pops, ticks climbing |
| **01.6–02.4** | The final volley: the rest of the sheet bursts at once, the top screen flashes white for 2 frames, and the sheet flattens | ***Feel* it give.** | Volley + tonic resolve |
| **02.4–03.0** | The ram holds at full depth, a crumb of plastic settles, and the fold glyph completes the close | ***Feel* it give.** (held) | Motor spins down |
| **03.0–04.6** | Cut to the **outer display**: the "PRESS SEALED · 48 TONS · OPEN TO SEE" card, gauge needle settling | ***Ka-chunk.*** | Ka-chunk (heavy, fixed brand sound) |
| **04.6–06.6** | Back to the inner display: the ram lifts, 2 s slow-mo replay of the volley, then the card pops in: "BUBBLE WRAP · 48 pops", and the red PRESSED stamp thunks | **Open it to see.** | Release sigh → reveal sting |
| **06.6–10.0** | **Rubber Duck, slow close.** Squeak pitch rising, sideways bulge, then the comic *bloop* flat. **00:08.0 is the poster frame** (mid-squash) | **Slowly is *better*.** | Rising squeak, bloop |
| **10.0–12.2** | Egg: hairline cracks spread, *crack*, and the yolk spreads | ***Ten* objects.** | Shell crack, soft spread |
| **12.2–13.6** | Crayon: clean SNAP, second snap, waxy smear | **Ten ways to *give*.** | Snap, snap |
| **13.6–15.0** | Jelly wobbles and splorts out of the sides | **Ten ways to *give*.** (held) | Wobble, splort |
| **15.0–17.4** | Glass Bottle: a long creak, the gauge redlines, the bottle strains | **It *creaks*…** | Creak (no screech) |
| **17.4–19.4** | Shatter: chunky, soft-edged shards, debris at 0.3× for 250 ms, one flash (< 3 Hz) | **…then it *doesn't*.** | The app's biggest event |
| **19.4–22.0** | Cake Slice reveal: frosting strands as the ram lifts, the specimen card with `CRUSHED AT 92° · 48 TONS · 112 FRAGMENTS`, the Perfect Squish mark and the PRESSED stamp | **Every press, a *specimen*.** | Reveal sting, stamp tap |
| **22.0–25.0** | Shelf: three cards shrink into slots one after another, one Golden. The "?" secret slot is visible but never opened | **Collect the *shelf*.** | Collection chime ×3 |
| **25.0–27.0** | Settings sheet: "Press without folding" toggles on, then a quick drag on the ram handle squashes the duck | **No fold? *Drag* to press.** | Squeak |
| **27.0–30.0** | End frame: the duck waiting on the empty anvil, lamps glowing. The "Squish" wordmark is centred in the top band | **No ads. No in-app purchases.** (sub-line: *Squish: Fold-to-Crush Press*) | Quiet room tone, one soft ready tap |

Notes:
- The secret object never appears, and neither does Soda Can or Gummy Bear (they're held back for a possible Preview 2).
- If a beat runs long, cut Jelly (13.6–15.0) first.
- **6.9" version:** the same structure with Pinch Press footage from a non-Duo iPhone, at the same 886 × 1920. Replace 03.0–04.6 (the cover display doesn't exist there) with the in-app sealed card and the caption "**Ka-chunk.**", and change the 25.0–27.0 caption to "**Every iPhone. Just drag.**"
- **Optional Preview 2 (15 s, "Unlocks"):** Soda Can buckling ring by ring and fizzing, Gummy Bear splitting with rainbow layers, and the Perfect Squish mark. End caption: "**Unlock them by playing.**"

---

## B. Social teaser: "Nothing real goes inside" (15 s, vertical 1080 × 1920, 30 fps)

For X, Bluesky, Mastodon, r/iPhoneDuo, TikTok, Reels and Shorts. **Real hands are fine here** (these aren't App Store rules), but **the gap between the halves must stay visibly empty**: nothing physical ever sits on the screen.

**Shot:** the iPhone Duo in tabletop pose on a plain light wooden or off-white table, from a three-quarter overhead angle so the lower screen is clearly visible. One hand on the top half. Soft window light. Phone audio captured with a clip mic near the speaker. Phone sound **on**.

| Time | Picture | On-screen caption (burned in, safe area: middle 80%) | Audio |
|---|---|---|---|
| **0.0–1.0** | Already mid-close at ~150°. An egg is on screen and the top half is coming down | **my phone is a hydraulic press now** | Hiss, ticks |
| **1.0–3.0** | Slow push. Cracks spread across the egg on the lower screen, and the hand slows | *(held)* | Ticks climbing, creak |
| **3.0–4.0** | *Crack*: the shell gives, yolk spreads, and the top screen flashes onto the lower one | **slowly…** | Crack (the money moment) |
| **4.0–6.0** | The hand continues to close. The gap is visibly empty, then the magnetic close | *(held)* | Crush bed → **ka-chunk** |
| **6.0–7.5** | Close-up of the cover display: "PRESS SEALED · 48 TONS · OPEN TO SEE" | **ka-chunk** | Ready taps |
| **7.5–10.0** | The hand opens it. The ram lifts, slow-mo replay, and the "EGG" specimen card stamps PRESSED | **then you open it** | Reveal sting |
| **10.0–13.0** | Fast cuts (0.7 s each, on screen only): duck squeak-flat, bubble-wrap ripple, glass creak-shatter, cake ooze | **10 objects. all break differently.** | Each object's signature sound |
| **13.0–15.0** | End card: the duck on the anvil, the Squish wordmark, the line below | **Squish · coming to the App Store** / small: *everything's on screen. nothing real goes inside.* | Soft ready tap |

Variants:
- **Pre-hardware (this week):** if the Duo isn't in hand yet, use a Simulator capture with the hinge slider and swap the first caption to "**building a hydraulic press for the fold**". Duo-Man drew 2.1M views from a simulator demo (research 06).
- **Launch day:** change the end card to "**Squish · out now on the App Store**". Only post the price in the post text, never in the video.
- **Creator cut:** send creators the raw 30 s, caption-free, plus the 15 s cut (see `press-kit.md`).

Caption tone: lowercase, calm, deadpan. Never "rage", "anger", "smash your stress" or "destroy". The joke is how calm it is.

---

## Sources

- App Store Connect Help, *App preview specifications* (15–30 s; ≤ 30 fps; formats and bit rates; up to 3 per device size and language; ≤ 500 MB; accepted 886 × 1920 / 1920 × 886 for iPhone Duo, 6.9" and 6.5"; default poster frame at 5 s): https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- Apple Developer, *App Previews* (show only the app; "Don't film people interacting with a device"; previews autoplay muted; no prices or timely references; appropriate for all ages; choosing a poster frame): https://developer.apple.com/app-store/app-previews/
- Research 04 §6 (average watch time 4–6 s; first-3-seconds rule; captions for silent autoplay), research 06 (Duo-Man simulator clip reach)
