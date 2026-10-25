# Project log

This is how Squish got here, kept so a new owner (human or Claude) inherits the reasons as well as the code. The newest entry is last. Every round's full critique is in `design/FOLD-REVIEW-N.md`.

## Founder decisions (22 Oct 2026)

- **The idea.** A paid iPhone Duo toy in the spirit of *Toastie* (close the phone and it toasts). The phone is a hydraulic press, and folding it crushes the object. It was chosen because the fold-angle mechanic was unclaimed and the "hydraulic press" genre is already viral.
- **Name:** "Squish: Fold-to-Crush Press" (fallback "Hingepress").
- **Price:** £2.49, no ads, no in-app purchases.
- **Rating:** 9+. The 12+ teen tone lives only in the copy; there's no gore.
- **Devices:** universal iPhone app. The Duo is the hero; other iPhones get the P-48 drag-to-press machine.
- **Sound:** free and synthesised first, with a path to paid libraries later. Today every sound is synthesised.
- **Schedule:** ship as soon as possible, about 4 weeks, with about 10 objects and more in free updates. The launch plan targets **Tue 24 Nov 2026** (`docs/appstore/launch-checklist.md`).
- **Team:** no other humans. Claude is the whole studio, and is open to buying asset libraries if needed.
- **Process:** design and UX before code. "Do iterations… operate as an entire firm… test compile without me."
- **Git:** push straight to `main` with no approvals, and make the repo public for unlimited CI minutes.
- **Two corrections that set the bar:**
  - On the early screenshots: "the UI and UX looks horrible… would you ever even use this app?"
  - On the Duo: "the entire point was that we leverage the folding mechanism… with the screen acting like the press. This really is an iPhone Duo-first app."

## iPhone Duo platform facts (researched 22 Oct)

- **Hinge API:** SwiftUI `onHingeChange` and UIKit `UIHingeInteraction` give a `DeviceHinge?` with `angle` (180° is flat) and `status` (closed / partiallyOpen / fullyOpen). It is nil without a hinge.
- **Accuracy:** about ±5°. The update rate is system policy; the simulator gives about 72 updates per sweep.
- **Displays:** closing the phone moves the app to the outer display, and the app keeps running. Inner book pose is 951×669 pt with a 40 pt vertical crease; tabletop is 669×951 pt. The outer display is 466×678 pt.
- **Sources:**
  - Apple dev forums thread 847644
  - github.com/artemnovichkov/iPhone-Duo-by-Examples (also the `hinge` simulator CLI used in CI)
  - foldhunt.com/iphone-duo

## Rounds

| When | What landed | Critic score |
|---|---|---|
| 22 Oct | Research (6 reports), design bible, App Store kit, architecture and visual target | — |
| 22 Oct | Milestone 1: engine, haptics, synth, RealityKit scene. Then the full product: 10 objects, P-48 rig, collection, shelf, cover, share clip | UX review 1, visual review 1 |
| 22 Oct | Cloud CI (macOS runners), plus an iPhone Duo simulator CI with real hinge angles | — |
| 22 Oct | **Fold Press**: the Duo halves become the press (warped anvil ARView, 2D platen, bezel) | FOLD-REVIEW-1: **4.2** |
| 22 Oct | Duo round 2: exposure, ink prints, book-pose diptych | R2: **5.8** |
| 22 Oct | Round 3: flat glass shards, app icon art, CI waits on app log markers | R3: **6.3** |
| 23 Oct | Round 4: tone match, lean, squash latch, the Patience achievement rule, first store-shot renderer | R4: **7.1** |
| 23 Oct | Round 5: tabletop hero shot, `UIRequiresFullScreen` so the Duo can rotate to tabletop | R5: **7.6** |
| 23 Oct | Round 6: squeeze shading, labels that match the readout, store-set pipeline (`store.yml`), bubble wrap rebuild | R6: set **7.0**, app **7.8**. Two app bugs found: a phantom press on a closed launch, and reveals eaten by stray closed samples |
| 23 Oct | Round 7: both bugs fixed with tests (`RevealCollectGate`, arm only from an observed open hinge), set re-cut, stale-closed fix | R7: set **7.9**, app **8.2** |
| 23 Oct | Round 8: candle bug, render pause while shut (`FoldRenderGate`), reveal ready when the display relights, Duo shelf split, duck icon | R8: set **8.2**, app **8.5**. "Binary ready" |
| 23 Oct | Round 9: 07 in portrait with source-size checks, seeded specimens carry real prints, visible glass crack, crushed cake | R9: set **8.6**, app **8.7**. **Launch call: yes** |
| 23 Oct | Toasts finally seen on screen (the app captures its own window); P5 caption made true ("No ads. No upsells.") | — |

## Where it stands

- **Ready:** code and art, as 1.0.
- **Founder tasks before submitting:** `docs/HANDOVER.md` §7 (metadata placeholders, Game Center achievements, subtitle, review notes, release date).
- **Next work:** real-device tuning on the founder's Duo, then the 1.0.1 list in `design/FOLD-REVIEW-9.md`.
