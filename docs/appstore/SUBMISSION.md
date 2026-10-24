# Squish 1.0: submission runbook

*The definitive, click-by-click path from nothing to "Ready for Sale" on **Tue 24 Nov 2026**. Written 23 Oct 2026. Every decision behind a value is in `DECISIONS.md`. The machine-readable metadata is `asc-metadata.json`. Follow the sections in order; each one says who does it.*

---

## 0. The only things the founder must personally supply

Everything else is decided, written or automated.

| # | What | Where it goes | Why it can't be done for you |
|---|---|---|---|
| 1 | **Your legal name** (or company name) | the Copyright line (`2026 <name>`), the agreements, the tax forms, and the EU trader declaration | It's your legal identity |
| 2 | **Review contact: first name, last name, phone, email** | App Review Information | App Review calls or emails a real person |
| 3 | **EU trader contact details** (address, phone, email). These are shown publicly on EU storefronts | Business → Digital Services Act | Only you can declare them. If you'd rather not publish them, untick the 27 EU countries in Availability (`DECISIONS.md` #7) |
| 4 | **Apple-login actions** | — | They need your Apple Account |
| | a. Accept the Paid Apps agreement; fill in tax and banking | Business | |
| | b. Enrol in the Small Business Program | developer.apple.com | |
| | c. Register the bundle ID and create the app record (§1) | | |
| | d. Create the App Store Connect API key (Admin) and add the 4 GitHub secrets (§5a). Builds and listing pushes then run on GitHub | | |
| | e. Nothing to build yourself: GitHub builds with Xcode 27.1 and uploads to TestFlight (§5a). Your Mac is Intel and can't run Xcode 27 | | |
| | f. Press **Submit** for the featuring nomination (§9) and for review (§7) | | |
| | g. On launch day, publish the Accessibility labels (§8) | | |

**Optional:** a support email for the support page. The page currently routes support through GitHub issue forms.

**Keep these out of the repo.** The repo is public, so names, phone numbers, emails and the `.p8` key never go into it. Give them to the tool the way `tools/appstore/README.md` describes (local, untracked).

## Timeline

| Date | Who | Step |
|---|---|---|
| **This week (by Thu 29 Oct)** | Founder | §1 app record, §2 agreements, tax, banking, SBP and DSA, §3 API key |
| **By Tue 3 Nov** | Founder | §9 featuring nomination 1. **Deadline: 3 weeks before launch** |
| 23 Oct – 6 Nov | Founder + Claude | Real-Duo tuning (`docs/HANDOVER.md` §3). Claude turns the Tuning Lab log into new defaults |
| By Fri 6 Nov | Founder | §5 first archive and upload; §6 TestFlight internal, then external |
| **Mon 9 Nov** | Claude | Code freeze for 1.0. Last day for the App Preview to make 1.0 (`DECISIONS.md` #10) |
| Mon 9 – Tue 10 Nov | Founder | §5 release-candidate upload; §4 tool push; §4b manual steps |
| **Wed 11 Nov** (hard cut Mon 16 Nov) | Founder | §7 submit for review |
| Thu 19 Nov | Founder | Featuring nomination 2 (Holiday), `featuring-nomination.md` |
| **Tue 24 Nov, 08:00 UTC** | Apple | Scheduled release. Then §8 launch-day steps |

---

## 1. Create the app record (founder, web, once)

**1a. Register the bundle ID** at developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+**:

| Field | Value |
|---|---|
| Type | App IDs → App |
| Description | `Squish` |
| Bundle ID | **Explicit**: `com.pravegm.squish` |
| Capabilities | tick **Game Center** (nothing else) |

**1b. Create the app** in App Store Connect → Apps → **+** → New App:

| Field | Value |
|---|---|
| Platforms | **iOS** |
| Name | `Squish: Fold-to-Crush Press`. If it's taken: `Hingepress`, and tell Claude, because the JSON and copy change |
| Primary Language | **English (U.K.)** |
| Bundle ID | `com.pravegm.squish` |
| SKU | `squish-ios` |
| User Access | Full Access |

**1c. Turn on Game Center:** the app → Services / Features → **Game Center** → enable it. The achievements are created in §4.

## 2. Agreements, tax, banking, Small Business Program, DSA (founder, web)

1. **Business → Agreements:** accept the **Paid Apps** agreement. Without it, a £2.99 app can't be priced.
2. **Business → Tax:** complete the US tax form (W-8BEN for an individual outside the US, W-8BEN-E for a company), plus any local tax forms App Store Connect asks for.
3. **Business → Banking:** add the payout account. The agreement shows "Active" once tax and banking are both done.
4. **Small Business Program:** enrol at https://developer.apple.com/app-store/small-business-program/enroll/ as the Account Holder. There are no associated accounts.
   - Proceeds move to 15% fifteen days after the end of the fiscal month in which enrolment is approved, so enrolling now covers launch.
5. **Digital Services Act:** App Store Connect → Business → **Digital Services Act Compliance** → "I am a trader". Enter the trader details (founder-only item 3).
   - If you decline to publish them, untick all EU storefronts in §4b step 3 instead.

## 3. API key for the tool (founder, web, once)

1. Go to Users and Access → **Integrations** → App Store Connect API → **Team Keys** → **Generate API Key**.
2. Name it `Squish CI`, with role **Admin**. Admin is needed so the TestFlight workflow can create signing certificates (§5a), and this one key also runs the listing tool, so don't make a second key.
3. Download the `.p8` (you only get one chance), and note the **Key ID** and **Issuer ID**.
4. Store all three outside the repo, as `tools/appstore/README.md` says.

## 4. Push the metadata with the tool (founder runs it; Claude can run it if given the key)

The tool is `tools/appstore/asc.swift`. Its usage, environment variables and flags are in **`tools/appstore/README.md`**; follow that file. In outline:

1. **Get the frames and badges:**
   - Download the screenshot artifacts into an empty folder: `gh run download 39952047687 -R pravegm/squish -D <artifacts-root>`. You get `store-69/`, `store-61/` and `store-duo/`, matching the paths in `asc-metadata.json`.
   - Render the achievement art with `xcrun swift tools/appstore/badges.swift`. It also re-checks the 10 IDs.
2. **Give the founder-only values to the tool locally** (legal name, review contact), as the README says. Don't edit them into the committed JSON.
3. **Run `tools/appstore/asc.swift push`.** It sends, from `asc-metadata.json`:
   - the en-GB and en-US name, subtitle, description, keywords, promo text and URLs;
   - the categories, age rating, review notes and contact;
   - the scheduled release, the price;
   - the 10 achievements with their images;
   - the `APP_IPHONE_67` and `APP_IPHONE_61` screenshot sets;
   - the 6.9" App Preview, if it has been delivered.
4. **Re-run after any copy change.** The push is the only way metadata gets in. If you change the review notes, change the block in `review-notes.md` and re-mirror it.

### 4b. Manual-only steps, with the exact answers

The API can't do these, so do them in the web UI after the push.

1. **App Privacy** (App Store Connect → the app → App Privacy):
   - Privacy Policy URL: `https://pravegm.github.io/squish/privacy/`.
   - Get Started → "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app** → Save → **Publish**.
   - Game Center needs nothing: it's Apple's data (`privacy-labels.md`).
2. **App Information** (fill in whatever the push didn't set):
   - **Content Rights:** "Does your app contain, show, or access third-party content?" → **No**.
   - **Age Rating:** if it isn't already set, Edit and answer:
     - Cartoon or Fantasy Violence → **Infrequent**; every other content question → **None**;
     - every capability question (web access, user-generated content, messaging, social media, advertising, parental controls, age assurance, gambling, loot boxes, health or wellness) → **No**;
     - Made for Kids → **No**.
     - Expect **9+**.
   - **Categories:** Games (Casual, Simulation); secondary Entertainment.
3. **Pricing and Availability:**
   - **Price:** base country **United Kingdom, £2.99**, leaving the other countries on Apple's automatic prices. Check the US shows $2.99.
   - **Availability:** **all countries or regions except China mainland**. Untick the EU too only if you skipped DSA trader status.
   - **Pre-order:** **off**.
   - **Family Sharing:** **on**.
4. **The 1.0 version page** (iOS App → 1.0):
   - **Build:** select the release-candidate build from §5.
   - **Game Center:** switch on, then **+** → add all **10** achievements. They only go live with a version that includes them.
   - **Copyright:** `2026 <legal name>`.
   - **App Review Information:**
     - Sign-in required: **unticked**.
     - Contact: founder's first name, last name, phone and email.
     - Notes: pushed by the tool. If not, paste the block from `review-notes.md`.
   - **Version Release:** **"Automatically release this version after App Review approval, no earlier than"** → **24 Nov 2026, 08:00 UTC**. The UI shows this in your time zone: 08:00 in the UK, 00:00 Pacific.
   - **iPhone Duo screenshots:**
     - In Previews and Screenshots, open the device list. If an **iPhone Duo** entry exists, upload `store-duo/duo-screens/store/duo-inner/01…07` to the inner-display slot, then `duo-outer/O1, O2` to the outer one, in that order.
     - Check them with App Store Connect's iPhone Duo **preview tool**.
     - If there is no Duo entry, skip it. The Duo sets ship in 1.0.1 (`DECISIONS.md` #13).
   - **Check the iPhone sets** the tool uploaded: 5 frames in the 6.9" slot, 5 in the 6.1" slot, in order P1–P5. Look at P5 at both sizes once (`DECISIONS.md` §4 caveat).
5. **Export compliance:** nothing to do. `ITSAppUsesNonExemptEncryption = NO` is already in the build (`project.yml`). If App Store Connect asks anyway:
   - "Does your app use encryption?" → **No**.
   - Or, in the newer form, "What type of encryption algorithms does your app implement?" → **None of the algorithms mentioned above**.
   - No French declaration is needed.
6. **Accessibility Nutrition Labels:** **not yet**. They can only be published once 1.0 is live (§8).

## 5. Build and upload

**The founder's Mac is Intel, and Xcode 27 doesn't run on Intel Macs.** So builds are made and uploaded by GitHub Actions on Apple-silicon runners with Xcode 27.1: the **CI route** below. The Xcode route after it is for anyone who later works from an Apple-silicon Mac.

### 5a. CI route (the default): Actions → TestFlight

**One-time setup (founder, about 15 minutes, all in a web browser):**
1. **Join the Apple Developer Program** at developer.apple.com/programs/enroll, as an individual, with your legal name. It costs £79 or $99 a year, and approval can take up to 48 h.
2. **Create the app record** as described in §1.
3. **Create an API key:**
   - In App Store Connect, go to **Users and Access → Integrations → App Store Connect API → Team Keys → +**.
   - Name: `Squish CI`. Access: **Admin**. Admin lets Xcode on the runner create the signing certificate and profile itself.
   - **Download** the `.p8` file. Apple lets you download it only once.
   - Note the **Key ID** (in the table) and the **Issuer ID** (above the table).
4. **Find your Team ID:** developer.apple.com → Account → **Membership details** → Team ID (10 characters).
5. **Add four secrets** on GitHub: the repo → **Settings → Secrets and variables → Actions → New repository secret**.

   | Name | Value |
   |---|---|
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_PRIVATE_KEY` | open the `.p8` in TextEdit and paste **all** of it, including the BEGIN and END lines |
   | `APPLE_TEAM_ID` | the Team ID |

   Secrets are encrypted and never shown in logs. The same three `ASC_*` secrets also let `asc.yml` push the listing (§4) without your Mac.

**Every build after that:**
- Go to Actions → **TestFlight** → Run workflow, or ask Claude to run it.
- About 20 minutes later the build is in App Store Connect → TestFlight. Then follow §6.
- The build number is the run number, so every upload is unique.

**Before the release-candidate build, Claude makes sure `main` has the tuned defaults from your Duo.** The 1.0 version, the `NSPhotoLibraryAddUsageDescription` string, the Settings credits fix and the privacy manifest are already in. Everything must be green on CI.

### 5b. Xcode route (Apple-silicon Mac only)

1. Pull `main` and generate the project:
   ```bash
   git pull
   xcodegen generate
   open Squish.xcodeproj
   ```
   Use **Xcode 27.1**. The project is generated, so always re-run `xcodegen generate` after pulling.
2. In the Squish target, go to **Signing & Capabilities**:
   - Team: your team.
   - Tick **Automatically manage signing**.
   - Confirm the **Game Center** capability is listed.
3. Set the build number: each upload needs a new `CURRENT_PROJECT_VERSION`. Use 1 for the first upload, then 2, 3 and so on. Claude bumps it in `project.yml` on request, or you can set it in the target's General tab for that archive.
4. Choose the run destination **Any iOS Device (arm64)**, then **Product → Archive**.
5. In the Organizer, select the archive → **Distribute App** → **App Store Connect** → **Upload**. Keep the defaults (upload symbols on, automatic signing) → **Upload**.
6. Wait for the "has completed processing" email, usually 10–30 minutes. The build appears under TestFlight. You should not be asked an export-compliance question (step 5 of §4b).

## 6. TestFlight (founder)

1. **Internal:** TestFlight → Internal Testing → **+** group `Studio` → add yourself → add the build.
   - Paste this into "What to Test": `The press is open. Ten objects, one shelf of pressed specimens, zero ads. Close slowly.`
   - Then check on the Duo:
     - the first-hour checks in `docs/HANDOVER.md` §3;
     - **Share → Save Image and Save Video** (this is the crash risk in `DECISIONS.md` §6 #1);
     - one full pass with **VoiceOver** on, and one with **Reduce Motion** on (`accessibility.md`);
     - Settings → Press without folding.
2. **External:**
   - Create the group: TestFlight → External Testing → **+** group `Duo owners`.
   - Test Information:
     - Beta App Description: the promo text.
     - Feedback Email: your contact email.
     - Sign-in required: off.
     - Notes: the `review-notes.md` block.
   - Add the build → **Submit for Review**. The first external build gets a short Beta App Review.
   - Turn on the **Public Link** (limit 100) and post it as `social-launch.md` says.
3. Every later build goes to both groups. Only a build that has passed the checks in step 1 becomes the release candidate.

## 7. Submit for review (founder, by Wed 11 Nov)

1. Confirm the §4 push ran on the release-candidate day, and that everything in §4b is done.
2. On the 1.0 page, click **Add for Review**. App Store Connect lists anything missing; fix it and repeat.
3. Click **Submit to App Review**.
4. Expect 24–48 hours.
   - **If rejected:** use the replies in `review-notes.md` ("If rejected under…"). A metadata-only rejection can be fixed in the same submission.
   - Answer in the Resolution Center within hours.
5. **Once approved,** the status becomes "Pending Developer Release" or "Ready for Distribution" with the scheduled date. The app goes live by itself on **24 Nov at 08:00 UTC**.
   - Don't press "Release This Version" early.

## 8. Launch day: Tue 24 Nov (founder)

1. After 08:00 UTC, check the product page in the UK and US storefronts: the price, the 9+ rating, "Data Not Collected", and the screenshots.
2. **Accessibility Nutrition Labels:** App Store Connect → the app → **App Accessibility** → Get Started → **iPhone**.
   - Tick **VoiceOver** and **Reduced Motion** only. Leave every other box unticked.
   - **Publish.** The reasons for each are in `accessibility.md`.
3. Generate the promo codes (App Store Connect → the app → Promo Codes) for the creators in `press-kit.md`.
4. Watch Crashes and Ratings in App Store Connect. Claude prepares 1.0.1, which is planned to be submitted by Fri 27 Nov:
   - the real-Duo photo for frame 1;
   - the Duo screenshot sets if they missed 1.0;
   - the App Preview if it missed 1.0;
   - the accessibility fixes in `accessibility.md`;
   - the FOLD-REVIEW-9 §4 list.

## 9. Featuring nomination 1 (founder; deadline **Tue 3 Nov 2026**)

App Store Connect → the app → **Featuring** → **Nominations** → **Create Nomination**. Paste these fields. They're the same as in `featuring-nomination.md`, which is the master copy.

| Field | Value |
|---|---|
| Nomination Name | `Squish - App Launch - iPhone Duo hinge press` |
| Type | **App Launch** |
| Publish Date | Specific day: **2026-11-24** |
| Related Apps | Squish (auto-filled) |
| Platforms | iOS |
| Countries or Regions, Localizations | leave the auto-selection |
| In-App Events | none (the Holiday event goes with nomination 2) |
| Supplemental Materials | `https://pravegm.github.io/squish/` · `https://pravegm.github.io/squish/press/` · your teaser post URL (when posted) · the TestFlight public link (when live) |

**Description** (965 / 1,000):
```
Squish turns iPhone Duo into a hydraulic press. The two halves of the inner screen are the press plates: pick a virtual object, close the phone slowly, and watch, hear and feel it strain, crack and give way, following the hinge degree by degree. Shut it for a heavy ka-chunk on the outer display, then reopen to reveal a pressed specimen card for your shelf.

The hinge is the whole interface: the live angle drives deformation, synthesized sound and haptics in the same frame. Ten launch objects each fail their own way, from bubble wrap that pops bubble by bubble to a glass bottle that creaks, then shatters.

Built for everyone: the same press works on every iPhone with a drag, and Press without folding brings it to Duo owners who can't or don't want to fold. Every unlock works either way. VoiceOver can press step by step, and Reduce Motion calms every effect.

One price, no ads, no in-app purchases, no timers, no data collected. Free object drops follow.
```

**Helpful Details** (415 / 500):
```
Optimized for iPhone Duo: tabletop and book poses, inner and outer displays (the sealed press and an object picker live on the cover). Built with Xcode 27.1 on the public hinge API. A one-person studio: every object is generated in code and every sound is synthesized live, so free drops can come every few weeks (Holiday Object Drop planned for December). Slow, steady closes are quietly rewarded; slams never are.
```

Click **Submit**. You can save a draft first, but a draft isn't a nomination. Nomination 2 (Holiday, New Content) is due **Thu 19 Nov**.
