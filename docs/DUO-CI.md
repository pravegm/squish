# Duo fold screenshots in CI

`.github/workflows/duo.yml` (manual: **Actions > Duo fold screenshots > Run workflow**) builds Squish for
an **iPhone Duo simulator** on our only Mac, the GitHub `xcode-27` runner. It moves the **real simulated
hinge** and uploads `duo-screens/`, which holds a screenshot of every object at every angle, the closed cover
display and the reopen reveal. `ci.yml` (iPhone 18 Pro, iOS 27.0) is unchanged.

## Pipeline

| Step | What happens | Confidence |
|---|---|---|
| Select Xcode 27.1 | `sudo xcode-select -s /Applications/Xcode_27.1.app`. This is a symlink to `Xcode_27.1_Release_Candidate.app`, build 27A9275, and "the RC is the GA". | Verified (image readme, runner-images#15000) |
| Runtime present? | The image only ships iOS 27.0, which has no Duo. The step checks `simctl list runtimes -j` for `com.apple.CoreSimulator.SimRuntime.iOS-27-1`. | Verified |
| Cache restore | `actions/cache/restore` restores `~/simruntime`, keyed `ios-27.1-simruntime-<Xcode build>-v1`. | Inferred (standard actions/cache) |
| Download | `xcodebuild -downloadPlatform iOS -exportPath ~/simruntime` runs up to 3 tries. With Xcode 27.1 selected it fetches **iOS 27.1 (24A94425)**, a 7.85 GB arm64 runtime. The first try can fail with `DVTDownloadableErrorDomain Code=41`, and a retry works. | Command and build: verified (#15000). Size and retry: verified (blakecrosley.com). `-exportPath`: verified for Xcode 16 and later, not yet on 27.1. |
| Cache save | Runs right after the download, so a later failure still keeps the dmg. | Inferred |
| Import | `xcodebuild -importPlatform <dmg>`, falling back to `xcrun simctl runtime add <dmg>`. The dmg is then deleted to free about 8 GB. | Inferred (Xcode 16 and later behaviour) |
| Create and boot | Creates the device with `xcrun simctl create "Squish Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1` and starts `simctl boot` before the build so the two overlap. The 27.1 runtime supports **only** the iPhone Duo. | Verified (#15000, blakecrosley.com) |
| Hinge tools | Installs `brew install artemnovichkov/tap/hinge`, then builds two fallbacks: duo-fold-control `duo-hinge` (clang) and `foldctl` (brew). | README-verified. Not yet run on this runner. |
| Build | `xcodegen generate`, then `xcodebuild build -destination id=<UDID> -derivedDataPath build CODE_SIGNING_ALLOWED=NO`. `otool` prints `LC_BUILD_VERSION`: the app must be linked against the 27.1 SDK, or it runs letterboxed in compatibility mode. | Inferred from ci.yml |
| Capture | Runs `ci/duo-screenshots.sh`. Details are in the next section. | See below |

Every step has a `timeout-minutes`. Every long shell call is wrapped in `gtimeout` (coreutils), and the
script wraps every `simctl`, `devicectl` and hinge call in `to <secs>`. The job timeout is 90 minutes.

## Capture script (`ci/duo-screenshots.sh`)

For each object:

1. Set the hinge to 180° and launch with `-squishDemo "object=<kind>;duo"`, sending stdout and stderr to `logs/<kind>.txt`.
2. Wait for the app's `SQUISH-T frame 120` line, for at most 45 s. iOS 27.1 simulators start slowly.
3. For each angle in `ANGLES`, **sweep** from the previous angle at 1.5 s per 30°. `hinge sweep` runs at 60 Hz, so the app gets a continuous stream of `onHingeChange` updates. A confirmed `set` follows, then a 2.5 s settle for the display switch, then a capture of `<kind>-<angle>.png`.
4. Sweep to 0° and capture `<kind>-closed.png` from the cover display.
5. Sweep to 170° and capture `<kind>-reveal.png`. Opening from shut, the cover stays lit until about 150°, so the reveal is taken at 170°.

**Displays.** A Duo simulator has two displays, and `simctl io screenshot` without `--display` fails with
`Invalid argument`. Sources disagree on the display names:

- The hinge README uses `LCD` (cover) and `LCD-1` (inner), or the numeric ids 1 and 3.
- `simctl io enumerate` lists `primary` and `primary-1`.

The script logs `simctl io enumerate`, then probes these candidates once:

- inner: `LCD-1`, `primary-1`, `3`, `internal`
- cover: `LCD`, `primary`, `1`, `external`

It captures **both** panels into `raw/<shot>-inner.png` and `raw/<shot>-cover.png`. It measures the brightness
of each with `sips`, scaling it to a 16×16 BMP. The lit panel becomes `<shot>.png`, because a panel that is off
captures as all black. Each shot also appends `hinge posture` and `devicectl device info displays` (the active
panel) to `logs/posture.txt`.

**Hysteresis** (from the iphone-duo-simulator-skill notes):

- Closing from flat, the inner panel stays lit down to about 20°, so every angle from 180° to 45° shows on the inner panel.
- 0° switches to the cover panel.
- The display switch takes 1–2.5 s after the angle changes.
- The simulator can sometimes stop following the hinge while still reporting angles. A `shutdown` and `boot` fixes it.

**Never** run `simctl io … screenConfig` on the Duo. It crash-loops SpringBoard.

### Hinge drivers and the fallback

`HINGE_DRIVER=auto` (the default, and the workflow's `driver` input) probes each driver with a real move from
180° to 150° and back to 180°. It uses the first driver that passes, in this order:

1. **hinge**. A helper compiled against the simulator SDK runs **inside** the simulator through
   `xcrun simctl spawn`. It posts Device Hub's vendor HID event (usage page 0xFF61, usage 0x5B,
   source `hinge-slider-control`) through `IOHIDEventSystem`, and confirms the angle through `CMAngleManager`.
   - It needs no Simulator.app and no Device Hub.
   - No host Accessibility or TCC permission is involved, so there is nothing to click.
   - Its `posture` subcommand uses `devicectl`.
2. **duo-hinge** (tosbaha/duo-fold-control). A host CLI that sends Device Hub's fold message to CoreSimulator over XPC.
   - Its README says it passes on a headless simulator booted with `simctl boot`, with Device Hub closed.
   - It can only set an angle, and each call takes about 1–1.5 s. The script emulates a sweep in 10° steps.
3. **foldctl**. Uses the private CoreDevice API from the host. It can only set an angle, and waits up to 60 s for the simulator to report it.

If every probe fails, the script still captures each object at 180° and **exits 3**. The artifact is still
uploaded, and `logs/run.txt` shows each probe's error.

**UI-test fallback.** Use it if `simctl io screenshot` cannot capture the inner display headless. It needs no app
code changes. `XCUIScreen.main` is always the cover display, so the test captures `XCUIScreen.screens` and
attaches the largest one. The hinge still moves through duo-fold-control's HTTP bridge, which wraps `duo-hinge`.

Add this to `project.yml`. It uses a separate scheme, so `ci.yml` never runs it on the iPhone 18 Pro:

```yaml
targets:
  SquishDuoUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [SquishDuoUITests]
    dependencies: [{ target: Squish }]
    settings: { base: { GENERATE_INFOPLIST_FILE: YES, TEST_TARGET_NAME: Squish } }
schemes:
  SquishDuo:
    build: { targets: { Squish: all, SquishDuoUITests: [test] } }
    test: { targets: [SquishDuoUITests] }
```

Copy `DuoDemo/DuoDemoUITests/DuoFold.swift` (MIT) from tosbaha/duo-fold-control into `SquishDuoUITests/`,
then add `SquishDuoUITests/DuoFoldScreensTests.swift`:

```swift
import XCTest

final class DuoFoldScreensTests: XCTestCase {
    let angles: [Double] = (ProcessInfo.processInfo.environment["ANGLES"] ?? "180 150 120 100 90 75 60 45")
        .split(separator: " ").compactMap { Double($0) }
    let objects = (ProcessInfo.processInfo.environment["OBJECTS"] ?? "rubberDuck bubbleWrap glassBottle sodaCan")
        .split(separator: " ").map(String.init)

    func testFoldSweep() throws {
        for object in objects {
            DuoFold.set(degrees: 180)
            let app = XCUIApplication()
            app.launchArguments = ["-squishDemo", "object=\(object);duo"]
            app.launch()
            sleep(8)
            var current = 180.0
            for angle in angles + [0, 170] {
                // Emulated sweep: 10° steps (~1 s each through duo-hinge).
                let step = angle < current ? -10.0 : 10.0
                while abs(angle - current) > 10 { current += step; DuoFold.set(degrees: current) }
                DuoFold.set(degrees: angle); current = angle
                Thread.sleep(forTimeInterval: 2.5)
                let name = angle == 0 ? "\(object)-closed" : angle == 170 ? "\(object)-reveal" : "\(object)-\(Int(angle))"
                let screen = angle == 0 ? DuoDisplay.cover : DuoDisplay.inner
                attachScreenshot(name, of: screen)
            }
            app.terminate()
        }
    }
}
```

To run it, replace the build and capture steps in `duo.yml`:

```sh
python3 "$HOME/duo-fold-control/tools/duo-hinge-server.py" --port 8765 &   # needs tools/duo-hinge built next to it
TEST_RUNNER_ANGLES="$ANGLES" TEST_RUNNER_OBJECTS="$OBJECTS" gtimeout 2400 xcodebuild test \
  -project Squish.xcodeproj -scheme SquishDuo -destination "id=$UDID" -derivedDataPath build \
  -resultBundlePath duo.xcresult CODE_SIGNING_ALLOWED=NO
kill %1
xcrun xcresulttool export attachments --path duo.xcresult --output-path duo-screens
```

The `TEST_RUNNER_` prefix forwards the variables into the test process. `duo-hinge-server.py` has no subprocess
timeout, so keep the `gtimeout`. UI tests also need code signing to be allowed for the runner. If
`CODE_SIGNING_ALLOWED=NO` breaks the runner bundle, drop it and use `CODE_SIGN_IDENTITY=-`.

**Appium fallback (not wired).** WebDriverAgent 16.14.0 and later (PR #1287, merged 4 Oct 2026) adds
`POST /wda/device/hingeAngle` (angle 0–180), which the xcuitest-driver exposes as `mobile: setSimulatedHingeAngle`.
It uses the same HID payload as `hinge`, sent from the WDA runner inside the simulator. It does not wait for the
layout transition. Display selection for screenshots and MJPEG uses the `currentDisplayId` setting. It needs
Node, Appium and a WDA build, which adds roughly 10 minutes to a run.

## What the app must do for `duo`

DemoMode's `duo` key must:

- load the object;
- leave `hingeUnavailable()` uncalled, `usesVirtualHinge` untouched and the touch press unscripted;
- not auto-press or reveal.

Real `onHingeChange` events then drive the press, the cover and the reveal. `PressDirector.runDemo` already does
this: it returns early after `load(kind)`.

It must also keep `ignoreInputAfterActivation = 0` and the `SQUISH-T frame` prints. The script waits on `frame 120`.

**Recommended addition.** In demo mode, print a line such as `SQUISH-H <t> <angle> <closed>` from
`hingeUpdate`, throttled to about 10 per second. The script counts these lines per object, which proves that
`onHingeChange` fired and shows the angles the app saw. HingeLog alone does not print anything.

## Cost per run (estimates, not yet measured)

| Phase | No cache | With cache |
|---|---|---|
| Runtime download, 7.85 GB | 6–12 min | – |
| Cache save (first run only) / restore | 5–10 min | 4–8 min |
| Import runtime | 3–5 min | 3–5 min |
| xcodegen and build | 6–10 min | 6–10 min |
| First boot of the Duo (overlaps the build) | 1–10 min | 1–10 min |
| Capture, about 2–2.5 min per object with `hinge` (+1 min with the set-only fallbacks) | ~10 min for 4 objects | ~10 min |
| **Total** | **~35–55 min** | **~25–40 min** |

- macOS runner minutes bill at a much higher rate than Linux minutes. Check the current GitHub pricing.
- The cache entry takes about 7.9 GB of the repo's 10 GB default Actions cache quota and may evict other caches.
- Set `cache_runtime: false` if the cache gives no speedup. Apple's CDN is often about as fast as a restore.

## Known limitations

- **Private APIs.** All three hinge drivers and WDA use undocumented Device Hub, CoreSimulator or CoreDevice
  protocols, verified on Xcode 27.1 and 27.2 with the iOS 27.1 runtime. Any Xcode update can break them. If
  that happens, the probe logs show which driver failed.
- **Runtime split.** Today the iOS 27.1 runtime supports only the Duo, and iOS 27.0 supports everything else.
  Apple is expected to ship a universal 27.2 (runner-images#15000). If the image later preinstalls 27.1, the
  download steps skip themselves.
- **The display switch is path-dependent and not guaranteed.** The script keeps both raw panels, picks the lit
  one and logs a `NOTE` when it differs from the expected panel.
- **Hinge accuracy.** There is no host-side angle readback other than the tools' own reads (`hinge get`
  reads `CMAngleManager`). `devicectl device motion hinge-angle` is rejected on 27.1.
- **Memory.** The Duo simulator is heavy. One report shows an M1 Mac mini swapping hard. The runner logs
  `hw.memsize` for this reason. If the boot or app is killed, cut `objects` per run.
- **No taps.** Taps on the open (inner) display are unreliable through XCUI and accessibility tooling. That
  does not matter here, because demo mode needs no taps.
- **Not yet run.** Nothing here has run on the runner yet. The first run's `logs/run.txt` and `logs/posture.txt`
  will settle the display names and which driver works.

## Sources

- Runner image: https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md
- iOS 27.1 is Duo-only, runtime 24A94425, download command: https://github.com/actions/runner-images/issues/15000
- Runtime size and retry, device type and runtime ids, `primary`/`primary-1` displays: https://blakecrosley.com/blog/xcode-27-1-beta-iphone-duo-simulator
- hinge (README, `skills/hinge/SKILL.md`, `scripts/hinge`, `scripts/hinge_helper.m`): https://github.com/artemnovichkov/hinge
- duo-fold-control (`duo-hinge.m`, `duo-hinge-server.py`, `DuoFold.swift`): https://github.com/tosbaha/duo-fold-control
- foldctl: https://github.com/tatsuz0u/foldctl
- WDA hinge endpoint: https://github.com/appium/WebDriverAgent/pull/1287
- Simulator facts (hysteresis, screenConfig crash, display names): https://github.com/WhitenWhiten/iphone-duo-simulator-skill
- `-downloadPlatform`, `-exportPath`, `-buildVersion`, `-importPlatform`: https://dev.classmethod.jp/en/articles/xcodebuild-ios-simulator-runtime-download-install/
