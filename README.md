# Squish

A hydraulic press in your pocket. Squish is a paid toy built for iPhone Duo. On a Duo, the two halves of the inner screen are the press plates. Close the phone slowly to crush the object, watching, hearing and feeling it give, then reopen to collect the pressed specimen. Every other iPhone gets a drag-to-press machine, the P-48.

**Start here:**
- [`CLAUDE.md`](CLAUDE.md): the takeover guide (the bar, working rules, CI, code map, how the work is run, gotchas, status).
- [`docs/HANDOVER.md`](docs/HANDOVER.md): the founder's build steps, first-hour device checks, launch tasks and upload list.
- [`docs/PROJECT-LOG.md`](docs/PROJECT-LOG.md): the decisions and the history.

**Status (23 Oct 2026):** the code and art are ready to submit as 1.0 (design critique round 9: store set 8.6/10, app 8.7/10). Real-device tuning on the Duo is next.

## Build and run (on a Mac)

Requirements: macOS with **Xcode 27.1** (iOS 27.1 SDK, needed for the hinge API) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/pravegm/squish.git
cd squish
xcodegen generate
open Squish.xcodeproj
```

1. Select the **Squish** target → *Signing & Capabilities* → choose your team.
2. Pick your iPhone Duo (or the iPhone Duo simulator) and press **Run**.
3. Run the tests with **⌘U**.

Re-run `xcodegen generate` whenever files are added or removed. The `.xcodeproj` is generated, so it isn't committed.

**Simulator:** the iPhone Duo simulator has fold controls; hold ⌥ for a continuous hinge slider. On other simulators and iPhones, drag down on the screen to press.

## On-device checks (first run on the Duo)

Open the **Tuning Lab** (Settings → long-press the **Version** row):
1. Close the phone slowly and note the **raw angle** when the inner screen turns off. Set **End angle** a few degrees above it.
2. Watch **Hinge updates / s** while folding. That's the real sample rate.
3. Tap **Copy hinge log CSV** after a few slow and fast folds and paste it into an issue or chat, so the smoothing can be tuned from real data.
4. Tap **Copy config JSON** once it feels right.

## Layout

- `Squish/Core`: the press engine. Hinge filtering, angle→depth mapping, the state machine, material profiles, catalog and variants. Pure logic, unit-tested.
- `Squish/App`: `PressDirector` (the hub), the hinge reader, and demo mode for CI.
- `Squish/Scene`:
  - `Fold/`: the iPhone Duo Fold Press.
  - the P-48 rig (`PressScene`).
  - the 10 objects (`Objects/`).
- `Squish/Feedback`: Core Haptics and the real-time synth. All sound is synthesised.
- `Squish/UI`, `Squish/Collection`, `Squish/Share`: interface, specimens and achievements, and the share image and clip.
- `SquishTests`: Swift Testing suites.
- `ci/`, `.github/workflows/`: build and test, Duo simulator captures, and the App Store screenshot pipeline.
- `design/`:
  - the bible (`SQUISH-DESIGN-BIBLE.md`);
  - the Duo spec (`FOLD-PRESS.md`);
  - the architecture;
  - the critique rounds (`FOLD-REVIEW-1…9.md`).
- `docs/appstore/`: metadata, screenshot plan, review notes, privacy, press kit, launch checklist.
- `research/`: the six design research reports behind the bible.
