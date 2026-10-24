# Squish: App Review notes (v1.0, final)

*Final, 23 Oct 2026. Every claim below was checked against the code at `main` (see "Checked against the code"). The block between the markers is mirrored verbatim into `asc-metadata.json` → `review.notes` and pushed by `tools/appstore/asc.swift`. Apple limits this field to 4,000 bytes; the block is plain ASCII, and its size is checked by the same script that validates the JSON.*

## Where this goes
App Store Connect → the version → **App Review Information**:
- **Sign-in required:** off (no accounts). `demoAccountRequired: false`.
- **Contact:** the founder's first name, last name, phone and email (founder-only; `null` in the JSON until filled).
- **Notes:** the block below (pushed by the tool; paste by hand only if the push fails).
- **Attachment (optional, recommended once the founder has filmed it):** a 20-30 s screen recording of one Duo press (close → ka-chunk on the cover → reopen → card). The notes don't depend on it.

<!-- REVIEW-NOTES:BEGIN -->
```
Thanks for reviewing Squish: a paid toy with no ads, no in-app purchases, no accounts, no login and no network requests of its own.

1. TESTING WITHOUT AN iPHONE DUO (start here)
You don't need a Duo. Every object, unlock and achievement works without folding.
- Any iPhone without a hinge, or the Simulator: the drag press is always on. Put a finger on the press and drag down slowly; the ram follows your finger and the object deforms, cracks and gives. Let go to ease off. Drag to the bottom to seal; after a moment the specimen card appears.
- On iPhone Duo: tap the gear key (Settings) on the press console, or Menu > Settings, and turn on "Press without folding". The drag press then works exactly as above.
- With VoiceOver: focus the press and swipe up to press one step, swipe down to ease off.

2. WHAT IT DOES
Squish is a virtual hydraulic press. A virtual object (bubble wrap, rubber duck, egg and so on) sits on the anvil. Pressing crushes it in real time with synthesized sound and haptics. Opening the press reveals a "pressed specimen" card, saved to an on-device shelf.

3. HOW THE HINGE IS USED (iPhone Duo)
Squish reads the hinge only through the public iOS 27.1 API (SwiftUI onHingeChange), behind an availability check. No private API is used.
a) Open the phone in tabletop or book pose. The two halves of the inner screen are the press plates.
b) Close slowly. The press arms where you start closing (between 168 and 130 degrees) and maps the hinge angle continuously to press depth. It seals at 48 degrees (PressConfig.endAngle).
c) Close fully. The normal magnetic close gives a "ka-chunk" and a "Press sealed" card on the outer display.
d) Reopen (past about 120 degrees) to see the specimen card. After a short ceremony, fold again or tap Keep to collect it.
No extra force is needed or encouraged: the user closes the phone exactly as they normally would.

4. UNLOCKS (no hidden features, nothing to buy)
- 6 objects are open from the start.
- Soda Can: press 3 different objects.
- Gummy Bear: press 6 times in total.
- Glass Bottle: earn one "Perfect Squish" (close or drag steadily for 2 seconds or more, without easing off or slamming).
- The 10th object is a secret: it unlocks after pressing the other 9, and it is a steel ball that cracks the press instead. Reaching it takes roughly 10 presses (about 5 minutes).

5. SAFETY (Guidelines 1.4.5 and 2.4.2)
- All objects are virtual and on screen only. Nothing in the app or the store copy suggests placing anything real between the halves.
- On first run the outer display shows: "Squish is on-screen only. Never close your phone on real things." The description repeats it.
- Fast slams are never rewarded: no badge, achievement or bonus. The Perfect Squish trait rewards slow, steady closing, and slams show a gentle "Close it slowly..." hint.
- Rendering pauses while the phone is shut, and effects scale down when the device runs warm.

6. PRIVACY
Squish collects no data. No third-party SDKs, analytics, ads, accounts or tracking, and no network requests of its own. The collection is stored only on the device. Sharing a clip or picture happens only when the user taps Share, through the system share sheet. App Privacy: "Data Not Collected".

7. GAME CENTER
10 optional achievements (700 points), all earned through normal play. None rewards speed or slamming. One ("The Secret") is hidden until earned. No leaderboards. If the player isn't signed in, Squish works fully and keeps achievements to report later.

8. OTHER
- A one-time rating prompt (SKStoreReviewController) may appear after about 10 presses, only after a reveal, never mid-press.
- No notifications are requested.
- Sound plays even when the silent switch is on (playback audio session, mixing with other audio); Settings > "Play when phone is on Silent" turns that off.
- Release builds contain no debug or demo modes.
- Content: cartoon objects only. No creatures, no gore, no brands. The rubber duck is fine.
```
<!-- REVIEW-NOTES:END -->

## Checked against the code

| Claim | Evidence |
|---|---|
| Drag press is automatic without a hinge; "Press without folding" on a Duo | `Squish/UI/SettingsView.swift:87-94` (toggle shown only with a hinge; "Press by dragging · ALWAYS ON" otherwise); `Squish/Shared/Contracts.swift:62-63` |
| Drag gesture, let go to ease off | `Squish/UI/RootView.swift:234-248` (`DragGesture`, `virtualRelease` on end). It is a drag, not a pinch: the old "pinch vertically" line was wrong and is gone |
| Shelf key → gear → Settings | `Squish/UI/PressOverlays.swift:572-574` (Shelf key, "Opens your collection and settings"); `Squish/UI/ShelfView.swift:135-139` (gear, label "Settings") |
| VoiceOver swipe-to-press | `Squish/UI/RootView.swift:216-229`, `:265-283` (adjustable action, 9 steps, step 9 seals) |
| Public hinge API only | `Squish/App/HingeReader.swift` (wraps `onHingeChange`); hinge code behind `#available(iOS 27.1, *)` (CLAUDE.md, Build) |
| Arms 168°-130°, seals at 48°, reveal at 120° | `Squish/Core/PressConfig.swift:8-11` (`armAngleMax` 168, `armAngleMin` 130, `endAngle` 48), `:24` (`revealAngle` 120) |
| "Press sealed" on the cover; first-run safety line | `Squish/UI/CoverView.swift:270`, `:98` |
| Unlock rules | `Squish/Core/ObjectCatalog.swift:64-71` |
| Perfect Squish = no slam, no easing off, ≤ 100°/s, ≥ 2 s | `Squish/Core/PressEngine.swift:532`; `Squish/Core/PressConfig.swift:39-40` |
| Slam hint text | `Squish/App/PressDirector.swift:429` ("Close it slowly… it's more satisfying.") |
| Render pause while shut; thermal scaling | `Squish/Scene/Fold/FoldRenderGate.swift`; `Squish/Scene/Fold/FoldPressController.swift:197`, `Squish/Scene/Kit/Particles.swift:122`, `Squish/Feedback/HapticsController.swift:106` (`thermalState`) |
| No network | see `privacy-labels.md` (grep: no `URLSession`, `URLRequest`, `Network`, web views or SDKs) |
| 10 achievements, 700 points, one hidden | `Squish/Shared/Contracts.swift:168-183`; `achievements.md` |
| Achievements earned signed-out are kept | `Squish/Collection/GameCenter.swift:8` |
| Rating prompt after ≥ 10 presses, after a reveal | `Squish/UI/RootView.swift:422-429` |
| Ambient audio session | `Squish/Feedback/AudioController.swift:38-40` |
| Demo modes compiled out of Release | `Squish/App/DemoMode.swift:125-138` (`DemoScenario.current` is `nil` without `DEBUG`); `Squish/UI/SettingsView.swift:343-354` |

**What changed from the draft, and why:**
- The **no-Duo path now leads** (reviewers may not have a Duo).
- **"Pinch vertically" removed**: the code only has a drag.
- **Angle range corrected**: the press arms between 168° and 130° rather than always at 168°, and it seals at 48°. The checklist's old "60°" note is obsolete.
- **"1,000 points" corrected to 700**: 300 are held back for the holiday update.
- **Perfect Squish timing corrected**: "about 10 seconds" became "2 seconds or more" (`duration >= 2`).
- **The haptics-only-while-visible claim was cut**, because I couldn't find it in the code.
- **The contact line was dropped from the notes**: contact details go in the form's own fields.

**If the founder's real-Duo measurement moves `endAngle`:** change "48 degrees" in block §3b to match, then re-run the push. The tool re-mirrors the block.

## If rejected under 2.4.2 or 1.4.5

Reply in the Resolution Center, calmly and specifically:
> "Squish never asks users to place anything on the device or to use more than a normal close. All objects are rendered on screen. We show an explicit safety line on first run ('Squish is on-screen only. Never close your phone on real things.'), repeat it in the description, and deliberately give no reward for fast closing; the only quality trait rewards slow, gentle closes. We're happy to make the safety line more prominent, for example on the first inner-display screen as well."

Then offer that change in the next build: add the line to the first inner-display frame too.

## If rejected under 2.3.7 (subtitle) or 2.3.1

- **Subtitle:** 1.0 already uses the low-risk "The priciest hydraulic press" (no number, no currency; see `DECISIONS.md`). If even that is flagged, change it to `A hydraulic press for the fold` (29 characters) in the same rejected submission and resubmit. No new build is needed while the version is still in review.
- **"Hidden features" (2.3.1):** point the reviewer to §4. The secret object is reachable in about 5 minutes of normal play, and there's no code, shortcut or purchase.

## Sources

- App Review Guidelines, https://developer.apple.com/app-store/review/guidelines/:
  - 2.4.2 Hardware Compatibility
  - 1.4.5 Physical Harm
  - 2.1(a) App Completeness
  - 2.3.1(a) specific notes and no hidden features
  - 2.3.7 metadata
- App Store Connect Help, *Platform version information*: App Review notes are "up to 4000 bytes". https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Apple, *App privacy details*: data processed only on the device isn't "collected", and data collected by Apple isn't the developer's to disclose. https://developer.apple.com/app-store/app-privacy-details/
