# Founder handover

Read this first when you have the Mac and the Duo in hand. It covers what exists, how to build it, what to check on the device in the first hour, and what only you can do.

## 1. What's in the build

- **Fold Press is the product.** On an iPhone Duo the two halves of the inner screen are the press plates:
  - The **anvil** is the bottom half in tabletop, or the trailing page in book pose. It is a 3D RealityKit view, warped so it reads as the floor of the press.
  - The **platen** is the other half. It is a 2D layer stack: shadow, contact kiss, ink print, splat.
  - Closing the phone crushes the object. Reopening it reveals the pressed specimen.
  - Spec: `design/FOLD-PRESS.md`.
- **P-48 (touch press)** is the fallback for every other iPhone, and for Settings → *Press without folding*. You drag down to drive a toy hydraulic press.
- **Ten objects** with fracture tables, rare variants (golden 1 in 50, surprises), and unlock rules. See `Squish/Core/ObjectCatalog.swift`.
- **Collection:**
  - a shelf of pressed specimens and card detail;
  - share image and share clip (MP4 with audio);
  - Game Center achievements;
  - the cover-display card when the phone is closed.
- **Sound and haptics:** all sound is synthesised in real time; there are no audio files. Core Haptics recipes per object. Soft style in Settings.
- **87 unit tests** (Swift Testing). All passing on CI.

## 2. Build and run

```bash
brew install xcodegen
git clone https://github.com/pravegm/squish.git && cd squish
xcodegen generate && open Squish.xcodeproj
```

1. In the Squish target, open *Signing & Capabilities* and set your team.
2. Keep the Game Center capability on.
3. Pick the Duo and press Run; ⌘U runs the tests.
4. Re-run `xcodegen generate` after adding or removing files.

You need **Xcode 27.1** (iOS 27.1 SDK) for the hinge API. The deployment target is iOS 18; the hinge code is behind `#available(iOS 27.1, *)`.

CI runs every push to `main`:
- `.github/workflows/ci.yml` builds, tests and captures screenshots on an iPhone 18 Pro simulator.
- `duo.yml` (manual) boots a real **iPhone Duo** simulator and sweeps the hinge with the `hinge` CLI. See `docs/DUO-CI.md`.
- Screenshots and logs are uploaded as run artifacts.

## 3. First hour on the Duo (do these before tuning anything)

Open the **Tuning Lab**: Settings → long-press the **Version** row. Then work through these checks:

1. **Display-off angle.** Close the phone slowly and note the raw angle at which the inner screen goes dark. `endAngle` (default 48°) must sit a few degrees above it, or the press never seals.
2. **Sample rate.** Watch *Hinge updates / s* while folding. The simulator gave about 72 updates per sweep. The One-Euro filter is tuned for that.
3. **Hinge log.** Make a few slow folds and a few slams, tap *Copy hinge log CSV*, and paste it to me. I tune smoothing, contact and the slam coach from it.
4. **Cover display.** Close fully. Does the sealed card appear on the outer screen? Do hinge samples still arrive while it's closed?
5. **Feel.** Press the bubble wrap and the duck at three speeds. Are the haptic grains per degree crisp or mushy? Is the strain bed too loud?
6. **Frame time.** The warped anvil should hold 120 Hz. If it stutters near contact, note the object.
7. **Both poses.** Try book pose (phone upright, fold vertical) and tabletop (bottom half flat on a table). Note which one people pick up naturally.
8. Then work through the rest of `design/FOLD-PRESS.md` §9.8 (pt/mm ruler, IMU half, eye position).

Once it feels right, tap *Copy config JSON* and send it to me. Those values become the defaults.

## 4. Only you can do these (dated, from `docs/appstore/launch-checklist.md`)

| When | What |
|---|---|
| **Now (Thu 22 Oct)** | Reserve **"Squish: Fold-to-Crush Press"** in App Store Connect with bundle ID `com.pravegm.squish`. Fallback name: Hingepress. Enrol in the Small Business Program. Set up a domain with `/privacy`, `/support` and `/press`; the copy is in `docs/appstore/`. |
| Fri 23 – Sun 25 Oct | Film the 15 s teaser (`preview-video.md` §B). Post it, then email the tip lines (`press-kit.md`). |
| Sun 1 Nov | Choose the subtitle: the £/$ joke or the fallback **"The priciest hydraulic press"**. The joke risks Guideline 2.3.7 (`metadata.md` §2). |
| **By Tue 3 Nov** | Submit **featuring nomination 1**. The text is in `featuring-nomination.md`. |
| Before the pre-order build (5 Nov) | Create the 10 Game Center achievements. The IDs and copy are in `achievements.md`; the IDs must match exactly. |
| Tue 24 Nov | Release. |

## 5. Known issues and open items

- **Real-device timing is unverified.** The CI simulator renders slowly. Startup took up to 8 s before the studio lighting loaded; the slow texture work has since been moved off the main thread. Please time a cold launch on the Duo.
- **Book-pose vs tabletop framing** was tuned on the simulator only. Eye position (FOLD-PRESS §9.4) needs real people.
- **App icon:** CI renders `AppIcon-1024.png` from `AppIconArt.swift` and it gets committed into the asset catalog. Check it on the home screen.
- **Gauge scales differ.** The P-48 gauge reads 0–60 tons; the Fold Press bezel reads 0–80. Pick one.
- **Share clip render** takes about 80–130 s on CI. It should be much faster on the device. If not, the offscreen studio needs to be lighter.
  - The CI simulator's video encoder sometimes stops responding for a whole run. `ShareTests` tolerates only that specific error; please confirm a share clip on the Duo.
- **Store shots.** `FoldStoreShot.swift` renders a modelled folded Duo for App Store frames. CI writes them as `*-storeshot-*.png`.
  - They are good for layout and captions. A real hand-held Duo video from you will sell the fold better than any render.
- **Patience achievement** needs 30 s of engaged pressing. It is suppressed in CI demo runs.
- **The design-critic score** for Duo frames was 6.3/10 after round 3. The target before submission is 8. The reviews are in `design/FOLD-REVIEW-*.md`.

## 6. Where things are

- **Design:**
  - `design/SQUISH-DESIGN-BIBLE.md` is the product.
  - `design/FOLD-PRESS.md` covers the Duo experience.
  - `design/ARCHITECTURE.md` describes the code contracts.
- **Research:** `research/01–06`.
- **App Store:** `docs/appstore/` has the metadata, screenshot plan, preview script, review notes (θ_end must match what you measure), privacy policy, press kit and social plan.
