# CLAUDE.md: taking over Squish

Read this first. It is everything the previous Claude account knew that the code doesn't say on its own.

## What this is

**Squish: Fold-to-Crush Press** is a paid (£2.99, no ads, no in-app purchases) iPhone toy, built **iPhone Duo first**. The iPhone Duo is Apple's foldable (iOS 27.1). The phone itself is the hydraulic press: an object lies on the inner screen, you close the phone slowly, it crushes in real time (driven by the hinge angle), and you reopen to collect the pressed specimen. Regular iPhones get a drag-to-press fallback machine called the **P-48**.

The founder (GitHub `pravegm`) is the product owner. There are no other humans. Claude acts as founder, designer and developer, and works as a "firm": parallel subagents for each role, plus a design-critic loop.

## The bar (non-negotiable)

1. **Duo-first.** On a Duo, the two halves of the inner screen *are* the press plates. The **anvil** (bottom half in tabletop pose, trailing page in book pose) is a 3D RealityKit view. The **platen** (the other half) is a 2D ink-print stack. Closing the real phone closes the press. Never let a "machine drawn inside the screen" be the hero on a Duo; that is the P-48, and it is only for phones that don't fold.
   - The founder rejected exactly that once ("the entire point was that we leverage the folding mechanism… with the screen acting like the press"). Judge every change first on real iPhone Duo simulator frames.
2. **Worth paying for.** The founder rejected an early build as "horrible… would you ever even use this app?". Polish is the product: haptics, sound, visuals, copy.
3. **Truthful store frames.** No frame may show anything the app doesn't do. Never use iPhone 18 Pro folded shots, because that phone doesn't fold.

## Working rules

- **Push straight to `main`.** No feature branches and no PRs. You don't need to ask before committing or pushing (the founder's standing instruction).
- **Repo:** https://github.com/pravegm/squish. It is **public**, because the founder chose that to get unlimited CI minutes.
  - Keep personal and employer data out of it.
  - Commits are authored as the founder's GitHub noreply address.
  - End commit messages with the attribution line your harness gives.
- **There is no Mac on the Claude side. CI is the compiler.** Every Swift change is unverified until a GitHub Actions run passes. Batch changes into rounds, push, read the failures, fix.
- **Talk to the founder in plain language.** Be blunt about quality. Don't claim anything works until CI or a frame shows it.

## Build (founder, on a Mac)

```bash
brew install xcodegen && xcodegen generate && open Squish.xcodeproj
```

- Requires Xcode 27.1 (iOS 27.1 SDK, for the hinge API).
- The deployment target is iOS 18; hinge code is behind `#available(iOS 27.1, *)`.
- Swift 5 language mode.
- The `.xcodeproj` and `Info.plist` are generated, not committed (`project.yml` is the source).
- Details and the first-hour device checks are in `docs/HANDOVER.md`.

## CI: your only compiler and camera

| Workflow | Trigger | What it does | Artifacts |
|---|---|---|---|
| `ci.yml` (CI) | every push touching `Squish/`, `SquishTests/`, `project.yml`, `ci/`, workflows | builds and runs all tests (~160, Swift Testing) on an iPhone 18 Pro sim, then captures a screenshot subset and renders the app icon | `logs` (build.log, errors.txt), `screenshots` (incl. `AppIcon-1024.png`) |
| `duo.yml` (Duo fold screenshots) | manual | downloads the iOS 27.1 runtime, boots a real **iPhone Duo** simulator, drives the hinge with the `hinge` CLI (`brew install artemnovichkov/tap/hinge`), and captures book-pose sweeps, tabletop store shots, UI frames and `verify/` frames | `duo-screens` |
| `store.yml` (App Store screenshots) | manual, ~1 h | builds the full upload set: Duo inner 01–07, outer O1–O2, 6.9" and 6.1" P1–P5, each with a `MANIFEST.txt` | `store-duo`, `store-69`, `store-61` |

Useful commands:

```bash
gh run list -R pravegm/squish -L 5
gh workflow run store.yml -R pravegm/squish --ref main
gh run watch <id> -R pravegm/squish
gh run download <id> -R pravegm/squish -D <empty-dir>
```

- **Concurrency:** `ci.yml` cancels an in-progress run on a new push. Don't push while you wait on a CI → store chain, or the store run never starts.
- **Manifests:** a good set ends `missing: 0  flagged: 0` in every `MANIFEST.txt`. The checks cover source size and orientation, that reveals held, variant (no Golden or surprise in store frames), demo state and in-frame bounds. Still look at the frames yourself: the manifest once said 0 while 07 was a landscape capture.
- **The app talks to CI through log markers on stdout.** The scripts grep these, so don't rename them:
  - `SQUISH-T …`: timings, demo, storeshot, toast and capture.
  - `SQUISH-H …`: one line per hinge sample, with phase, depth and compression, logged *after* the engine takes the sample.
  - `SQUISH-F …`: Fold stage frames, paused/resumed, and reveal dark/lit.
  - `SQUISH-CLIP …`: the share clip.
  - In demo runs stdout is line-buffered (`DemoMode.swift`), but log lines can still reach the scripts seconds late. For exact timing, the app captures itself (`DemoCapture.window`).
- **Demo mode:** DEBUG only. Scripted states come from the `-squishDemo "key=v;key"` launch argument. Every key is documented at the top of `Squish/App/DemoMode.swift`; the scenario lists are in `ci/scenarios.txt`.

## Code map

- `Squish/Core`: the press engine.
  - Pure logic, unit-tested: One-Euro filter, angle→depth mapping, state machine (idle/armed/pressing/sealed/revealing), material profiles, catalog, variants (Golden 1/50, surprises).
  - `RevealCollectGate`: the reveal is only collected by a deliberate fold or close.
- `Squish/App`:
  - `PressDirector` is the hub: engine, scene, Fold controller, feedback, collection, hinge, demo runner and store-shot helpers.
  - `HingeReader` wraps `onHingeChange`.
  - `DemoMode` holds the CI keys.
- `Squish/Scene`:
  - `PressScene`: RealityKit P-48 rig, studio and IBL.
  - `Objects/*`: 10 objects with procedural meshes and deformation.
  - `Kit/*`: mesh, debris and particle helpers.
  - `Fold/*` is the **Duo experience**:
    - `FoldGeometry`: layout and eye model.
    - `FoldAnvil`: warped 3D half.
    - `FoldPlaten`, `FoldStamps`: ink print, splat, PRESSED.
    - `FoldBezel`: gauge and live hinge readout.
    - `FoldPressController`, `FoldPressView`.
    - `FoldRenderGate`: pauses rendering while shut.
    - `FoldStoreShot`: marketing renders of a modelled folded Duo.
- `Squish/Feedback`: Core Haptics and a real-time synth. All sound is synthesised, so there are no audio files. `CueBook` and `Recipes/*` hold per-object sound and haptic recipes.
- `Squish/UI`: SwiftUI (root, overlays, reveal card, cover display, shelf, settings, Tuning Lab, `AppIconArt` (CI renders the icon), `Theme`).
- `Squish/Collection`: specimens (JSON plus thumbnails), unlocks, achievements, Game Center, and `SpecimenPrint`, which rebuilds a print from a record.
- `Squish/Share`: share image and share clip (offscreen ARView → AVAssetWriter → AAC → mux).
- `SquishTests`: PressEngine, ObjectCatalog, Feedback, Collection, Scene, Share and FoldPress tests.
- `ci/`: screenshot scripts, the `scenarios.txt` table, the `store-frame.swift` captioner, and `store-set.sh`, which assembles the upload set.

## Design documents (read in this order)

1. `design/SQUISH-DESIGN-BIBLE.md`: pillars, decisions, the beat-by-beat experience, specs. It carries a Duo-first amendment at the top.
2. `design/FOLD-PRESS.md`: the Duo experience spec (mapping §4, implementation §9, Week-0 device checks §9.8, acceptance §12).
3. `design/ARCHITECTURE.md`: the module contracts. Update it when you change `Squish/Shared/Contracts.swift`.
4. `design/FOLD-REVIEW-1…9.md`: the design-critic reviews, one per round (history below).
5. `design/VISUAL-TARGET.md`, `research/01–06` (haptics, sound, visuals, psychology, hinge UX, market).
6. `docs/appstore/*`: metadata, screenshot plan (`screenshots.md` explains how the set is made), review notes, privacy, press kit, social plan, achievements, launch checklist.

## How the work was run: the round loop

1. A **design critic** subagent (fresh, general-purpose) reviews the latest real frames. It is told the bar and given the previous review, and it writes `design/FOLD-REVIEW-N.md`: a score /10, the status of last round's items, ranked issues with file:line and the fix, a top 5, and a launch call.
2. Split the top fixes across **3–4 engineer subagents with disjoint file ownership**, for example:
   - Store shot: `FoldStoreShot`, the demo section of PressDirector, `DemoMode`, `ci/`.
   - Fold: `Scene/Fold/*`, `PressScene`.
   - Objects: `Scene/Objects/*`, `Kit/*`.
   - UI: `UI/*`, `Collection/*`.
   - Core: `Core/*`, the non-demo parts of PressDirector.

   Tell each one explicitly which files are theirs and which are others'. They can't compile, so ask them for a list of compile risks, and tell them not to commit.
3. Integrate: run `bash -n` on the scripts, commit one round commit, and push. Fix CI failures yourself; they are usually small Swift Testing or type issues.
4. Run `store.yml` (or `duo.yml`), check the manifests, **look at the key frames yourself**, then go back to step 1.

Scores so far:

| Round | Score |
|---|---|
| R1 | 4.2 |
| R2 | 5.8 |
| R3 | 6.3 |
| R4 | 7.1 |
| R5 | 7.6 |
| R6 | set 7.0 / app 7.8 |
| R7 | set 7.9 / app 8.2 |
| R8 | set 8.2 / app 8.5 |
| R9 | set **8.6** / app **8.7**, launch call **yes** |

`docs/PROJECT-LOG.md` summarises each round.

## Gotchas learned the hard way

- **Swift Testing:**
  - `#require` can't nest inside `#require` (recursive macro expansion).
  - Compare optionals against typed literals, e.g. `CGFloat(909 - 455)`; an untyped literal picked a non-numeric `==`.
  - Hoist throwing calls out of `#expect`.
- **`PressConfig` is `Codable` with synthesized keys.** Adding a field silently resets saved tunings, so put new tunables elsewhere (see `PressEngine.staleClosedAngle`).
- **Duo simulator hinge quirks:**
  - `closed` can stay set while the phone reopens to ~150°, so the engine and the reveal gate trust the angle above 90°.
  - The first open sample after a closed launch is a state, not a transition (`PressEngine.ingestSample`).
  - Programmatic rotation needs `UIRequiresFullScreen: true` (it is set in `project.yml`).
  - The `hinge` CLI occasionally fails a move; `hinge_to` retries.
- **Rendering:** the inner ARViews are taken out of the window while the inner display can't be seen (`FoldRenderGate`). A blind clock keeps the engine, haptics and audio running. `stray=0` in the `SQUISH-F resumed` line proves RealityKit stopped rendering.
- **Isolation:** `@MainActor` everywhere in views and controllers. Pure maths lives in nonisolated enums so tests can call it.
- **This Windows host** (if you run on it): Bash ignores `cd`, so use absolute paths and `git -C`. Expect LF→CRLF warnings (harmless). There is no Python; use Node for quick maths models.

## Status (end of round 9) and what's next

- **Code and art:** submittable as 1.0. The last green store run (`store.yml` run 39952047687) has 0 missing and 0 flagged.
  - Achievement toasts have now been seen on screen (`verify/duo-reveal-toast-app.png`).
- **The founder now has an iPhone Duo.** Real-device findings outrank everything in the simulator. Ask for the Tuning Lab hinge log (Settings → long-press Version), then tune from the real data:
  - the display-off angle against `endAngle` (48°) and the reveal light threshold (55°);
  - whether `closed` sticks above 90° on hardware;
  - battery and heat while shut;
  - book-pose letterboxing;
  - haptics;
  - the share clip.
- **1.0.1 list:** in `design/FOLD-REVIEW-9.md` §4 (the orange hero can on the shelf, the cake top clipping to white, the P2 photo framing, the cover picker centring, the shelf orientation re-confirm, the icon hash check).
- **Founder-only launch tasks:** `docs/HANDOVER.md` §7.
