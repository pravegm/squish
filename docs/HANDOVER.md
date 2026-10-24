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
- **About 160 unit tests** (Swift Testing). All passing on CI.

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
3. **Hinge log.** Make a few slow folds and a few slams, tap *Copy hinge log CSV*, and paste it to Claude (whichever account owns the project). Smoothing, contact and the slam coach are tuned from it.
4. **Cover display.** Close fully. Does the sealed card appear on the outer screen? Do hinge samples still arrive while it's closed?
5. **Feel.** Press the bubble wrap and the duck at three speeds. Are the haptic grains per degree crisp or mushy? Is the strain bed too loud?
6. **Frame time.** The warped anvil should hold 120 Hz. If it stutters near contact, note the object.
7. **Both poses.** Try book pose (phone upright, fold vertical) and tabletop (bottom half flat on a table). Note which one people pick up naturally.
8. Then work through the rest of `design/FOLD-PRESS.md` §9.8 (pt/mm ruler, IMU half, eye position).

Once it feels right, tap *Copy config JSON* and send it to Claude. Those values become the defaults.

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
- **One gauge scale:** both presses read 0/40/80 tons, and every needle stops at the tonnage printed on the card.
- **Share clip render** takes about 80–130 s on CI. It should be much faster on the device. If not, the offscreen studio needs to be lighter.
  - The CI simulator's video encoder sometimes stops responding for a whole run. `ShareTests` tolerates only that specific error; please confirm a share clip on the Duo.
- **Store shots.** `FoldStoreShot.swift` renders a modelled folded Duo for App Store frames. CI writes them as `*-storeshot-*.png`.
  - They are good for layout and captions. A real hand-held Duo video from you will sell the fold better than any render.
- **Patience achievement** needs 30 s of engaged pressing. It is suppressed in CI demo runs.
- **The design-critic score** after round 9 is 8.7 for the app and 8.6 for the store set, and the launch call is yes. The reviews are in `design/FOLD-REVIEW-*.md`.
- **Hinge status vs angle.** The Duo simulator sometimes keeps reporting `.closed` while the phone reopens to about 150°. Two places now trust the angle instead when it reads above 90°: the engine (`PressEngine.staleClosedAngle`) and the reveal gate (`RevealCollectGate`). Check what the real Duo reports in the Tuning Lab hinge log.
- **Two press bugs fixed in round 7, with tests:**
  - Opening the app with the phone shut no longer seals a press you never made.
  - A stray `closed` sample no longer dismisses the reveal before you see it.

## 6. App Store screenshots

Actions → **App Store screenshots** (`store.yml`, manual dispatch) builds the whole set in about an hour:
- **Duo inner display**, 7 frames, 2007×2853.
- **Duo outer display**, 2 frames, 1398×2034.
- **6.9"**, 5 frames, 1320×2868.
- **6.1"**, 5 frames, 1206×2622.

The artifacts are `store-duo`, `store-69` and `store-61`. `store/MANIFEST.txt` lists each frame's source and any frame refused as MISSING or FLAGGED. A frame is refused when its reveal didn't hold, its settings state didn't apply, or its variant was Golden.

How the set is made, and the order of the frames, is in `docs/appstore/screenshots.md`.

**Decisions only you can make:**
- whether to use a real photo of the Duo for frame 1;
- whether App Store Connect offers the Duo screenshot slots yet;
- the subtitle.

## 7. Launch status (23 Oct 2026)

- **Design critique round 9:** store set 8.6/10, app 8.7/10, **launch call: yes**.
- **Since then, before submission:**
  - the 1.0.1 polish is done: green hero can, cake sponge band, reveal photo framing, cover centring, egg plate;
  - the privacy manifest is added;
  - the Photos permission string is added (Share → Save could crash);
  - the version is 1.0;
  - selected chips carry a non-colour outline.
- **Final assets: GitHub release [press-kit](https://github.com/pravegm/squish/releases/tag/press-kit).** It holds:
  - the 19 App Store frames, from `store.yml` run 39996965349 (0 missing / 0 flagged);
  - `appstore-screenshots-1.0.zip`, laid out for `tools/appstore/asc.swift`;
  - both App Previews, 886×1920 with sound: 6.9" (26 s) and iPhone Duo (19 s);
  - the icon, the press clips and the Game Center badges.

  Release assets don't expire the way Actions artifacts do.
- **Upload exactly:**
  - Duo inner `01–07`
  - Duo outer `O1–O2`
  - 6.9" `P1–P5`
  - 6.1" `P1–P5`
- **Never upload:**
  - `verify/` frames
  - `V4`
  - `-eye` composites
  - the iPhone 18 Pro folded scenarios (`9A–9D`, `90–99`)
- **Done by Claude** (`docs/appstore/DECISIONS.md` has one line per decision):
  - website at https://pravegm.github.io/squish/ (support, privacy, press);
  - every listing decision: subtitle, keywords, categories, price, territories, age rating, release date, previews;
  - the listing copy, the review notes, and the App Privacy and Accessibility answers;
  - the frame sign-off;
  - Game Center achievement data and badges;
  - the App Store Connect tool;
  - the press clips and paste-ready social and pitch copy.
- **Only you can do:** the short list at the top of `docs/appstore/SUBMISSION.md` §0.
  - your legal name;
  - a review contact;
  - the EU trader details, or untick the EU;
  - Apple-login actions: agreements, tax and banking, Small Business Program, the app record, the API key, archive and upload, Submit;
  - sending the posts and emails from your accounts.

**Only the real Duo can settle:**
- the display-off angle against the reveal timing;
- whether `closed` sticks above 90°;
- battery and thermals while shut;
- cold launch on the cover;
- book-pose letterboxing;
- haptics;
- the share clip.

Start with §3 above.

## 8. Handing the project to another Claude account

Everything the work depends on is in this repo. The previous account's private memory has been copied into `CLAUDE.md` and `docs/PROJECT-LOG.md`, so nothing lives outside GitHub.

**The founder does this once:**
1. **Give the new account access to GitHub.** Either sign in to `gh` on the new machine as `pravegm` (`gh auth login`), or invite the account's own GitHub user as a collaborator with **Write** access: Settings → Collaborators. It needs to push to `main` and run workflows.
2. **Clone the repo:** `git clone https://github.com/pravegm/squish.git`. Open the folder in Claude Code; `CLAUDE.md` loads automatically.
3. **Tell it the standing rules,** or let it read them in `CLAUDE.md`: push straight to `main` without asking; Duo-first is the bar; it is the whole studio.
4. **Give it your real-Duo findings.** Paste the Tuning Lab hinge log CSV and config JSON (Settings → long-press Version), and describe what felt off. That is the most valuable input it can get now.

**The new account's first steps:**
1. Read `CLAUDE.md`, then `design/FOLD-REVIEW-9.md` (the latest critique, the launch call and the 1.0.1 list), then this file.
2. Run `gh run list -R pravegm/squish -L 5` to check that CI is green on `main`.
3. Tune from the founder's device data. Keep the critique loop going (`CLAUDE.md`, "The round loop") for 1.0.1.

**Nothing external besides GitHub:**
- no secrets in the repo, no API keys, no paid services;
- CI uses GitHub's own macOS runners (`xcode-27`);
- the only third-party tool is the open-source `hinge` simulator CLI, installed by Homebrew inside the Duo workflow.

Signing (team, certificates) and App Store Connect access stay with the founder.

## 9. Where things are

- **Design:**
  - `design/SQUISH-DESIGN-BIBLE.md` is the product.
  - `design/FOLD-PRESS.md` covers the Duo experience.
  - `design/ARCHITECTURE.md` describes the code contracts.
- **Research:** `research/01–06`.
- **App Store:** `docs/appstore/` has the metadata, screenshot plan, preview script, review notes (θ_end must match what you measure), privacy policy, press kit and social plan.

## 10. Builds without a Mac that runs Xcode 27 (24 Oct 2026)

The founder's Mac is **Intel**, and Xcode 27 doesn't run on Intel Macs, so that Mac can't build or run Squish.

**Every device build goes through `.github/workflows/testflight.yml`.** It runs on GitHub's Apple-silicon runner with Xcode 27.1:
- it archives a signed Release, letting Xcode create the signing assets from the App Store Connect API key;
- it uploads the build to App Store Connect;
- the founder installs it on the Duo from the **TestFlight** app.

The one-time setup is in `docs/appstore/SUBMISSION.md` §5a: the Developer Program, the app record, an Admin API key, and 4 repo secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`).

The §2 "Build and run" steps apply only on an Apple-silicon Mac.
