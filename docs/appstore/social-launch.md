# Squish: Social launch copy

*For the founder to post by hand from their own accounts. Nothing here is automated or scheduled by a tool, and nobody else posts for you. Dates follow `launch-checklist.md`. Tone: calm, deadpan, a little smug. Never "rage", "anger", "stress-smashing" or "destroy". Never show or suggest anything real between the halves.*

**Links used below (all live, or live once you create them):**
- Site: https://pravegm.github.io/squish/
- Press page: https://pravegm.github.io/squish/press/
- Press-kit release (you create it; attach the files in `docs/press/` with the same names): https://github.com/pravegm/squish/releases/tag/press-kit
- App Store / pre-order link: **only exists once the app record is live.** It is the one thing to paste in: `https://apps.apple.com/app/id<your app ID>` (App Store Connect › App Information › Apple ID).

**Clips** (in `docs/press/`, cut by `.github/workflows/preview.yml` from real screen recordings of the app with its own sound; 1080 × 1920, 30 fps, H.264 + AAC, all under 10 MB, so every platform takes them as they are):

| File | Shows | Use |
|---|---|---|
| `squish-duo-duck.mp4` | iPhone Duo (simulator, tabletop): a rubber duck squashes as the top half closes, then the phone reopens to the specimen card stamped PRESSED | X teaser, launch posts |
| `squish-glass.mp4` | A glass bottle under the P-48 press: a long creak and a hold, then it breaks | Bluesky teaser |
| `squish-can.mp4` | A soda can buckling ring by ring, then sealed and filed as a specimen | Mastodon teaser |
| `squish-glass-loop.gif` | The glass break, looped (silent) | replies, Reddit comments, live blogs |

Character counts were measured by script with the App Store link filled in (X and Mastodon count any link as 23; Bluesky counts every character, and an `apps.apple.com/app/id…` link is 39):

| Post | Platform limit | Characters |
|---|---|---|
| Teaser, X | 280 | 189 |
| Teaser, Bluesky | 300 | 295 |
| Teaser, Mastodon | 500 | 483 |
| Pre-order, X | 280 | 247 |
| Pre-order, Bluesky | 300 | 263 |
| Launch, X | 280 | 200 |
| Launch, Bluesky | 300 | 289 |
| Launch, Mastodon | 500 | 443 |
| Longest pre-launch clip post (13 Nov) | 280 / 300 | 102 / 118 |
| Longest object-of-the-day post (Soda Can) | 280 | 170 |

**Always add the alt text** given under each post. Paste the post text exactly as it appears inside the quote block.

## Schedule (from `launch-checklist.md`)

| Date | What | Where | Section |
|---|---|---|---|
| **Sat 24 Oct** | Teaser | X, Bluesky, Mastodon; r/iPhoneDuo if the rules allow | Phase 1 |
| Wed 28 Oct, then every second day | Pre-launch object clips | X, Bluesky, Mastodon | Phase 1b |
| **Sat 7 Nov** (once pre-order is live) | Pre-order post; edit the Reddit post | X, Bluesky, Mastodon, r/iPhoneDuo (edit) | Phase 2 |
| **Tue 24 Nov** | Launch posts, then object of the day #1 | X, Bluesky, Mastodon, r/iPhoneDuo (rules permitting) | Phase 3, Phase 4 |
| Thu 26 Nov, 28 Nov, 30 Nov, 2 Dec, 4 Dec | Object of the day #2–#6 | X, Bluesky, Mastodon | Phase 4 |
| Sun 6 Dec (optional) | The secret-object tease | X, Bluesky, Mastodon | Phase 4 |
| **Thu 10 Dec** | Holiday Object Drop clips (1.1 live) | X, Bluesky, Mastodon | Phase 5 |
| **Mon 18 Jan** | £1.99 one-week sale | X, Bluesky, Mastodon (and the promo text) | Phase 5 |

---

## Phase 1: Teaser (Sat 24 Oct)

If you filmed the real-hands teaser (`preview-video.md` §B), post that instead of the clip named here and use its alt text from §B. Otherwise post the clip below: it's the app itself on the iPhone Duo simulator, which is honest pre-hardware footage.

### X  ·  attach `squish-duo-duck.mp4`
> my £2,000 phone is a hydraulic press now
>
> close it slowly. feel it give. ka-chunk.
>
> building Squish for iPhone Duo. everything's on screen, nothing real goes inside
>
> https://pravegm.github.io/squish/

*Alt text:* A screen recording of the iPhone Duo's folding screen in tabletop pose. A yellow rubber duck on the lower half squashes flatter as the top half closes, while a dial counts the hinge angle down. When the phone opens again, the flattened duck is stamped "PRESSED" on a specimen card.

### Bluesky  ·  attach `squish-glass.mp4`
> I'm building a hydraulic press for the iPhone Duo.
>
> A virtual glass bottle sits on screen. Press slowly and it creaks for a long, tense moment. Then it doesn't.
>
> It's called Squish. Coming in November. (Everything's on screen. Please don't press real bottles.)
>
> https://pravegm.github.io/squish/

*Alt text:* A screen recording of Squish on an iPhone. A yellow press ram comes down on a clear glass bottle, pauses while the bottle strains, then pushes on until the bottle breaks into chunky rounded shards.

### Mastodon  ·  attach `squish-can.mp4`
> I'm building a little toy for the iPhone Duo: the hinge becomes a hydraulic press.
>
> Pick a virtual object (bubble wrap, a rubber duck, a soda can) and close the phone slowly. The crush follows the hinge angle continuously: stop halfway, or creep down a degree at a time. Sound and haptics land in the same frame as each crack. Close it for a "ka-chunk", reopen to find a pressed specimen.
>
> No ads, no IAP, no tracking. November.
>
> https://pravegm.github.io/squish/
>
> #iPhoneDuo #iOSDev #IndieDev

*Alt text:* A screen recording of Squish on a regular iPhone, where you drag the press down instead of folding. A soda can buckles ring by ring under a yellow ram, the press seals, and the flattened can comes back as a specimen card.

### r/iPhoneDuo (teaser, Sat 24 Oct)
**Before posting:**
1. Read the sidebar rules and pinned posts. If there's a dev or self-promo day or a megathread, use it.
2. Choose the right flair.
3. Post from an account that has commented helpfully in the sub before (roughly 9 non-promotional contributions for every 1 self-promo).
4. **Say you're the developer** in the first line.
5. No App Store link in the teaser, no vote requests, and reply to every comment for the first 2 hours.

**Title:** I'm making the Duo into a hydraulic press. Would love feedback on the feel before launch

**Body** (attach `squish-duo-duck.mp4`, or your real-hands teaser):
> Hi all, I'm the developer, so this is self-promo, but I'm mostly here for feedback.
>
> Squish is a toy where the hinge works as a press: a virtual object sits on the lower screen, and as you close the top half it squishes continuously with the hinge angle (not just open/closed). There's haptic "strain" that builds as you go, a ka-chunk when you close it, and when you reopen you get a "pressed specimen" card for a collection.
>
> Questions for Duo owners:
> 1. Do you press with the phone flat on a table, or in your hands?
> 2. What object should I add first after launch? (shortlist: ice cube, fortune cookie, water balloon, marshmallow)
>
> Everything is on screen. Please never close your phone on real things; that inner screen is soft.
> Planned: £2.49/$2.49, no ads, no IAP. I'm looking for ~30 TestFlight testers with Duos in early November. Reply here and I'll DM.

---

## Phase 1b: Pre-launch object clips (Wed 28 Oct, then every second day to 23 Nov)

`launch-checklist.md` starts these on Wed 28 Oct with Bubble Wrap and says "every 2 days from here". The dates below run every second day up to launch; 7 Nov is the pre-order post instead. Each clip is the app's own share clip: press the object on your Duo, then **Share › Share Clip** on the specimen card (6–10 s, 1080 × 1920, with sound and the card as the last frame). Post the same text on X, Bluesky and Mastodon; add `#iPhoneDuo` on Mastodon only. Skip a date whenever you like; never post two on one day.

| Date | Object | Post copy |
|---|---|---|
| Wed 28 Oct | Bubble Wrap | 24 bubbles. Close slowly and they go one at a time. Squish, coming in November. |
| Fri 30 Oct | Rubber Duck | The squeak climbs as the press comes down. Then *bloop*. Squish, coming in November. |
| Sun 1 Nov | Egg | Hairline cracks first. Then the yolk. Squish, coming in November. |
| Tue 3 Nov | Crayon | Snap. Snap. Waxy smear. Squish, coming in November. |
| Thu 5 Nov | Jelly | It wobbles, then it doesn't. Squish, coming in November. |
| Sat 7 Nov | — | Pre-order post instead (Phase 2) |
| Mon 9 Nov | Cake Slice | It wasn't your birthday anyway. Squish, out 24 Nov. Pre-order: [App Store link] |
| Wed 11 Nov | Gummy Bear | Gummy bear, ex-bear. Squish, out 24 Nov. Pre-order: [App Store link] |
| Fri 13 Nov | Soda Can | Five buckles, if you go slowly enough to count. Squish, out 24 Nov. Pre-order: [App Store link] |
| Sun 15 Nov | Glass Bottle | It creaks. Then it doesn't. Squish, out 24 Nov. Pre-order: [App Store link] |
| Tue 17 Nov | Bubble Wrap | Fast for a rattle, slow for a ripple. Squish, out 24 Nov. Pre-order: [App Store link] |
| Thu 19 Nov | Rubber Duck | He springs back. He's been through worse. Squish, out 24 Nov. Pre-order: [App Store link] |
| Sat 21 Nov | Egg | One egg in eight hides a tiny toy chick. Squish, out 24 Nov. Pre-order: [App Store link] |
| Mon 23 Nov | The shelf | Every press, filed as a specimen. Squish is out tomorrow. Pre-order: [App Store link] |

*Alt text pattern:* "A screen recording of Squish: a yellow press ram flattens a cartoon [object] on a phone screen, then the result appears as a specimen card." For 23 Nov: "The Squish shelf: a grid of pressed specimen cards, one slot still a silhouette."

If pre-order isn't live by 9 Nov, drop the "Pre-order:" part and keep "coming in November".

---

## Phase 2: Pre-order (Sat 7 Nov, once it's live)

### X  ·  attach `squish-duo-duck.mp4`
> Squish is up for pre-order.
>
> Your phone becomes a hydraulic press: close it slowly, feel it give, snap it shut, open it to a pressed specimen. 10 objects, one secret. No ads, no in-app purchases.
>
> £2.49 / $2.49 · out 24 Nov
> [App Store link]

### Bluesky  ·  attach `squish-duo-duck.mp4`
> Squish is up for pre-order.
>
> Your phone becomes a hydraulic press: close it slowly, feel it give, snap it shut, open it to a pressed specimen. 10 objects, one secret. No ads, no in-app purchases.
>
> £2.49 / $2.49 · out 24 Nov
> [App Store link]

### Mastodon
The Bluesky text, then this line before the link: "Works on every iPhone too: drag the ram down if you don't fold." End with `#iPhoneDuo #IndieDev`.

*Alt text:* as the X teaser.

**r/iPhoneDuo:** don't make a new post. Edit the teaser post with an "Update: pre-order is live: [App Store link]" line (only if the sub allows links in edits), and reply to the testers who asked.

---

## Phase 3: Launch day (Tue 24 Nov)

Post the launch posts first, then object of the day #1 (Phase 4) later the same day.

### X  ·  attach `squish-duo-duck.mp4` (or the 30 s App Preview from the press-kit release)
> Squish is out.
>
> Close your phone slowly and feel a rubber duck give, one squeak at a time.
> Ka-chunk.
>
> £2.49 / $2.49 · no ads · no IAP · works on every iPhone, made for the fold
> [App Store link]

### Bluesky  ·  attach `squish-duo-duck.mp4`
> Squish is out today. It turns the iPhone Duo into a hydraulic press (and every other iPhone into a slightly less dramatic one).
>
> 10 objects that each break their own way, a shelf of pressed specimens, no ads, no in-app purchases, no data collected.
>
> [App Store link]

### Mastodon  ·  attach `squish-duo-duck.mp4`
> Squish is out. 🗜️
>
> On iPhone Duo, the hinge drives a hydraulic press in real time: every degree you close squishes a little more, with haptics and sound in the same frame. On other iPhones, you drag the ram. Ten objects at launch, each breaking its own way, plus a secret one that has opinions about being squished.
>
> £2.49 / $2.49, no ads, no IAP, no tracking. Free object drops all winter.
>
> [App Store link]
> #iPhoneDuo #iOSDev #IndieDev

*Alt text (all three):* as the X teaser.

### r/iPhoneDuo launch post (only if the rules allow a launch post; otherwise the megathread)
**Title:** [Dev] Squish is out: thanks for the feedback on the hydraulic press toy

**Body:**
> Developer here. A few weeks ago you told me what you wanted from the hinge press. Here's what changed because of this sub:
> - [real change 1, e.g. "tabletop coaching" because most of you press flat]
> - [real change 2]
>
> It's £2.49/$2.49, no ads, no IAP, no data collected. Next free drop is the holiday one in December, and the top-voted object from the teaser thread ([name]) is in it.
>
> Happy to answer anything about how the hinge mapping works. Link in the comments, per the rules.

*(The two changes and the object name can only come from the real thread; fill them in on the day or cut those lines.)*

---

## Phase 4: "Object of the day" series (Tue 24 Nov – Fri 4 Dec)

Every second day from launch: **24, 26 and 28 Nov, 30 Nov, 2 Dec, 4 Dec**. Each post gets a 6–10 s share clip (Share › Share Clip on the specimen card), whose end frame is the specimen card. Same text on X, Bluesky and Mastodon; add `#iPhoneDuo` on Mastodon only. Not on Reddit.

| # | Date | Object | Post copy | Alt text (short) |
|---|---|---|---|---|
| 1 | Tue 24 Nov | **Bubble Wrap** | Object of the day: Bubble Wrap. 24 bubbles, 24 tiny opinions. Close slowly for a ripple, fast for a rattle. Either way, ka-chunk. | Cartoon bubble wrap on a phone screen popping row by row as a yellow press ram descends |
| 2 | Thu 26 Nov | **Rubber Duck** | Object of the day: Rubber Duck. The squeak climbs as the press comes down, then *bloop*. He springs back when you open it. He's fine. He's been through worse. | A yellow rubber duck squashing flat under a press ram, then springing back |
| 3 | Sat 28 Nov | **Egg** | Object of the day: Egg. Hairline cracks first. Then the yolk. One in eight hides a tiny toy chick. Double yolks are rarer, but real. | A cartoon egg cracking under a press; yolk spreading across a steel plate |
| 4 | Mon 30 Nov | **Cake Slice** | Object of the day: Cake Slice. It wasn't your birthday anyway. Frosting ooze, a bent candle, sprinkles everywhere, and sometimes a jam centre. | A slice of cake flattening, frosting oozing out of the sides, sprinkles bursting |
| 5 | Wed 2 Dec | **Soda Can** | Object of the day: Soda Can. It buckles ring by ring (five buckles, if you go slowly enough to count), then the fizz goes. Unlocks after you press three different things. | A soda can with a made-up label folding like a concertina, then a fizz spray |
| 6 | Fri 4 Dec | **Glass Bottle** | Object of the day: Glass Bottle. The longest creak in the app, then the biggest moment. Earned with a Perfect Squish: slow, steady, no hesitating. | A glass bottle under a press, creaking, then breaking into chunky rounded shards |

**Post 7 (the tease, optional, Sun 6 Dec):** "There is a tenth object. It does not squish. That's all we're saying." (Image: the "?" silhouette slot on the Shelf. Never show the object.)

---

## Phase 5: After launch

- **Thu 10 Dec, Holiday Object Drop (1.1 live):** "Squish 1.1 is out: the Holiday Object Drop. [the new objects, by name]. Free for everyone who has Squish. [App Store link]" plus a share clip of one new object. Write the object line once 1.1 is final; never announce an object that isn't in the build.
- **Mon 18 Jan, the £1.99 sale (one week, to Mon 25 Jan):** "Squish is £1.99 / $1.99 this week, then back to £2.49. A hydraulic press for your iPhone. No ads, no in-app purchases. [App Store link]". Social posts and promo text only, never In-App Event metadata.

---

## Don'ts (all phases)

- No real objects between the halves, even as a joke. No "try it with a grape".
- No Hydraulic Press Channel references, characters or catchphrases, and no "Pocket Press".
- No anger or venting language ("rage", "smash your stress", "therapy").
- No "share to unlock", no giveaways that require follows or reposts, and no buying engagement.
- Use Apple marks correctly: "iPhone Duo" in referential use only, never "the Duo app" as a product name, and no Apple logos.
- Don't put the price inside videos (keep it in the post text), so the clips stay usable as store-safe footage.
