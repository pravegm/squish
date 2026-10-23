# Squish: Launch checklist (status 23 Oct 2026 → January drop)

*Release: **Tue 24 Nov 2026, 08:00 UTC**, scheduled, no pre-order (`DECISIONS.md` #4–5). Every item has one of three tags, with the reason:*
- ✅ **Done (Claude)**: finished and committed.
- ⚙️ **Automated (tool)**: `tools/appstore/asc.swift push` does it from `asc-metadata.json`, and someone just runs it.
- 👤 **Founder-only**: needs your legal identity, your Apple login, your hardware or your public voice.

*Clicks and exact answers: `SUBMISSION.md`.*

## Decisions and copy

| Item | Status | Note |
|---|---|---|
| Subtitle (£/$ joke vs fallback) | ✅ Done (Claude) | "The priciest hydraulic press". The 2.3.7 risk isn't worth a review cycle |
| Keywords, categories, price, territories, age rating | ✅ Done (Claude) | `DECISIONS.md` #2–9 |
| Release date and type; pre-orders | ✅ Done (Claude) | 24 Nov 08:00 UTC, scheduled; no pre-order |
| Description and promo text, checked against the code | ✅ Done (Claude) | `metadata.md` / `asc-metadata.json` |
| App Review notes, with θ_end = 48° (`PressConfig.endAngle`) | ✅ Done (Claude) | `review-notes.md`. Claude updates the angle if the real-Duo tuning moves it |
| App Privacy answers | ✅ Done (Claude) | Data Not Collected; grep evidence in `privacy-labels.md` |
| Accessibility Nutrition Label answers | ✅ Done (Claude) | VoiceOver + Reduced Motion only (`accessibility.md`) |
| Achievement copy and IDs checked against the code | ✅ Done (Claude) | `achievements.md`; 700 points |
| Screenshot frames and captions sign-off (19 frames, run 39952047687) | ✅ Done (Claude) | `DECISIONS.md` §4 |
| Frame 1 photo vs render | ✅ Done (Claude) | Render in 1.0; real-Duo photo in 1.0.1 |
| App Preview decision | ✅ Done (Claude) | Optional 6.9" preview, only if delivered by Mon 9 Nov |
| Duo App Store slots research | ✅ Done (Claude) | No API type exists; upload by hand in the web UI if the slot shows (`DECISIONS.md` §3) |
| Featuring nomination 1 text | ✅ Done (Claude) | `featuring-nomination.md`, `SUBMISSION.md` §9 |
| Domain with /privacy, /support, /press | ✅ Done (Claude) | GitHub Pages at https://pravegm.github.io/squish/, so no custom domain is needed. The pages are in `site/` (commit `34470db`). On 23 Oct the landing page, /support/ and /privacy/ all returned HTTP 200. Re-check before the push: Apple rejects a support URL that doesn't load |

## Before submission (by Wed 11 Nov; hard cut Mon 16 Nov)

| By | Item | Status | Reason / where |
|---|---|---|---|
| **Thu 29 Oct** | Register the bundle ID, create the app record, enable Game Center | 👤 Founder-only | Apple login (`SUBMISSION.md` §1) |
| **Thu 29 Oct** | Paid Apps agreement, tax, banking | 👤 Founder-only | Legal identity (§2) |
| **Thu 29 Oct** | Small Business Program enrolment | 👤 Founder-only | Account Holder only. Enrolling in October covers launch (§2) |
| **Thu 29 Oct** | EU Digital Services Act trader declaration, or untick the EU | 👤 Founder-only | Your public contact details (§2) |
| **Thu 29 Oct** | App Store Connect API key for the tool | 👤 Founder-only | Apple login (§3) |
| Fri 23 – Sun 25 Oct | Film and post the 15 s teaser; email the tip lines | 👤 Founder-only | Your hands, your accounts (`preview-video.md` §B, `press-kit.md`) |
| **Tue 3 Nov** | **Submit featuring nomination 1** | 👤 Founder-only | Apple login. Text final (`SUBMISSION.md` §9) |
| 23 Oct – 6 Nov | Real-Duo first-hour checks + Tuning Lab hinge log and config JSON to Claude | 👤 Founder-only | Only you have the hardware (`docs/HANDOVER.md` §3) |
| By Fri 6 Nov | First archive and upload; TestFlight internal and external | 👤 Founder-only | Signing needs your team (`SUBMISSION.md` §5–6) |
| Release candidate | Name, subtitle, description, keywords, promo text, URLs (en-GB, en-US) | ⚙️ Automated (tool) | `asc.swift push` |
| Release candidate | Categories, age rating, review notes, scheduled release, price | ⚙️ Automated (tool) | `asc.swift push` |
| Release candidate | 10 Game Center achievements + images | ⚙️ Automated (tool) | `asc.swift push` (images from `tools/appstore/badges.swift`) |
| Release candidate | 6.9" and 6.1" screenshot sets (P1–P5 each) | ⚙️ Automated (tool) | `asc.swift push` from run 39952047687's artifacts |
| Release candidate | 6.9" App Preview (if delivered by 9 Nov) | ⚙️ Automated (tool) | `asc.swift push` (`IPHONE_67`) |
| Release candidate | Copyright line + review contact | 👤 Founder-only | Your legal name and contact details; given to the tool locally, never committed |
| Release candidate | App Privacy "Data Not Collected" → Publish | 👤 Founder-only | Web UI only; answers in `privacy-labels.md` |
| Release candidate | Availability (all but China mainland), Family Sharing on, Content Rights = No | 👤 Founder-only | Web UI only (`SUBMISSION.md` §4b) |
| Release candidate | Add the 10 achievements to the 1.0 version; select the build | 👤 Founder-only | Web UI (`SUBMISSION.md` §4b.4) |
| Release candidate | iPhone Duo inner and outer screenshots, if the slot exists | 👤 Founder-only | The API has no Duo type, so it's a web upload (`SUBMISSION.md` §4b.4) |
| Release candidate | Look once at P5 (6.9" and 6.1") after upload | 👤 Founder-only | Its new caption hasn't been looked at yet (`DECISIONS.md` §4) |
| **Wed 11 Nov** | **Submit 1.0 for review** | 👤 Founder-only | Apple login (`SUBMISSION.md` §7) |
| Wed 18 Nov | Generate promo codes, line up creator emails | 👤 Founder-only | Your accounts |
| **Thu 19 Nov** | Submit featuring nomination 2 (Holiday, New Content) | 👤 Founder-only | Apple login (`featuring-nomination.md`) |

### Handed to engineering (Claude). These must land on `main` and pass CI before the release-candidate archive

| Item | Status | Reason |
|---|---|---|
| `NSPhotoLibraryAddUsageDescription` in `project.yml` | Open, handed over | Share → Save Image/Video would otherwise crash (`DECISIONS.md` §6 #1) |
| `MARKETING_VERSION` 0.1.0 → 1.0 | Open, handed over | The upload must be 1.0 |
| Settings credits line (no Sonniss/Freesound) | Open, handed over | It is false; all sound is synthesised |
| Tuned defaults from the founder's Duo log | Waiting on the founder's data | `docs/HANDOVER.md` §3 |
| Toast verify run (FOLD-REVIEW-9 N8) | ✅ Done (Claude) | Seen in `verify/duo-reveal-toast-app.png` |

## Launch day: Tue 24 Nov

| Item | Status | Reason |
|---|---|---|
| App goes live at 08:00 UTC | ⚙️ Automated (Apple) | Scheduled release |
| Check the UK and US product pages | 👤 Founder-only | Needs a store account and a person to look |
| Publish the Accessibility labels (VoiceOver, Reduced Motion) | 👤 Founder-only | Apple only allows it once 1.0 is live (`SUBMISSION.md` §8) |
| Launch posts (X, Bluesky, Mastodon, r/iPhoneDuo), a note to the journalists, ask FoldHunt to update | 👤 Founder-only | Your public voice (`social-launch.md`) |
| Watch crashes and reviews; prepare 1.0.1 (submit by Fri 27 Nov) | ✅ Planned (Claude) | Frame-1 photo, Duo sets if missed, accessibility fixes, FOLD-REVIEW-9 §4 |

## Holiday drop (Wed 25 Nov – Sun 3 Jan)

| Date | Item | Status |
|---|---|---|
| Thu 26 Nov | Create In-App Event 1 (copy final in `featuring-nomination.md`); promotion starts | 👤 Founder-only (Apple login) |
| **Tue 1 Dec** | Submit 1.1 (holiday objects + achievements from the reserved 300 points) | 👤 Founder-only to submit; Claude builds it |
| Fri 4 Dec | Promo text → drop version | ⚙️ Automated (tool), once the JSON is updated |
| Thu 10 Dec | 1.1 live, event starts; post the clips | 👤 Founder-only (public posts) |
| Fri 18 Dec | Featuring nomination 3 (January drop) | 👤 Founder-only (Apple login) |
| 23–27 Dec | App Store Connect holiday slowdown: **submit nothing** | — |

## January backorder-wave drop

| Date | Item | Status |
|---|---|---|
| Mon 4 Jan | Create In-App Event 2; promotion starts | 👤 Founder-only |
| **Fri 8 Jan** | Submit 1.2 | 👤 Founder-only to submit; Claude builds it |
| Mon 18 Jan | 1.2 live; £1.99 one-week sale (promo text and social only, never in event metadata) | 👤 Founder-only (price change = Apple login) |
| Mon 25 Jan | End the sale; review Search data; maybe swap keywords (`metadata.md` §5) | 👤 Founder-only for the price; ⚙️ tool for the keywords |

## Always-on checks before every submission

- [ ] Nothing in the metadata, screenshots or preview shows real objects between the halves, prices, Hydraulic Press Channel references or "anger" language.
- [ ] The privacy label is still accurate: re-run the grep in `privacy-labels.md`.
- [ ] Every accessibility claim in the description, and every published label, is still true (`accessibility.md`).
- [ ] The review notes match the build: unlock rules, Settings labels, angles (`review-notes.md`, "Checked against the code").
- [ ] Screenshots, previews and the subtitle can change **only with a new version**. Promo text can change any time.

## Sources

- App Store Connect Help, *Publish for pre-order*: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order
- App Store Connect Help, *Nominate your app for featuring*: "a minimum lead time of 3 weeks". https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring
- Apple Developer, *In-App Events*: promote up to 14 days ahead; events last up to 31 days. https://developer.apple.com/app-store/in-app-events/
- App Store Connect Help, *Manage Accessibility Nutrition Labels*: publishing needs a live version. https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels
- Research 06 §7: holiday shutdown about 23–27 Dec; January backorders.
