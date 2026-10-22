# 04 — Psychology & UX of Squish

*Research brief for Squish, a £2.99 hydraulic-press toy for iPhone Duo. Launches 23 Oct 2026, iOS 27.1.*
*Constraints applied: ships in about 4 weeks with about 10 launch objects, more in free updates. Audience is 12+: edgy humour is fine, gore is not. One AI developer builds everything with no human artists, so screens and systems stay small.*

---

## Key takeaways

1. **The pleasure comes from tension, then release, then reveal. Anger relief is not the pitch.** The best meta-analysis on venting (Kjærvik & Bushman 2024, 154 studies, ~10k participants) found that high-arousal "letting it out" does not reduce anger. Calming, low-arousal activity does ([ScienceAlert](https://www.sciencealert.com/venting-doesnt-reduce-anger-but-something-else-does-study-says)). So market Squish as *satisfying* and *calming*, never as "rage therapy". The slow close is our advantage: it is a slow, controlled, low-arousal act, much closer to bubble wrap than to a sledgehammer.
2. **"Oddly satisfying" is under-researched, but four ideas hold up.** (a) A "just right" sense of completion (Keedy, U Chicago, in [Discover](https://www.discovermagazine.com/why-are-oddly-satisfying-videos-sosatisfying-218)). (b) Vicarious touch through a touchscreen ([Necsus](https://necsus-ejms.org/touchscreens-tactility-and-material-traces-from-avant-garde-artists-to-instagram-asmrtists/); [Nansen & Balanzategui 2022](https://journals.sagepub.com/doi/10.1177/13548565221105196)). (c) Predictable cause and effect with a small surprise. (d) Sound that matches the picture. Squish turns vicarious touch into real touch, because your hand does the pressing.
3. **The hinge has to feel like it is doing the work.** Spend about 60% of the effort on feel: deformation that tracks the angle continuously, speed-sensitive sound (Unpacking's [lesson](https://www.gamedeveloper.com/marketing/auditory-tales-from-the-making-of-zen-puzzler-unpacking)), and juicy haptics. In a CHI 2021 study with 38 people, vibrotactile embellishments measurably raised enjoyment, immersion and meaning ([Singhal & Schneider](https://uwaterloo.ca/haptic-experience-lab/projects/juicy-haptic-design-vibrotactile-embellishments-can-improve)).
4. **Design for the hardware we actually have.** The Duo hinge is stiff, uses variable torque, holds angles, and snaps shut on magnets ([9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/)). Put the dramatic failure, the crack or burst, at **about 25–45°**, where the user can still see the screen. The magnetic snap becomes the final "thunk", felt and heard but not seen. The reveal happens on reopen, which is exactly the beat Toastie uses ([TechRadar](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)).
5. **Make a toy, not a game.** No score on the main loop, no fail state, no timers. Toca Boca ([Kill Screen](https://www.killscreen.com/secret-smart-kids-entertainment-give-them-toy-not-game/)) and Townscaper (Stålberg calls it "more of a toy than a game", [Bloomberg](https://www.bloomberg.com/news/articles/2020-07-24/the-video-game-where-you-build-an-empty-town)) show that open-ended play keeps people coming back when the core feel is excellent.
6. **Each object needs a personality and a small surprise inside.** Rewards that are better than expected drive dopamine; rewards that arrive exactly as predicted do not ([Schultz-line review](https://pmc.ncbi.nlm.nih.gov/articles/PMC10116860/)). Uncertainty while waiting builds anticipation ([Fiorillo et al. 2003](https://www.nature.com/articles/nrn1127)). Use small, honest variation: crack patterns, a hidden surprise inside 1 in 8 crushes, rare "golden" variants. Never put money or random paid drops behind it.
7. **Make the ending the best part.** By the peak-end rule (Redelmeier & Kahneman), people remember an experience by its peak and its end ([summary](https://en.wikipedia.org/wiki/Peak%E2%80%93end_rule)). The reveal is the end, so give it a short slow-motion replay, a satisfying final sound and the card landing in the collection.
8. **Teach with zero text and do not show a tutorial.** The first object (bubble wrap) responds before the user has been taught anything. A ghosted "close" arc on the hinge is the only hint. Discover the gesture by doing it, as in Monument Valley ([critique](https://mechanicsofmagic.com/2022/05/19/monument-valley-critical-play-2/)). Clear's 7-page tutorial is the cautionary tale ([Web Designer Depot](https://webdesignerdepot.com/?p=18293)).
9. **Sharing should mean one tap to a 6–10 second vertical clip with sound.** It should show the object, the slow close, the burst and the flattened card, with a tiny watermark. Like Wordle's grid, the share is a brag about your own result, not an ad ([Northeastern](https://news.northeastern.edu/2022/01/21/what-makes-wordle-so-g-r-e-a-t/)). It also doubles as our App Store preview footage.
10. **A paid, no-IAP model makes ethical design easy, so use that as a selling point.** Avoid Zagal et al.'s temporal, monetary and social-capital dark patterns ([taxonomy summary](https://arxiv.org/html/2412.05039v1)): no streak penalties, no energy, no push-notification nagging, no "share to unlock". Competitors such as Hydraulic Press Pocket and pop-it apps are free-to-play with slots, IAP and ads ([App Store](https://apps.apple.com/app/id1224226281)), and ad frequency is their top complaint ([marlvel](https://marlvel.ai/apps/pop-it-fidget-3d-pop-it-toy/reviews)). "No ads. No IAP. Just squish." is a selling point in itself.

---

## 1. Why crushing things feels good

### 1.1 What the evidence actually says
- **Catharsis doesn't work, but satisfaction does.** Bushman's long-running work and the 2024 meta-analysis show that arousal-raising venting such as hitting or boxing doesn't reduce anger. Calming activity does ([ScienceAlert](https://www.sciencealert.com/venting-doesnt-reduce-anger-but-something-else-does-study-says); [Simply Psychology on rage rooms](https://www.simplypsychology.com/articles/rage-rooms-catharsis-psychology)). Where rage rooms do lift mood, the likely reasons are novelty, exertion and permission, not "releasing" anger. **Implication:** never position Squish as anger management. Position it as a calm, sensory ritual. Slow closing fits the low-arousal side of the evidence.
- **Bubble wrap is the closest precedent to Squish.** Dillon's small study in *Psychological Reports* found students who popped two sheets felt calmer and more alert than controls ([Packaging Digest](https://www.packagingdigest.com/packaging-design/bubble-wrap-offers-packaging-protection-stress-relief)). It is a small, old study, so treat it as directional only. The "33-minute massage" stat is a Sealed Air-commissioned survey, so don't cite it. Bubble wrap is also the ideal first object: everyone knows it, the reward is instant, and each pop is a small, contained event.
- **The "just right" feeling.** Keedy (U Chicago) links satisfying content to the feeling of order and completion. Spanish researchers found that interrupting a task causes unease, more strongly in people with OCD ([Discover](https://www.discovermagazine.com/why-are-oddly-satisfying-videos-sosatisfying-218); related "Not Just Right" work: [UNED](https://portalcientifico.uned.es/documentos/5eb09ed8299952764113cc38)). **Implications:** (a) a press should always *finish*, with a clean flat result and a clear end state; (b) the collection grid is an order-making device, so neat rows of flattened shapes are satisfying in their own right; (c) don't interrupt a press with pop-ups.
- **Vicarious touch made real.** The literature on satisfying and slime videos centres on "visual tactility": watching hands touch materials feels pleasant when you watch on a touchscreen ([Necsus 2020](https://necsus-ejms.org/touchscreens-tactility-and-material-traces-from-avant-garde-artists-to-instagram-asmrtists/); [Nansen & Balanzategui 2022](https://journals.sagepub.com/doi/10.1177/13548565221105196); [Revealing Reality](https://think.revealingreality.co.uk/asmr-page2)). Squish goes one step further: the user's own hand closes a real mechanism. That puts it in Swink's "real-time control of virtual objects", the core of game feel ([Game feel](https://en.wikipedia.org/wiki/Game_feel)).
- **ASMR relaxes some people, not everyone.** Poerio et al. (2018, PLOS ONE) found heart rate fell by about 3.1 bpm and mood improved, but only among people who experience ASMR ([Sheffield](https://www.sheffield.ac.uk/psychology/news/brain-tingles-first-study-its-kind-reveals-physiological-benefits-asmr)). **Implication:** sound must be optional but excellent. Offer a "Soft" (ASMR-style, close-mic crackles) sound set rather than assuming everyone wants it.
- **Mastery over collapse.** Developmental writing on children knocking down towers describes the pleasure of *causing* collapse yourself: the child enjoys it only when they do it themselves ([Tinkergarten](http://blog.tinkergarten.com/blog/2017/5/25/destruction-is-good-for-kids)). This is untested folk theory, but it matches the press-channel premise: *you* decide when it breaks. A fixed animation would kill this, so the hinge must be authoritative.
- **Hydraulic Press Channel scale and format.** The channel has 10M+ subscribers and over 6.5B views. YouTube's own write-up calls it a "simple, dramatic destruction of a random object" blending satisfying content and ASMR ([YouTube Culture & Trends](https://blog.youtube/culture-and-trends/hydraulic-press/); [Wikipedia](https://en.wikipedia.org/wiki/Hydraulic_Press_Channel)). The appeal is curiosity ("what will *this* do?"), plain presentation and dry humour. Its early breakout video was a paper-folding test, so the hook is a question, not a spectacle ([Know Your Meme](https://knowyourmeme.com/memes/hydraulic-press-channel)).
- **Unverified pop claims.** The widely repeated "Professor Colombo found serotonin/dopamine release" has no primary source we could find. Discover and Live Science both say direct research is thin ([Live Science](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)). Don't put neuro-claims in marketing.

### 1.2 Predictability versus surprise
Reward prediction-error research gives the rule: fully predicted rewards produce no dopamine response, better-than-expected ones produce a positive response, and uncertainty during the wait ramps anticipation ([review](https://pmc.ncbi.nlm.nih.gov/articles/PMC10116860/); [Fiorillo 2003 commentary](https://www.nature.com/articles/nrn1127)). Each press should therefore be **mostly predictable in its physics**, so the user feels mastery. In SDT research, competence and intuitive controls predict enjoyment ([Ryan, Rigby & Przybylski 2006](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf)). The **details** of each press should vary: exactly where it cracks, how fragments scatter, what's inside. This is the honest version of variable reward. Nothing is bought, nothing is withheld, and every press pays out.

### 1.3 Haptics and sound are half the product
- In a within-subjects study of 38 phone players, vibrotactile embellishments raised enjoyment, aesthetic appeal, immersion and meaning ([Singhal & Schneider, CHI 2021](https://uwaterloo.ca/haptic-experience-lab/projects/juicy-haptic-design-vibrotactile-embellishments-can-improve)). A Korean study found vibration improved hedonic satisfaction, especially when sound is off ([KoreaScience](https://koreascience.or.kr/article/JAKO201326952132747.pdf)). That matters because many people play silently.
- Apple's three audio-haptic principles are **causality** (the user can tell what caused the feedback), **harmony** (sound, haptics and visuals agree) and **utility** ([WWDC21 "Practice audio haptic design"](https://developer.apple.com/videos/play/wwdc2021/10278)).
- Unpacking's 14,000-file foley taught four lessons ([Game Developer](https://www.gamedeveloper.com/marketing/auditory-tales-from-the-making-of-zen-puzzler-unpacking); [NME](https://www.nme.com/news/unpacking-features-over-14000-sound-effect-files-3087521)):
  - keep sounds short so they feel responsive
  - make them **speed-dependent**: the same object sounds different when moved slowly or fast
  - use multiple variants to avoid repetition fatigue
  - give hero objects unique sounds
- Smash Hit's glass breaks where hit rather than at the weakest point, so it is "not realistic", yet it feels great because the feedback is convincing ([Wikipedia](https://en.wikipedia.org/wiki/Smash_Hit)). **Lesson for an AI-only build:** stylised and reliable beats physically accurate.
- **Squish haptic grammar** (Core Haptics):
  - continuous low "strain" rumble whose intensity tracks resistance
  - sharp transients for cracks and pops
  - a big transient at the break
  - a heavy, dull transient at the magnet snap
  - soft double-tap on the cover display ("ready")
  - Map each sound event 1:1 to a haptic event (harmony).

---

## 2. What makes toys and fidget apps sticky

| Product | Hook | Discovery | Mastery | Novelty | Collection | Sharing | Lesson for Squish |
|---|---|---|---|---|---|---|---|
| **Toastie** (Duo, ~£3) | Closing the phone shuts the toaster. The phone pulses each second of cooking; you decide when to stop, then open to see it ([TechRadar](https://www.techradar.com/phones/iphone/apple-iphone-duo-review); [FoldHunt](https://foldhunt.com/iphone-duo/)) | Reveal on reopen | The reviewer needed "half a dozen" tries for an edible sandwich: a skill curve on a toy | Ingredient combos | Implicit | Photo of result | Copy the **closed-phone pulse** and the **reopen reveal**. Add a light, optional skill axis (how slowly you close). |
| **Hydraulic Press Pocket** | 200+ items, press upgrades | Collections | Upgrades | Quantity | Yes | Low | Quantity with free-to-play plumbing (slots, IAP, currency) ([App Store](https://apps.apple.com/app/id1224226281)). We win on **depth per object**, not count. |
| **Pop-it / Antistress apps** | Instant tactile pop | Many mini-toys | None | "New toys every 2 weeks" | Some | Low | Ads are the top complaint ([marlvel](https://marlvel.ai/apps/pop-it-fidget-3d-pop-it-toy/reviews)). A regular update cadence does keep people coming back. |
| **Unpacking** | Item-by-item tactile discovery | Story through objects | Light spatial puzzles | Every item is new | Implicit | Screenshots | Per-object sound personality; reward hero objects ([Game Developer](https://www.gamedeveloper.com/marketing/auditory-tales-from-the-making-of-zen-puzzler-unpacking)) |
| **Townscaper** | Click and a town grows | Emergent shapes | None needed | Procedural | Your towns | Huge (GIFs) | No goal is fine if the output is beautiful and yours ([Bloomberg](https://www.bloomberg.com/news/articles/2020-07-24/the-video-game-where-you-build-an-empty-town)). Procedural output suits an AI-only build. |
| **Let's Create! Pottery** | Tactile shaping | Quests | Sculpting skill | Glazes | Gallery | Sell/auction | Reviewers loved the feel and disliked the unclear economy and feedback ([Common Sense](https://www.commonsensemedia.org/app-reviews/lets-create-pottery-hd); [TouchArcade](https://toucharcade.com/2010/07/19/lets-create-pottery-hd-review-all-the-fun-of-making-pottery-without-the-mess/)). **Do not add a currency.** |
| **Smash Hit** | Glass shatter | Rooms | Aiming | New rooms | — | Moderate | The sight and sound of breaking glass is the whole pitch ([press release](https://pressreleases.triplepointpr.com/2014/02/25/mediocre-to-shatter-the-app-store-and-google-play-with-smash-hit/)) |
| **Other Duo hinge apps** | Inkblotter, Paint & Fold, Bellowsby accordion, ChompDuo, Keep It Shut | — | — | — | — | — | **No crush or press app is listed** in the FoldHunt launch directory ([FoldHunt](https://foldhunt.com/iphone-duo/)). The niche is open, but expect clones within weeks. |

**What these products have in common:**
1. One verb with excellent feel.
2. Each item answers a question ("what will *this* do?").
3. A visible record of what you've done.
4. Occasional new things.
5. Output that is easy to show other people.

Mastery is optional seasoning. Toastie's "stop at the right time" and our "close slowly" are enough.

---

## 3. Progression and collection without IAP

**Principle: every system must either make the next press more interesting or make the record of past presses more pleasing. Cut anything else.**

| Feature | Satisfaction | Friction or build cost | Verdict for v1.0 (4 weeks, 1 AI dev) |
|---|---|---|---|
| **Collection shelf** (flattened results as cards) | High: order, record, "just right" | Low: one screen, auto-generated thumbnails | **Ship** |
| **Variants per object** (procedural crack pattern and colour; golden at 1/50) | High: honest surprise | Low: shader and parameter tweaks | **Ship** |
| **Surprise inside** (piñata, egg: something inside) | Very high: better-than-expected reward | Medium: per object | **Ship on 2 objects** (Egg, Piñata) |
| **"Perfect Squish"** (slow, even close) | Medium: light mastery like Toastie | Low | **Ship as a quiet badge on the card, never a score screen** |
| **Unlocks** | Medium. The endowed-progress effect (34% vs 19% completion with a head start, Nunes & Drèze 2006, [summary](https://siliconcanals.com/t-car-wash-loyalty-cards-endowed-progress/)) suggests starting with most objects open | Low | **Ship: 6 open at start, 4 unlocked by simply playing.** No grind. |
| **Secret object** | High: word-of-mouth, social currency | Low | **Ship 1** |
| **Game Center achievements** | Low–medium; some users love them | Low (config only) | **Ship ~10**, all naturally earned, none requiring days of repetition |
| **Daily object / streaks** | Pull, but streaks are a temporal dark pattern ([Zagal et al.](https://arxiv.org/html/2412.05039v1)) | Medium (needs content) | **No streaks, ever.** Maybe a weekly "featured variant" in v1.2. |
| **Challenges** (exact thickness, slowest close) | Medium, for a minority | Medium (UI, tuning; hinge precision unknown) | **v1.1**, as an optional "Lab" |
| **Stacking two objects** | Very high novelty, emergent stories | High (combinatorial physics) | **v1.2, as the headline free update** |
| **Sandbox** | — | — | Not needed: the core loop *is* the sandbox |
| **Leaderboards** | Low; turns a toy into a competition | Medium | **Never** |

**Update cadence:** a free update of 3–5 objects every 3–4 weeks for the first quarter, then monthly. Pop-it apps that ship every two weeks show the pull of new content. Each update should get one 6-second clip for social and a "What's new" shelf glow, with no push notification.

---

## 4. Onboarding a physical gesture

- **Discover by doing.** Monument Valley opens on a solvable puzzle with almost no text, introducing each mechanic with one or two examples ([Mechanics of Magic](https://mechanicsofmagic.com/2022/05/19/monument-valley-critical-play-2/)). Clear's mandatory 7-page tutorial was criticised as making users work before they had tried anything ([Web Designer Depot](https://webdesignerdepot.com/?p=18293)). Its better idea was list items that teach the remaining gestures in context ([CODE Magazine](https://codemag.com/Article/1509061/All-Aboard-Maximize-Mobile-Engagement-with-Interactive-Onboarding)).
- **The object is the tutorial.** Bubble wrap responds from the first few degrees of closing, so the cause-and-effect lesson takes about 0.5 s.
- **"Slowly" is taught by consequence, not instruction.** Closing fast still works: everything bursts at once in a big rattle. Closing slowly yields a ripple of individual pops plus a "Perfect Squish" sparkle on the card. Users learn that slow is *richer* without being told.
- **Expect two-handed use.** The hinge is stiff enough that reviewers needed two hands to open it ([9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/)). The idle pose should suggest a two-hand grip: a soft glow at both outer edges.
- **Never require reading.** The only text in the first minute is the object name and pop count on the first card.

---

## 5. Session design

- **One press lasts about 8–20 seconds**, a ritual in five beats:
  1. **Choose**, about 2 s
  2. **Place**, about 1 s: the object drops onto the plate with a weighty thud
  3. **Press**, 4–15 s, user-paced
  4. **Snap**, 0.3 s: the magnet thunk
  5. **Reveal**, about 3 s
- **Rest moments:** after the reveal, the plate is empty and quiet for about 1.5 s, with a soft hydraulic hiss as the press "resets". The next object then slides in, pre-chosen but changeable. That gives a gentle "one more" pull without autoplay pressure, and the user has to actively open the phone again.
- **Expected session shape:** 2–5 minutes, 5–15 presses. No session timer and no "come back tomorrow".
- **UI minimalism:** during a press there is zero UI. The plates are the frame. The status bar is hidden.
- **Settings, one sheet only:**
  - Sound (on/off) and Sound style: "Workshop" or "Soft" (ASMR)
  - Haptics (Off / Low / Full)
  - Reduce Motion (follows the system setting by default; [App Store Connect criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria))
  - Press without folding (slider mode)
  - Credits and support
- **Accessibility:**
  - **Motor:** a full alternative to folding, a vertical press slider on the inner display. Hinge-API guidance warns that some people can't or won't fold ([Bleeping Swift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)). Apple advises against requiring specific body movements ([Apple docs](https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app.md)). Slider mode must reach every unlock and achievement.
  - **Vision:** VoiceOver labels for objects ("Rubber duck. Squeaky, rubbery.") and spoken outcomes ("Burst! Confetti inside."). Haptics carry the experience on their own.
  - **Hearing:** haptics plus a brief visual "sound ring" on major events. Apple recommends supplementing visuals with haptics and audio ([HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion.md)).
  - **Reduce Motion:** no camera shake, no slow-mo zoom, and fragments fade rather than fly.
  - **Photosensitivity:** no full-screen white flashes; burst flash below 3 Hz.

---

## 6. Sharing and virality

- **The clip:** an auto-generated 6–10 s vertical (9:16) MP4 with sound, rendered from a replay of the recorded hinge-angle curve. If the simulation is deterministic from seed plus angle curve, the clip re-renders cleanly at 60 fps with slow motion on the break.
  - 0–1 s: title card ("RUBBER DUCK vs SQUISH")
  - 1–6 s: the press, sped up where nothing happens
  - break moment at 0.3× speed
  - final 1 s: the flattened card, traits and a tiny "Squish · iPhone Duo" watermark
- **v1.1 option, the "real hands" picture-in-picture:** opt-in front-camera footage of the fold, which proves you physically folded the phone. This is the novelty factor for TikTok and Reels. Duo camera and occlusion regions are part of the SDK ([eCorpIT](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)), but it adds a permission prompt and scope, so it is not v1.0.
- **Make the share a brag, not an ad:** the clip is about *your* duck, Wordle-style ([Smithsonian](https://www.smithsonianmag.com/smart-news/heres-why-the-word-game-wordle-went-viral-180979439/); [Northeastern](https://news.northeastern.edu/2022/01/21/what-makes-wordle-so-g-r-e-a-t/)). No referral bribes and no "share to unlock", which are social-capital dark patterns.
- **Entry point:** one share icon on the reveal and card detail, through the system share sheet. No SDKs, no accounts, no tracking.
- **Also offered:** a still "before/after" PNG with the object and flattened result side by side, for Messages and Stories.
- **App Store preview:** up to 3 previews of up to 30 s each, autoplaying muted ([Apple](https://developer.apple.com/support/app-previews/)). Average watch time is only about 4–6 s ([AppFollow](https://www.appfollow.io/blog/app-store-video-strategy/)), so the **first 3 s must show a real hand folding a Duo and something bursting**, with no logo intro. Set the poster frame deliberately to a mid-crush frame. Add captions such as "Close your phone. Squish anything." because playback is silent.
- **Name and ASO:** "Squish" is short and memorable but crowded by slime and squishy apps. Recommended App Store name: **"Squish: Fold Press Toy"**, subtitle **"Crush things with your iPhone Duo"**. Keywords: hydraulic press, crush, satisfying, fidget, ASMR, fold, foldable, bubble wrap, smash, stress. Do not use "Hydraulic Press Channel" or Apple marks in the name.

---

## 7. Ethics, age rating and content

- **Dark patterns to avoid**, using the Zagal, Björk & Lewis taxonomy ([summary](https://arxiv.org/html/2412.05039v1); [DiGRA critique](https://eprints.whiterose.ac.uk/156460/1/DiGRA_2020_paper_189.pdf)):
  - **Temporal:** streaks, timers, appointment play
  - **Monetary:** none possible by design; keep it that way and never add a "tip jar" pop-up
  - **Social-capital:** invite-to-unlock
- **Also avoid:**
  - notification nagging; v1 requests no notification permission at all
  - fake rarity (golden odds should be disclosed in Credits: "1 in 50")
  - auto-playing the next press
  - review prompts mid-press. Use `SKStoreReviewController` only after a reveal, at most once, after about 10 presses.
- **Age rating:** Apple's 2025 system has 4+, 9+, 13+, 16+ and 18+ tiers, assigned from a questionnaire ([9to5Mac](https://9to5mac.com/2025/07/24/apple-notifies-developers-of-new-app-store-age-rating-system/)). The founder's audience is 12+. Aim for content that rates **9+** (infrequent mild cartoon violence, mild crude humour), the same tier as Hydraulic Press Pocket ([App Store](https://apps.apple.com/app/id1224226281)). That widens reach while the *tone* stays teen and adult. Edgy humour lives in names and flavour text ("Ex's Mixtape", "Monday", "Tax Return"), never in imagery. If the copy pushes to 13+, that's acceptable, but decide deliberately.
- **Content rules:**
  1. No living creatures, real or cartoon-alive. Toys of animals (rubber duck, piñata) are clearly objects. Never give an object eyes that react with pain.
  2. No body parts, blood or anything that reads as them. Red jam is fine inside a doughnut, but never splattered across a white plate.
  3. Food is fine and toy-like; keep it cartoon-bright, not grossly realistic.
  4. No real brands, flags, religious items or real people.
  5. Glass and sharp fragments stay stylised (chunky, soft-edged, no "cuts").
  6. **Real-world safety:** add a gentle line in the description and a one-time cover-display hint: "Squish works on screen only. Please don't close your phone on real things." The inner display is the most fragile part of the device.

---

## Squish UX spec v0

### A. Core loop

```
        ┌───────────────────────────────────────────────────────────┐
        ▼                                                           │
  [OPEN PHONE] ─► [SHELF: pick object] ─► [PLACE: object drops      │
                        ▲                   onto lower plate]       │
                        │                          │                │
                        │                          ▼                │
                        │          [PRESS: close hinge 180° → 0°]   │
                        │           • deformation = f(angle, speed) │
                        │           • creak sound + strain haptic   │
                        │           • BREAK event at ~25–45°        │
                        │           • magnet SNAP at 0° = THUNK     │
                        │           • cover display: pressure gauge │
                        │             pulses (Toastie-style)        │
                        │                          │                │
                        │                          ▼                │
                        │          [REOPEN: 0° → >90°]              │
                        │           • steam hiss, plates part       │
                        │           • 2 s slow-mo replay of break   │
                        │           • flattened CARD + traits       │
                        │             (Perfect / Golden / Surprise) │
                        │                          │                │
                        │                ┌─────────┴─────────┐      │
                        │                ▼                   ▼      │
                        │        [auto-saved to Shelf]  [SHARE clip]│
                        │                │                          │
                        └──── [next object slides in, changeable] ◄─┘
```

**Angle mapping (tune on hardware):**

| Angle | What happens |
|---|---|
| 180–150° | Plate's shadow approaches; first contact around 150°, tunable per object height |
| 150–45° | Main deformation band |
| 45–25° | Break band |
| 25–0° | Final flatten, mostly hidden by the closing phone |
| 0° | Snap event |

Use hysteresis: reopening slightly does not "un-break". Deformation is monotonic, so the object never re-inflates; this is a press, not a spring.

### B. First-run script, second by second

Precondition: Squish opens on the inner display with the phone flat, at about 180°. No splash text and no permission prompts.

| t | What happens | Sense |
|---|---|---|
| 0.0 s | Black screen. A deep hydraulic *hiss-clunk*. Two brushed-steel plates fade in: the upper plate fills the top half, the lower plate the bottom half, with the fold as the seam. | Sound and a heavy haptic thud |
| 0.8 s | A square of **bubble wrap** drops onto the lower plate, bounces once and settles. | Soft haptic tap on landing |
| 1.5 s | Idle state. A faint **ghost arc** pulses along the hinge, a curved arrow suggesting "fold". Both outer edges glow softly to suggest a two-hand grip. The wrap shimmers. | Visual only |
| 3–6 s | **The user starts closing.** By about 170° the upper plate's shadow darkens the wrap. At about 160° the first bubble pops: a crisp *pop* with a sharp transient. This is the "oh!" moment. The ghost arc fades for good. | Pop sound plus transient |
| 6–12 s | Each further few degrees pops more bubbles in a ripple. Closing slowly gives distinct pops; closing fast gives a rattle-burst. | Rhythm of pops |
| ~40° | The last bubbles go together in a finale volley; the sheet flattens. | Bigger haptic |
| 0° | Magnet snap: a heavy **THUNK** (strong haptic plus low thump). The cover display shows a pressure gauge needle rising and settling. | Thunk |
| +1.5 s closed | The gauge settles. Two light taps and a small "open" glyph on the cover display invite reopening. | Two light taps |
| Reopen | A steam hiss; the plates part. A **2-second slow-motion replay** of the burst plays, then the flattened sheet lifts up as a card: "BUBBLE WRAP · 48 pops". | Release |
| +3 s | The card shrinks into shelf slot 1 of 10 via the bottom handle. The next object, a **rubber duck**, is already waiting on the plate. | "One more" pull |
| Second press | The duck squeaks with rising pitch as it compresses, then *bloops* flat. A second, different reaction teaches that every object behaves differently. | Curiosity |
| After the 2nd press | The shelf handle gives a single gentle bounce, so the user discovers the shelf. | Discovery |

### C. Screen list (4 screens, kept tight for one AI developer)

1. **Press** (the main screen, about 90% of time): plates and object only. Hosts the idle, press, reveal and replay states, plus a pull-up handle.
2. **Shelf** (bottom sheet over Press):
   - Grid of the 10 objects; locked ones show as silhouettes with a one-line hint
   - Tap an object to place it
   - Tabs: *Objects* (best card per object) and *Squished* (your last 200 results)
3. **Card detail** (sheet): flattened result, traits, replay, **Share clip**, **Share image** and Delete.
4. **Settings** (sheet via a small cog on the Shelf): Sound, Sound style, Haptics, Reduce Motion, Press without folding, golden odds disclosure, credits.

**Cover display (closed):** one passive pressure-gauge view, not an interactive screen.

**Deferred:** Lab and Challenges (v1.1), Stack mode (v1.2), the real-hands picture-in-picture (v1.1). Game Center uses system UI only.

### D. Progression recommendation (v1.0)

- **Start state:** 6 objects open (Bubble Wrap, Rubber Duck, Jelly, Crayon, Cake, Egg). Four unlock through play:
  - Squish 3 different things → **Soda Can**
  - Earn a Perfect Squish → **Glass Bottle**
  - Squish 8 times total → **Piñata**
  - Squish all 9 others → **secret object**
  - A typical user unlocks everything in their first or second session (about 10–15 min). This is endowed progress, not grind.
- **Per-press traits** (procedural, cheap):
  - *Perfect Squish*: a smooth close with angle velocity under a threshold and no reversals
  - *Golden*: 1/50, gold material plus chime
  - *Surprise inside*: Egg (1/8 a tiny toy chick, otherwise yolk) and Piñata (5 rotating contents)
  - *Flavour line*: 3–5 witty lines per object
- **Collection:** each object slot shows its best card (Golden beats Perfect beats normal). Completion shows as a quiet "10/10", with no percentage nag.
- **Game Center (~10 achievements):**
  - First Squish
  - Perfectionist (Perfect on 5 objects)
  - Midas (find a Golden)
  - What's Inside? (both surprises)
  - Patience (a press over 30 s)
  - Slam (a press under 1 s)
  - Collector (all 10)
  - The Secret
  - Pop Star (500 bubbles popped)
  - Steady Hands (10 Perfect Squishes)
- **Never:** currency, energy, streaks, leaderboards, notifications, ads, IAP or tip prompts.

### E. Launch objects (10) plus backlog (20)

Chosen to cover distinct **material behaviours**, so each press answers a different "what will it do?" question. All are buildable procedurally by one AI developer: primitive or low-poly meshes, vertex and shader deformation, Voronoi fracture, particles, and synthesized or licensed-library foley. Single art direction: matte, clay-like toy materials under soft studio light on brushed-steel plates.

| # | Object | Behaviour class | Signature moment | Build notes |
|---|---|---|---|---|
| 1 | **Bubble Wrap** (onboarding) | Discrete pops | Ripple of individual pops | Grid of domes, per-cell burst; easiest build, best teacher |
| 2 | **Rubber Duck** | Elastic, then pop-out | Rising squeak, then *bloop* flat | Squash-stretch deform; squeak pitch tied to angle |
| 3 | **Jelly** | Gooey and wobbly | Wobbles, spreads, splorts out the sides; jiggles on reopen | Soft-body spring mesh or metaball shader |
| 4 | **Crayon** | Brittle snap, then smear | Clean SNAP at about 70°, then a waxy colour smear | Two-stage: fracture, then a flattened decal streak |
| 5 | **Cake Slice** | Crumble and squeeze | Frosting oozes out, candle bends over | Layered prism plus crumb particles; flavour: "It wasn't your birthday anyway" |
| 6 | **Egg** | Crack, contents | Hairline cracks spread, then *crack*; yolk spreads; **surprise** 1/8 tiny toy chick | Crack decal plus fluid blob; bright cartoon, no gross-out |
| 7 | **Soda Can** (unlock) | Buckle and fizz | Accordion crumple, fizz spray | Procedural buckling rings plus spray; unbranded |
| 8 | **Glass Bottle** (unlock) | Tension, then shatter | Long creak, then sudden stylised shatter | Voronoi fracture with chunky, soft-edged shards |
| 9 | **Piñata** (unlock) | Burst with contents | Bursts into confetti and sweets; **surprise** contents vary | Low-poly papercraft toy |
| 10 | **Secret: "The Unsquishable"** (an indestructible steel ball bearing) | Comedy subversion | The press strains, the screen shakes, the gauge redlines, and the *press* cracks instead; reopen to a dented plate and the card "Press 0 – Ball 1" | Cheap to build and a great word-of-mouth beat. Avoids trademark risk from a "toy iPhone" idea. |

**Backlog of 20 for free updates**, grouped so each update adds a new behaviour:
- **Gooey:** Slime, Ketchup Sachet (squirt), Toothpaste Tube (one perfect ribbon), Stress Ball, Marshmallow (slow memory-foam rise on reopen)
- **Brittle:** Ice Cube (cracks, then melts on reopen), Fortune Cookie (**surprise** fortune with edgy one-liners), Chocolate Bar (snaps along squares), Dinner Plate, Crisps Packet (pop, then crunch)
- **Contents:** Geode (**surprise** crystal colours), Capsule Toy Egg, Water Balloon, Lava Lamp
- **Elastic and tough:** Tennis Ball, Coil Spring (fights back on reopen), Diamond (refuses to break), Puzzle Cube (pieces spray)
- **Humour (12+):** Alarm Clock (rings until silenced), "Monday" (a calendar page; paper folding homages the press-channel paper test)
- **v1.2 Stack mode:** any two objects layered, e.g. Duck on Cake. This is the headline update.

### F. Sharing feature (v1.0 minimum)

- **Trigger:** a share icon on the reveal and card detail. Never auto-prompted.
- **Output:**
  - 9:16 1080×1920 MP4, 6–10 s, with sound
  - deterministic re-render from the stored angle curve and seed
  - 0.3× slow motion at the break
  - end card with object, traits and a small watermark
  - target under 8 MB
  - plus a before/after PNG
- **Storage:** keep the angle curve and seed for each result (a few KB), not video, so any past card can be re-rendered and shared later.
- **Destination:** the system share sheet only. No SDKs, no account, no analytics on shares.
- **v1.1:** optional "real hands" front-camera picture-in-picture.

---

## Risks and open questions

1. **Hinge feel.** The hinge is stiff and has variable torque, with magnets pulling it shut ([9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/)). A slow, smooth close may feel effortful or jerky, and the last 10–20° may not be under the user's control. Keep all drama above about 25° and **test on hardware in week 1.**
2. **Hinge sample rate and precision are undocumented system policy** ([Bleeping Swift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)). Interpolate between samples and smooth velocity. Avoid mechanics needing exact-degree precision; "crush to exact thickness" may be unreliable, which is one reason Challenges are deferred.
3. **Behaviour while closed.** Content moves to the cover display on close ([eCorpIT](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)). Confirm that the scene keeps running and can drive the cover-display gauge and haptics while folded, as Toastie appears to.
4. **Physical-harm misread.** Users or kids might try real objects. Mitigate with copy and a hint (see section 7).
5. **Novelty decay.** Toys spike and fade. Mitigate with depth per object, honest variance, free updates and Stack mode. Watch week-4 retention.
6. **AI-only art consistency.** One procedural style keeps the pipeline sustainable. Photoreal food or glass would expose the lack of artists.
7. **Name collision and ASO.** "Squish" is crowded; validate search rank and use the descriptive subtitle.
8. **Fast followers.** No crush app is listed for Duo yet ([FoldHunt](https://foldhunt.com/iphone-duo/)), so first-mover status matters, but clones will follow. The moat is feel, sound and update cadence.
9. **Open questions:**
   - Should "Perfect Squish" be visible at all, or does it nudge the toy toward a game? Recommendation: keep it subtle.
   - Should "Soft/ASMR" be marketed as a calm mode?
   - Does edgy flavour text push the rating from 9+ to 13+?
   - Does Apple allow the cover display to show our gauge during the closed state without a Live Activity?
10. **Evidence quality.** Much of the "satisfying" research is thin: small studies, secondary coverage and unverified neuro-claims. Treat the psychology as design heuristics and validate with 5–10 hands-on playtests.

---

## Sources

- [ScienceAlert: Venting doesn't reduce anger (Kjærvik & Bushman 2024)](https://www.sciencealert.com/venting-doesnt-reduce-anger-but-something-else-does-study-says)
- [Simply Psychology: Rage rooms and catharsis](https://www.simplypsychology.com/articles/rage-rooms-catharsis-psychology)
- [Discover: Why are oddly satisfying videos so satisfying?](https://www.discovermagazine.com/why-are-oddly-satisfying-videos-sosatisfying-218)
- [Live Science: Why #OddlySatisfying videos are so satisfying](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)
- [Wikipedia: Oddly satisfying videos](https://en.wikipedia.org/wiki/Oddly_satisfying_videos)
- [Nansen & Balanzategui 2022, Visual tactility (Convergence)](https://journals.sagepub.com/doi/10.1177/13548565221105196)
- [Necsus: Touchscreens, tactility and ASMRtists](https://necsus-ejms.org/touchscreens-tactility-and-material-traces-from-avant-garde-artists-to-instagram-asmrtists/)
- [Revealing Reality: Visceral videos](https://think.revealingreality.co.uk/asmr-page2)
- [UNED: Incompleteness and "not just right" experiences](https://portalcientifico.uned.es/documentos/5eb09ed8299952764113cc38)
- [University of Sheffield: Poerio et al. 2018 ASMR study](https://www.sheffield.ac.uk/psychology/news/brain-tingles-first-study-its-kind-reveals-physiological-benefits-asmr)
- [Packaging Digest: Bubble wrap and stress relief (Dillon)](https://www.packagingdigest.com/packaging-design/bubble-wrap-offers-packaging-protection-stress-relief)
- [Tinkergarten: Why destroying stuff is good for kids](http://blog.tinkergarten.com/blog/2017/5/25/destruction-is-good-for-kids)
- [Review on reward prediction error and intermittent reinforcement (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10116860/)
- [Nature Reviews Neuroscience: commentary on Fiorillo, Tobler & Schultz 2003](https://www.nature.com/articles/nrn1127)
- [Ryan, Rigby & Przybylski 2006: The motivational pull of video games (PDF)](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf)
- [Peak–end rule (Wikipedia)](https://en.wikipedia.org/wiki/Peak%E2%80%93end_rule)
- [Endowed progress effect summary (Nunes & Drèze 2006)](https://siliconcanals.com/t-car-wash-loyalty-cards-endowed-progress/)
- [Singhal & Schneider, Juicy Haptic Design (CHI 2021)](https://uwaterloo.ca/haptic-experience-lab/projects/juicy-haptic-design-vibrotactile-embellishments-can-improve)
- [KoreaScience: vibration and hedonic satisfaction in mobile games](https://koreascience.or.kr/article/JAKO201326952132747.pdf)
- [Apple WWDC21: Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278)
- [Wikipedia: Game feel (Swink)](https://en.wikipedia.org/wiki/Game_feel)
- [Game Developer: Auditory tales from the making of Unpacking](https://www.gamedeveloper.com/marketing/auditory-tales-from-the-making-of-zen-puzzler-unpacking)
- [NME: Unpacking features over 14,000 sound files](https://www.nme.com/news/unpacking-features-over-14000-sound-effect-files-3087521)
- [Wikipedia: Smash Hit](https://en.wikipedia.org/wiki/Smash_Hit)
- [Mediocre: Smash Hit press release](https://pressreleases.triplepointpr.com/2014/02/25/mediocre-to-shatter-the-app-store-and-google-play-with-smash-hit/)
- [YouTube Culture & Trends: Hydraulic Press Channel at 10](https://blog.youtube/culture-and-trends/hydraulic-press/)
- [Wikipedia: Hydraulic Press Channel](https://en.wikipedia.org/wiki/Hydraulic_Press_Channel)
- [Know Your Meme: Hydraulic Press Channel](https://knowyourmeme.com/memes/hydraulic-press-channel)
- [TechRadar: iPhone Duo review (Toastie)](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)
- [9to5Mac: iPhone Duo review (hinge torque, magnets, two-handed opening)](https://9to5mac.com/2026/10/21/iphone-duo-review/)
- [AppleInsider: iPhone Duo review roundup](https://appleinsider.com/articles/26/10/21/iphone-duo-review-roundup-mostly-positive-opinions-unfold)
- [FoldHunt: iPhone Duo apps and games directory](https://foldhunt.com/iphone-duo/)
- [FoldHunt: Laying out around the iPhone Duo fold](https://foldhunt.com/guides/iphone-duo-fold/)
- [Bleeping Swift: onHingeChange in SwiftUI](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)
- [eCorpIT: iPhone Duo SDK explained](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)
- [App Store: Hydraulic Press Pocket](https://apps.apple.com/app/id1224226281)
- [marlvel: Pop It Fidget 3D reviews](https://marlvel.ai/apps/pop-it-fidget-3d-pop-it-toy/reviews)
- [Kill Screen: Give them a toy, not a game (Toca Boca)](https://www.killscreen.com/secret-smart-kids-entertainment-give-them-toy-not-game/)
- [Bloomberg: The video game where you build an empty town (Townscaper)](https://www.bloomberg.com/news/articles/2020-07-24/the-video-game-where-you-build-an-empty-town)
- [Common Sense Media: Let's Create! Pottery HD](https://www.commonsensemedia.org/app-reviews/lets-create-pottery-hd)
- [TouchArcade: Let's Create! Pottery HD review](https://toucharcade.com/2010/07/19/lets-create-pottery-hd-review-all-the-fun-of-making-pottery-without-the-mess/)
- [Mechanics of Magic: Monument Valley critical play](https://mechanicsofmagic.com/2022/05/19/monument-valley-critical-play-2/)
- [Web Designer Depot: How to design gesture-driven UI (Clear)](https://webdesignerdepot.com/?p=18293)
- [CODE Magazine: Interactive onboarding](https://codemag.com/Article/1509061/All-Aboard-Maximize-Mobile-Engagement-with-Interactive-Onboarding)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion.md)
- [App Store Connect: Reduced Motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)
- [Apple: Improving accessibility support (visionOS)](https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app.md)
- [Apple: App previews](https://developer.apple.com/support/app-previews/)
- [AppFollow: App preview video strategy 2026](https://www.appfollow.io/blog/app-store-video-strategy/)
- [Smithsonian: Why Wordle went viral](https://www.smithsonianmag.com/smart-news/heres-why-the-word-game-wordle-went-viral-180979439/)
- [Northeastern: What makes Wordle so great](https://news.northeastern.edu/2022/01/21/what-makes-wordle-so-g-r-e-a-t/)
- [Level Up or Game Over: Dark patterns in mobile games (arXiv)](https://arxiv.org/html/2412.05039v1)
- [DiGRA 2020: critique of the dark-pattern framework](https://eprints.whiterose.ac.uk/156460/1/DiGRA_2020_paper_189.pdf)
- [9to5Mac: Apple's new App Store age ratings](https://9to5mac.com/2025/07/24/apple-notifies-developers-of-new-app-store-age-rating-system/)
