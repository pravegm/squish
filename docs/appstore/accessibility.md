# Squish: Accessibility Nutrition Labels (v1.0)

*Decided 23 Oct 2026 from the code at `main`. Every answer below cites file:line. The rule: claim a label only when the code earns it across the app's **common tasks**, which are:*
- *choose an object;*
- *press it (by fold or by drag);*
- *see the reveal card and collect it;*
- *open the Shelf and a card;*
- *share;*
- *change Settings.*

## The answer, at a glance

| Label | 1.0 answer | Earnable in 1.0.1? |
|---|---|---|
| VoiceOver | **Supported** | — |
| Voice Control | Not supported | Yes, small fix (custom actions on the press) |
| Larger Text | Not supported | Medium fix (reveal card and press overlays at 200%) |
| Dark Interface | Not supported | No: the light studio is the design |
| Differentiate Without Color Alone | Supported (pre-submission fix: graphite outline on the selected chip, `Theme.swift` KeycapFace) | Done |
| Sufficient Contrast | Supported (same fix: the selected-chip outline is graphite on paper, about 13:1) | Done |
| Reduced Motion | **Supported** | — |
| Captions | Not supported (no video or audio-only content) | Not applicable |
| Audio Descriptions | Not supported (no time-based video content) | Not applicable |

**Publish only VoiceOver and Reduced Motion for iPhone**, and leave every other box unticked.

**Timing:**
- Apple only lets you publish labels for a device that has a **live version**, so this happens **on launch day, Tue 24 Nov**. The step is in `SUBMISSION.md` §8.
- Labels are voluntary for now. The product page shows "hasn't indicated support yet" until we publish.
- Before publishing, do one pass through the common tasks with VoiceOver on, and one with Reduce Motion on, on the release build, on both a Duo and a non-Duo iPhone. This pass confirms the answers below; it doesn't widen them.

## Label by label

### VoiceOver: Supported

Apple's bar is that users can complete all common tasks using only VoiceOver. The code covers each one:

- **Press without seeing it.** The press stage is one element with a label, a live value and a hint, plus an adjustable action: swipe up to press a step, swipe down to ease off. There are 9 steps, and step 9 seals.
  - Label, value and hint: `Squish/UI/RootView.swift:216-221`.
  - Adjustable action: `RootView.swift:222-229`, stepping logic `:265-283`.
  - The live value reads "Ready / Approaching / Touching / n percent squished / Sealed" (`RootView.swift:251-262`).
  - On a Duo, the hint says to fold, and folding needs no touch at all.
- **Announcements:**
  - the object as it's placed (`Squish/App/PressDirector.swift:318-319`, with copy from `Squish/Core/ObjectCatalog.swift:78-91`);
  - big moments (`PressDirector.swift:345-346`) and coach lines (`:431-432`);
  - tips (`Squish/UI/TipCenter.swift:58-59`);
  - the reveal (`Squish/UI/RevealCardView.swift:433-438`);
  - a screen-change notification when the reveal appears (`RootView.swift:454`).
- **Reveal card:**
  - The whole card is one sentence: number, object, where it gave, tonnage, breaks, time, traits and flavour (`RevealCardView.swift:183-185`, sentence built in `Squish/Collection/AchievementInfo.swift:114-134`).
  - The actions have hints, and focus moves to Next (`RevealCardView.swift:203, 224-225, 311, 325, 334-335`).
- **Object picker and console:**
  - "Object: …" with a hint (`Squish/UI/PressOverlays.swift:499-500`).
  - The Shelf key has a value, "n of 10 objects pressed" (`PressOverlays.swift:572-574`).
  - Decorative machine art is hidden (`PressOverlays.swift:49, 181, 263, 359`).
- **Shelf:** about 28 accessibility modifiers, including:
  - the totals (`Squish/UI/ShelfView.swift:126`);
  - Settings and Close (`:139, :147`);
  - "See all" (`:713`);
  - rows combined into one element each (`:646`).
- **Settings:**
  - headers (`Squish/UI/SettingsView.swift:35, 214`);
  - a labelled close button (`:49`);
  - chip choices with label and selected trait (`:303-304`);
  - rows combined (`:283`);
  - the Tuning Lab reachable through a named action instead of a long-press (`:158`).
- **Cover display:**
  - the sealed card is one sentence (`Squish/UI/CoverView.swift:269-270`);
  - the shelf summary (`:460-461`);
  - picker chips with label, selected trait and hint (`:496-498`).

### Voice Control: Not supported

- **Why not:**
  - On iPhones without a hinge, the core task (pressing) is a **drag only** (`RootView.swift:234-248`).
  - The step-by-step alternative is an `accessibilityAdjustableAction` (`RootView.swift:222`). That is a VoiceOver gesture, and Voice Control has no command that reaches it.
  - The press has no `accessibilityCustomActions` and there are no `accessibilityInputLabels` anywhere (grep: 0).
  - On a Duo the fold works hands-free, but the label is per device (iPhone), and most iPhones don't fold.
  - Apple's criteria require gestures to have custom actions or speech alternatives.
- **1.0.1 fix (S):**
  - Add `.accessibilityAction(named: "Press")` and `.accessibilityAction(named: "Ease off")` to the stage in `RootView.swift`, reusing `adjustAccessiblePress(by: ±1)`.
  - Add `.accessibilityInputLabels(["Press", "Squish"])` to the stage.
  - Check that every icon-only key exposes a name that can be spoken. For example, the gear is "Settings" (`ShelfView.swift:139`) and the close key is "Close settings" (`SettingsView.swift:49`), which are already fine.
  - Then test with Voice Control's "Show names" and "Show numbers".

### Larger Text: Not supported

- **Why not:** Apple needs text to reach at least 200% (about the AX3 size) in common tasks without truncation or overlap.
- **What already works:**
  - The fonts are Dynamic Type text styles (`Squish/UI/Theme.swift:104-116`).
  - The Shelf and Settings sheets go to AX3 (`Theme.swift:333-335`, applied at `ShelfView.swift:91, 102` and `RootView.swift:376`).
  - The Shelf switches to one column at accessibility sizes (`ShelfView.swift:54, 69`).
- **What stops at about 135% or lower:**
  - The press overlays are capped at `.large`, i.e. no growth (`PressOverlays.swift:219`, "painted on the machine"), and at `.xxxLarge` (`PressOverlays.swift:433`).
  - The reveal card's actions are capped at `.xxLarge` (`RevealCardView.swift:227`), and its other block at `.xxxLarge` (`:338`).
  - The specimen card itself is capped at `.xLarge` in the reveal (`Squish/UI/SpecimenCardView.swift:53`).
  - The cover is capped at AX2 (`CoverView.swift:50`).
  - The card art uses fixed 7–20 pt type: the stamp (`Theme.swift:580`) and the Perfect seal (`Theme.swift:620`).
- **1.0.1+ fix (M):**
  - Let the reveal card's data lines and buttons scale to AX3, reflowing the card into a scroll view at accessibility sizes.
  - Lift the overlay caps on the press console's text labels, not the painted machine art.
  - Then test at AX3 on a 6.1" phone and on the Duo outer display.

### Dark Interface: Not supported (by design)

- **Why not:**
  - The app forces the light appearance (`project.yml:34`, `UIUserInterfaceStyle: Light`, "the studio stays bright in Dark Mode").
  - The UI is off-white paper (`Theme.swift:9-11`).
  - Apple's criterion is "dark by default for all common tasks".
- **Plan:** none. The bright studio is part of the product. Revisit only if users ask.

### Differentiate Without Color Alone: Supported (fixed before submission)

- **Why not:**
  - A selected chip is shown **only by colour**: soft-yellow face and yellow lip vs paper (`Theme.swift:499, 507`).
  - This covers Sound style and Haptics in Settings (`SettingsView.swift:65, 80`), and every other `ChipChoice` and selected chip.
  - VoiceOver hears "selected" (`SettingsView.swift:304`), but sighted users who can't separate the colours get no other cue.
  - Nothing reads `accessibilityDifferentiateWithoutColor` (grep: 0).
- **Already fine elsewhere:**
  - Traits are text plus a symbol (GOLDEN with a crown, PERFECT SQUISH with sparkles: `AchievementInfo.swift:101-110`).
  - The bezel lamps are labelled READY / LOAD (`Squish/Scene/Fold/FoldBezel.swift:87-88`).
- **1.0.1 fix (S), in `KeycapStyle` (`Theme.swift`):** give the selected chip a leading checkmark glyph and a 1.5 pt graphite border, always or at least when `accessibilityDifferentiateWithoutColor` is on. Check under the Grayscale colour filter.

### Sufficient Contrast: Supported (fixed before submission)

- **Text passes.** Contrast ratios, computed from the `Theme` hex values:

  | Text | Background | Ratio |
  |---|---|---|
  | ink | paper | 13.0:1 |
  | ink | paperWarm | 11.75:1 |
  | inkSecondary | paperWarm | 5.35:1 (7.31:1 under Increase Contrast, `Theme.swift:18`) |
  | inkSecondary | backdrop | 5.44:1 |
  | stamp red | paper | 4.68:1 |
  | ink | yellow keys | 7.96:1 |

  `inkTertiary` (3.39:1) is used only for a chevron glyph (`ShelfView.swift:641`), which meets the 3:1 rule for non-text.
- **Why not:** the **selected-chip state indicator** is 1.18:1 (face, `#FFE3A1` vs `#FBF8F1`) and 1.89:1 (lip) against the unselected chip. Apple's bar for state indicators is 3:1.
  - Increase Contrast adds a border to every key (`Theme.swift:454-456`), but it doesn't separate selected from unselected.
- **1.0.1 fix:** the same chip fix as Differentiate Without Color. A graphite border on the selected chip is about 13:1. Then re-test with Bold Text, Increase Contrast and Reduce Transparency on.

### Reduced Motion: Supported

The press follows the user's own hand, so that movement is the content and isn't decoration. Everything added on top of it is cut or calmed when Reduce Motion is on:
- **Press scene:**
  - no slow motion (`Squish/Scene/PressScene.swift:266`);
  - no camera kick on failure (`PressScene.swift:322-327`);
  - the failure light flash drops from 30,000 to 8,000 (`Squish/Scene/SceneStyle.swift:48-49`);
  - no drop-in bounce (`PressScene.swift:638`);
  - no idle wave (`:748`);
  - no gauge tremor, buzz or panic (`:783-789`);
  - no Unsquishable wobble (`:795`);
  - no swinging seal tag (`Squish/Scene/Rig/PressRig.swift:355`);
  - no candle flicker (`Squish/Scene/Objects/CakeSliceView.swift:238`).
- **Debris and particles:** motion is scaled to 25% (`Squish/Scene/Kit/Particles.swift:363`).
- **Fold Press:**
  - the spray lands without stagger or pop (`Squish/Scene/Fold/FoldAnvil.swift:181, 211, 229`);
  - the print effects land instantly (`Squish/Scene/Fold/FoldPlaten.swift:139, 160, 239, 286, 301, 844`);
  - the bezel is calmed (`FoldBezel.swift:351`).
- **UI:**
  - no key-press spring (`Theme.swift:466`);
  - no row stagger or slide-in in sheets (`SettingsView.swift:224-225`, `ShelfView.swift:647-648`).
- The app follows the system setting and shows its state in Settings (`SettingsView.swift:98-99`).

### Captions: Not supported (not applicable)

- **Why not:** Apple's Captions label covers dialogue and relevant sounds in **video or audio-only content**. Squish has no dialogue and no video or audio content to caption.
  - The reveal replay is a re-run of the user's own press.
  - The share clip is exported, not played back in the app.
  - Apple says not to claim support if there's "very little or no captioned content".
- **What we do have**, which is honestly described in the store copy as "Captions" (not as this label):
  - a Captions setting that shows comic words for sound moments ("POP!", "CRACK!") (`Squish/Shared/Contracts.swift:60-61`, `SettingsView.swift:84-85`);
  - it switches on automatically when the system's closed-captions preference is on (`PressDirector.swift:69`).

### Audio Descriptions: Not supported (not applicable)

- **Why not:** there are no cut scenes, trailers or other time-based visual content in the app. Leave it unticked.

## 1.0.1 list to earn more labels honestly

| Fix | Size | Earns | Where |
|---|---|---|---|
| Checkmark + graphite border on the selected chip | S | Differentiate Without Color Alone, Sufficient Contrast | `Squish/UI/Theme.swift` (`KeycapStyle`) |
| "Press" / "Ease off" custom actions + input labels on the press stage | S | Voice Control | `Squish/UI/RootView.swift` stage |
| Reveal card and console labels to AX3 with reflow | M | Larger Text | `RevealCardView.swift`, `SpecimenCardView.swift`, `PressOverlays.swift` |

Re-evaluate the labels with every update: add a label only after the fix is on device and tested.

## Sources

- App Store Connect Help, *Overview of Accessibility Nutrition Labels*: the nine labels, common tasks, "voluntary to start". https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- App Store Connect Help, *Manage Accessibility Nutrition Labels*: per-device answers; you can only publish for devices with a live version. https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels
- Per-label evaluation criteria (linked from the overview):
  - Larger Text: 200% or the system maximum.
  - Sufficient Contrast: usually 4.5:1 for text, 3:1 for controls and state.
  - Dark Interface: "dark by default".
  - Reduced Motion: no parallax or multi-axis effects; meaningful animation may become a fade.
  - Captions and Audio Descriptions: time-based content.
  - Voice Control: names, numbers and gesture alternatives.

## Update (23 Oct 2026, before submission)

The chip fix was made before 1.0 rather than in 1.0.1. A selected chip now always carries a 2 pt graphite outline: tabs, sound style, haptics level, and the object on the anvil.
- The outline is about 13:1 against the paper face, and the chip reports the `.isSelected` trait to VoiceOver. See the `KeycapFace` body in `Squish/UI/Theme.swift`.
- **Labels this earns:** Differentiate Without Color Alone and Sufficient Contrast join VoiceOver and Reduced Motion.
- **Before publishing the labels on launch day,** check the Settings frame once under the Grayscale colour filter.
