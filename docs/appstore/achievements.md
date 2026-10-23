# Squish: Game Center achievements (v1.0)

*From bible §11 and research 04 §D. All are earned through normal play, and **all work with the drag press (the P-48 on non-folding iPhones, and Settings → Press without folding on iPhone Duo)**. Final copy, 23 Oct 2026; `asc-metadata.json` mirrors it. None rewards speed, slamming, streaks or daily play.*

## Rules

- **Apple limits:**
  - ≤ 100 points per achievement
  - ≤ 1,000 points in total per app
  - ≤ 100 achievements
  - Achievement ID ≤ 100 characters, alphanumeric plus `.` and `_`, and **permanent once created**
  - Each achievement needs a 1024 × 1024 RGB image (`.png`/`.jpg`, ≥ 72 ppi)
- **Launch total: 700 points.** That holds **300 points back** for future drops (Holiday, January and later) without ever hitting the 1,000 cap.
- **Achievable more than once:** No, for all ten.
- **Hidden:** only **The Secret**. Hidden achievements stay invisible in Game Center until earned.
- **Leaderboards:** none (bible §11: "never leaderboards").
- **Art:** each image is a mini pressed-specimen card on paper with a red PRESSED stamp, in the same style as the in-app cards. The Secret's image is a dented press plate.

## The ten

| # | Achievement ID | Title (Display Name) | Pre-earned description | Earned description | Points | Hidden | Trigger (for dev) |
|---|---|---|---|---|---|---|---|
| 1 | `com.pravegm.squish.ach.first_squish` | First Squish | Press your first object. | Pressed. Filed. Ka-chunk. | 25 | No | First completed press that reaches the reveal |
| 2 | `com.pravegm.squish.ach.pop_star` | Pop Star | Pop 500 bubbles. | 500 bubbles, and not one survivor. | 75 | No | Cumulative bubbles popped across all Bubble Wrap presses ≥ 500 |
| 3 | `com.pravegm.squish.ach.whats_inside` | What's Inside? | Find two different surprises hidden inside objects. | Found things in there. Didn't ask questions. | 75 | No | Two **different** surprises found, lifetime (`stats.surprisesFound.count >= 2`, CollectionStore.swift:255). Surprises: the seeded roll fires (toy chick, jam centre, second crayon colour, fruit pieces, rainbow layers, message confetti, mega bubble, double yolk) |
| 4 | `com.pravegm.squish.ach.patience` | Patience | Keep one press going for more than 30 seconds. | 30 seconds of pure restraint. | 50 | No | Time from arm (θ0 captured) to seal > 30 s, **excluding** time Paused, and **with continuous engagement**: depth must change at least once every 10 s, so leaving the phone half-open doesn't count |
| 5 | `com.pravegm.squish.ach.pumped` | Pumped | Ease off and press again, twice, in one squish. | Up, down, up, down. Very hydraulic. | 50 | No | One press with ≥ 2 Pressing → Armed (reopen) transitions before seal (bible §2: the plastic ratchet enables "pumping") |
| 6 | `com.pravegm.squish.ach.perfectionist` | Perfectionist | Earn a Perfect Squish on 5 different objects. | Five objects, five flawless closes. | 100 | No | Distinct objects whose best card has the Perfect trait ≥ 5 |
| 7 | `com.pravegm.squish.ach.steady_hands` | Steady Hands | Earn 10 Perfect Squishes. | Ten Perfect Squishes. Surgeons are nervous. | 75 | No | Lifetime Perfect Squish count ≥ 10 (any objects, repeats count) |
| 8 | `com.pravegm.squish.ach.midas` | Midas | Press a Golden object. | Golden. One in fifty, and it was yours. | 100 | No | First Golden variant (1/50 seeded roll) |
| 9 | `com.pravegm.squish.ach.collector` | Collector | Press all ten objects. | Ten objects, ten specimens. The shelf is full. | 100 | No | All 10 Shelf slots hold at least one card, **including the secret** |
| 10 | `com.pravegm.squish.ach.the_secret` | The Secret | Some things don't squish. | PRESS 0 – BALL 1. | 50 | **Yes** | First press of The Unsquishable (the press-cracks reveal completes) |
| | | | | | **700** | | |

**Check the ladder:**
- Achievement 1 lands on the first press; 3 usually within the first session or two (cake 1 in 3, jelly 1 in 4).
- Most players will hit Patience (if they're slow), Pumped and Perfectionist in the first session or two.
- Pop Star takes about 21 bubble-wrap presses (24 bubbles a sheet, `ObjectCatalog.swift:80`).
- Midas is luck: expected after ~50 presses.
- Collector and The Secret come together.

## Copy notes

- Titles stay short for the Game Center layout. Count them in the App Store Connect form when entering them; Apple's help page doesn't state field limits.
- "PRESS 0 – BALL 1" uses an en dash, matching the in-app card. If the form rejects it, use a hyphen.
- The Secret's pre-earned description is a tease that's safe even if hidden achievements are ever shown greyed out.
- Nothing mentions speed, and nothing mentions "slam", "smash" or "rage".

## Reserved for future drops (300 points)

| Planned ID | Title | Pre-earned | Points |
|---|---|---|---|
| `com.pravegm.squish.ach.cracker_pulled` | Bang! | Press the Christmas Cracker. | 25 |
| `com.pravegm.squish.ach.winter_set` | Winter Specimens | Press every holiday object. | 50 |
| `com.pravegm.squish.ach.new_year` | Fresh Start | Press every January object. | 50 |
| *(175 points held back)* | | | |

## Implementation checklist (dev)

- [x] Machine-readable copy for App Store Connect: `asc-metadata.json` → `achievements` (IDs verified against `Achievement.gameCenterID` in `Squish/Shared/Contracts.swift:173-182`, 23 Oct 2026; art from `tools/appstore/badges.swift`, which re-checks the IDs).
- [ ] Created in App Store Connect → Game Center by `tools/appstore/asc.swift push` (or by hand from this table) **before** the build that reports them, then added to the 1.0 version (`SUBMISSION.md` §4). IDs are permanent.
- [ ] Localisation: English (UK) and English (US) are identical for v1.0.
- [ ] Report progress with `GKAchievement.percentComplete` for Pop Star (bubbles / 500), Steady Hands (n / 10), Perfectionist (n / 5) and Collector (n / 10).
- [ ] Never present the Game Center sign-in sheet repeatedly. Authenticate once at launch, and if the player declines, stay silent.
- [ ] Pinch Press and Press without folding must be able to trigger every achievement (accessibility promise in the description and the nomination).
- [ ] Achievement banners are deferred until **after** the reveal, never mid-press.

## Sources

- App Store Connect Help, *Achievements* (Achievement ID ≤ 100 characters and permanent; ≤ 100 points each and ≤ 1,000 total; hidden; achievable more than once; Display Name and pre-earned/earned descriptions; image 1024 × 1024, RGB, ≥ 72 ppi): https://developer.apple.com/help/app-store-connect/reference/game-center/achievements
- Apple Developer, *Rewarding players with achievements* (≤ 100 achievements; point caps): https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements
- Bible §2 (no slam rewards; pumping), §4 (surprises, Golden 1/50), §11 (achievement list)
