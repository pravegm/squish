# Squish

A hydraulic press in your pocket. A paid toy for iPhone Duo: pick a virtual object, push the top half of the phone down slowly and watch, hear and feel it crush, then reopen to collect the pressed specimen. Runs on every iPhone (drag to press); the Duo's hinge is the hero.

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

- `Squish/Core` — press engine: hinge filtering, angle→depth mapping, state machine, material profiles (pure logic, unit-tested)
- `Squish/Feedback` — Core Haptics controller and the real-time synth (all sounds synthesised in v1)
- `Squish/Scene` — RealityKit press rig and the objects (bubble wrap, rubber duck)
- `Squish/UI` — overlays, reveal card, cover display, Tuning Lab
- `SquishTests` — press engine tests (Swift Testing)
- `design/SQUISH-DESIGN-BIBLE.md` — the single source of truth: pillars, decisions, beat-by-beat experience, specs, launch objects, build plan
- `research/` — the six design research reports behind the bible
