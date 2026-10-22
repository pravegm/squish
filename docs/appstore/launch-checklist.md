# Squish: Launch checklist (22 Oct 2026 → January drop)

*Release target: **Tue 24 Nov 2026**, the Tuesday before US Thanksgiving (26 Nov). The fallback is Fri 20 Nov. Each line is owned by either the **Founder** (F) or the **Dev** (D). The founder posts everything public by hand.*

Key Apple deadlines this plan is built around:
- Featuring nominations go in **≥ 3 weeks before launch**, so by **Tue 3 Nov**.
- Pre-orders need an approved build, and the release date must be 2–180 days out.
- In-App Events can be promoted **up to 14 days** before they start and run **≤ 31 days**.
- The App Store Connect holiday slowdown runs around 23–27 Dec.

---

## Week 0: Claim the idea (Thu 22 Oct – Mon 26 Oct)

| Date | Founder does | Dev does |
|---|---|---|
| **Thu 22 Oct** | [ ] Reserve **"Squish: Fold-to-Crush Press"** in App Store Connect (new app record, bundle ID `com.pravegm.squish`). If the name is taken, fall back to "Hingepress" (bible §12) and tell dev<br>[ ] Enrol in the Small Business Program<br>[ ] Register the domain and stand up a one-page site with `/privacy`, `/support` and `/press` (copy from `privacy-policy.md`, `support.md`, `press-kit.md`) | [ ] Add the `-squishDemo` keys requested in `screenshots.md` (`seed`, `t`/`freeze`, `collection`) to the backlog<br>[ ] Make sure the demo argument is compiled out of Release, or ignored in it |
| **Fri 23 Oct** (Duo on sale) | [ ] Get the Duo in hand<br>[ ] Film the 15 s teaser (`preview-video.md` §B), or the Simulator variant if the hardware is late | [ ] Hinge Lab build on the founder's Duo (bible §13 Week 0)<br>[ ] Teaser capture build: egg press + cover card |
| **Sat 24 Oct** | [ ] Post the teaser on X, Bluesky and Mastodon (`social-launch.md` Phase 1)<br>[ ] Read the r/iPhoneDuo rules, then make the teaser post if allowed | — |
| **Sun 25 Oct** | [ ] Email the **tip lines** (TechCrunch, MacRumors, 9to5Mac) with the clip (`press-kit.md` email 1)<br>[ ] Email FoldHunt asking to be listed | — |
| **Mon 26 Oct** | [ ] Start a TestFlight tester list from Reddit and X replies (target 30 Duo owners)<br>[ ] **Draft featuring nomination 1** in App Store Connect (`featuring-nomination.md`) | [ ] Week 0 report: display-off angle, hinge sample rate, haptic map. **Update θ_end in `review-notes.md` if it's not 60°** |

## Week 1: Core feel (Tue 27 Oct – Mon 2 Nov)

| Date | Founder does | Dev does |
|---|---|---|
| Tue 27 Oct | [ ] Pick the release date (24 Nov recommended) | [ ] Bubble Wrap + Rubber Duck end-to-end; Pinch Press fallback |
| Wed 28 Oct | [ ] "Object of the day" pre-launch clip #1 (Bubble Wrap). Post every 2 days from here | — |
| Fri 30 Oct | [ ] Press page live with placeholder assets<br>[ ] Find Vikhyaat Vivek's contact details (Digital Trends) | [ ] Build the share-clip renderer early (it produces all the marketing footage) |
| Sun 1 Nov | [ ] Decide on the £/$ subtitle vs the fallback (`metadata.md` §2) | — |
| **Mon 2 Nov** | [ ] **Submit featuring nomination 1 (App Launch)**. The deadline is Tue 3 Nov | [ ] TestFlight build 1 (internal) |

## Week 2: Materials and pre-order (Tue 3 Nov – Mon 9 Nov)

| Date | Founder does | Dev does |
|---|---|---|
| Tue 3 Nov | [ ] Fill in the age rating questionnaire (`metadata.md` §8), App Privacy "Data Not Collected", categories, price, Family Sharing on | [ ] Egg, Crayon, Jelly, Cake, Glass in build |
| Wed 4 Nov | [ ] Paste the description, keywords and promo text<br>[ ] Placeholder screenshots (6.9" set from the current build) | [ ] **Pre-order build**: final-quality and stable (Guideline 2.1 applies to pre-orders) |
| **Thu 5 Nov** | [ ] **Submit the pre-order build** with `review-notes.md` + a screen-recording attachment<br>[ ] Set the release date to 24 Nov | [ ] Create the 10 Game Center achievements (`achievements.md`) in App Store Connect before this build |
| Fri 6 Nov | [ ] External TestFlight to Duo owners (public link) | [ ] Fix TestFlight crash reports |
| Sat 7 Nov | [ ] **Pre-order live** (if approved): post Phase 2 copy<br>[ ] Edit the Reddit post. Send the pre-order link to the tip lines as a one-line follow-up | — |
| Mon 9 Nov | [ ] Collect tester quotes (with permission) for the press kit | — |

## Week 3: Product (Tue 10 Nov – Mon 16 Nov)

| Date | Founder does | Dev does |
|---|---|---|
| Tue 10 Nov | [ ] Pitch PocketGamer and TouchArcade (`press-kit.md` email 3) with the pre-order link + TestFlight | [ ] Soda Can, Gummy Bear, The Unsquishable |
| Wed 11 Nov | [ ] Pitch Digital Trends (email 2)<br>[ ] Shortlist 20–30 Duo creators | [ ] Cover display: sealed card + trophy shelf |
| Fri 13 Nov | [ ] Listening + feel session on the latest build (bible §8 protocol) | [ ] Shelf, Card detail, Settings; unlocks; Game Center reporting |
| Mon 16 Nov | [ ] Approve the caption wording for all screenshot frames | [ ] Accessibility pass: VoiceOver labels, Reduce Motion, visual sound cues. **Report anything that won't make 1.0 so the copy can be cut** |

## Week 4: Ship (Tue 17 Nov – Tue 24 Nov)

| Date | Founder does | Dev does |
|---|---|---|
| Tue 17 Nov | [ ] Perform the hero presses on the Duo for the preview (5 takes per object) | [ ] **Capture all screenshots** with the demo args: Duo inner 2007 × 2853 ×6, outer 1398 × 2034 ×2, 6.9" 1320 × 2868 ×6, 6.5" 1284 × 2778 ×6. Export PNG with no alpha |
| Wed 18 Nov | [ ] Sign off on screenshots (checklist in `screenshots.md`) | [ ] Render the App Preview (886 × 1920, 30 fps, 30 s), the 6.9" variant, the trailer and the b-roll |
| **Thu 19 Nov** | [ ] **Submit the 1.0 release build** + screenshots + preview, poster frame at 00:08.0<br>[ ] **Submit featuring nomination 2 (Holiday, New Content)** | [ ] Final checks: 20-press repetition test per object, thermal, silent mode, interruptions. Loudness −16 LUFS |
| Fri 20 Nov | [ ] Press kit zip final<br>[ ] Line up creator emails (sent after approval, when codes exist) | [ ] Draft the 1.1 holiday objects (cracker, bauble, snowman) |
| Sat 21–Mon 23 Nov | [ ] On approval: generate app promo codes, record who gets each one, send creator emails (email 4)<br>[ ] If Duo screenshots still can't be uploaded, ship with 6.9" and add them later | [ ] Standby for review questions. Respond in Resolution Center within hours (see `review-notes.md` reply text) |
| **Tue 24 Nov: release** | [ ] Launch posts (Phase 3) on X, Bluesky, Mastodon and r/iPhoneDuo (rules permitting)<br>[ ] Short launch note to every journalist contacted ("it's out, no embargo")<br>[ ] Object-of-the-day #1<br>[ ] Ask FoldHunt to update the listing | [ ] Watch crash reports and reviews. Hotfix branch ready |

## Holiday drop (Wed 25 Nov – Sun 3 Jan)

| Date | Founder does | Dev does |
|---|---|---|
| Thu 26 Nov | [ ] **Create In-App Event 1** in App Store Connect (`featuring-nomination.md`). Promotion starts today (14 days before 10 Dec)<br>[ ] Object-of-the-day #2 (then #3–#6 on 28 Nov, 30 Nov, 2 Dec, 4 Dec) | [ ] 1.1 feature-complete; event deep link `squish://event/holiday-2026` |
| **Tue 1 Dec** | [ ] **Submit 1.1** with What's New (`metadata.md` §6) | [ ] 1.1 release build + holiday achievements (from the reserved 300 points) |
| Fri 4 Dec | [ ] Update the promotional text to the drop version (no new build needed) | — |
| **Thu 10 Dec** | [ ] 1.1 live, event starts. Post "Holiday Object Drop" clips. Email the earlier contacts once ("free update") | [ ] Monitor |
| Fri 18 Dec | [ ] **Submit featuring nomination 3 (January drop)** | [ ] Start 1.2 objects (Ice Cube, Water Balloon, Marshmallow) |
| 23–27 Dec | Holiday App Store Connect slowdown. **Don't submit anything** | — |

## January backorder-wave drop

| Date | Founder does | Dev does |
|---|---|---|
| Mon 4 Jan | [ ] Create In-App Event 2. Promotion starts | [ ] 1.2 feature-complete |
| **Fri 8 Jan** | [ ] **Submit 1.2** | [ ] 1.2 release build |
| Mon 18 Jan | [ ] 1.2 live, event starts (runs to Wed 17 Feb)<br>[ ] **Start the £1.99 one-week sale** (bible §12); announce on social and in promo text only, never in event metadata<br>[ ] Pitch "best apps for your new iPhone Duo" roundups | [ ] Monitor |
| Mon 25 Jan | [ ] End the sale; restore £2.99<br>[ ] Review Search data and decide whether to swap the keyword set (`metadata.md` §5 alternate) | — |

---

## Always-on checks before every submission

- [ ] Nothing in the metadata, screenshots or preview shows real objects between the halves, prices (except the subtitle decision), Hydraulic Press Channel references or "anger" language.
- [ ] The privacy label is still accurate (no new SDKs or network calls).
- [ ] Every accessibility claim in the description is true in this build.
- [ ] The review notes match the build (unlock rules, settings labels, angles).

## Sources

- App Store Connect Help, *Publish for pre-order* (release date must be at least 2 days and at most 180 days out): https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order
- App Store Connect Help, *Nominations template* (submit at least 3 weeks before launch): https://developer.apple.com/help/app-store-connect/reference/nominations/nominations-template
- Apple Developer, *In-App Events* (promote up to 14 days ahead; events last up to 31 days): https://developer.apple.com/app-store/in-app-events/
- Research 06 §7 (holiday shutdown around 23–27 Dec; January backorders); bible §13 (build weeks)
