# Squish: Press kit

*Live at **https://pravegm.github.io/squish/press/** (source: `site/press/index.html`; keep the two in step). Full-size assets go on the GitHub Release `press-kit`: https://github.com/pravegm/squish/releases/tag/press-kit (**not created yet**; the press page already links to it). Everything here is **embargo-free**: write about it whenever you like, from the day you receive it.*

---

## The pitch (one paragraph)

**Squish turns your £2,000 phone into a hydraulic press.** Pick a virtual object (bubble wrap, a rubber duck, an egg, a glass bottle) and it sits on the lower half of the iPhone Duo's screen. Push the top half down slowly and the press follows your hand, degree by degree. You see, hear and *feel* the object strain, crack and give way, with every sound and haptic landing in the same frame. Snap the phone shut for a heavy *ka-chunk*, then open it again to find your object flattened, stamped and filed as a pressed specimen in your collection. It also works on every other iPhone: just drag the ram down. Squish costs £2.99 / $2.99, with no ads, no in-app purchases, no timers and no data collected. It's a calm, ridiculous and deeply satisfying toy from a tiny studio, with free object drops planned through the winter.

**One-liner:** *Your £2,000 phone is now a hydraulic press. Pick something on screen, close it slowly, and feel it give.*

---

## Fact sheet

| | |
|---|---|
| **Name** | Squish (App Store: "Squish: Fold-to-Crush Press") |
| **Developer** | Squish, an independent developer (GitHub `pravegm`) |
| **Founder** | [Founder name] (deliberately not on the live page) |
| **Release date** | Tue 24 Nov 2026, worldwide. Pre-order from [~7 Nov 2026] |
| **Platform** | iPhone, designed for iPhone Duo's hinge; drag-to-press (the P-48) on every other iPhone. Requires iOS 18.0 or later (`project.yml` deployment target; the hinge press uses iOS 27.1 APIs, which the Duo ships with) |
| **Price** | £2.99 / $2.99 / €2.99 one-off. No ads, no in-app purchases. Family Sharing on |
| **Age rating** | 9+ |
| **Launch content** | 10 objects: Bubble Wrap, Rubber Duck, Jelly, Crayon, Egg, Cake Slice, Soda Can, Gummy Bear, Glass Bottle, and one secret |
| **Features** | Hinge-driven analogue press · real-time haptics and sound · pressed-specimen collection · Perfect Squish and Golden variants · cover-display "sealed" card · share clip and image · Game Center achievements |
| **Accessibility** | Press without folding · VoiceOver · Reduce Motion · Soft sound mode · haptic levels (Off/Soft/Full) · Captions (on-screen words for sound moments) · flashes under 3 Hz *(not verified in code; left off the live page)* |
| **Privacy** | Data Not Collected. No accounts, no tracking, no third-party SDKs |
| **Size** | ~[XX] MB (target ≤ 80 MB) |
| **Languages** | English |
| **Updates** | Free object drops every 3–4 weeks. Holiday Object Drop in mid-December |
| **Links** | App Store: [link] · Website: https://pravegm.github.io/squish/ · Press page: https://pravegm.github.io/squish/press/ · Full-size assets: https://github.com/pravegm/squish/releases/tag/press-kit · Support: https://pravegm.github.io/squish/support/ |
| **Press contact** | Live page: GitHub Issues (https://github.com/pravegm/squish/issues/new?template=support.yml). [Founder to decide: a press email, which would replace this on the page] |

---

## Key features

- **The hinge is the hand.** Closing the phone drives the press continuously, not as an open/closed switch. Stop halfway and the press stops. Ease off and the ram lifts.
- **Every object fails its own way.** Bubble wrap pops bubble by bubble, the duck's squeak climbs with pressure, the soda can buckles ring by ring, and the glass bottle creaks for a long time before it lets go.
- **You feel it.** A haptic "strain bed" swells as you close, with tiny grains per degree of travel, and the only full-strength jolts are the break and the *ka-chunk*.
- **Ka-chunk, then the reveal.** Closing the phone seals the press, and the cover display shows "PRESS SEALED · 48 TONS · OPEN TO SEE". Reopening plays a slow-motion replay and stamps your specimen card.
- **A collection that rewards care, not speed.** Slow, steady closes earn a quiet Perfect Squish. Slams still work but earn nothing. One press in 50 comes out Golden.
- **Never a slot machine.** No currency, energy, streaks, notifications, ads or purchases.
- **For every iPhone.** Pinch Press runs the same engine on any iPhone, and it's also a full accessibility mode on the Duo.

---

## Founder quote (placeholder; left off the live press page until the founder writes one)

> "[Founder to write in their own words. Suggested angle: the moment the first bubble popped under a real hinge and you laughed out loud. Why it's a toy, not a game. Why no ads.]"
> — [Founder name], founder, [Studio name]

*Draft to edit, or to replace entirely:* "When Apple made a phone that folds, the hinge stopped being a hinge and became a lever. Squish is what happens when you take that literally, slowly. There's nothing to win and nothing to buy. You just close your phone and feel a rubber duck give up."

---

## Asset list (zip: `squish-press-kit.zip`, attached to the `press-kit` GitHub Release)

The live page already shows web-sized copies (≈900 px tall JPEGs in `site/assets/shots/`, from `store.yml` run 39952047687) and a 512 px icon. At minimum the release needs the 1024 icon and the full-size store PNGs from that run; the rest below can follow.

| File | Spec | Notes |
|---|---|---|
| `icon-1024.png` | 1024 × 1024 | A folding phone closing on a rubber duck, hazard-striped edges, on graphite (`Squish/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`) |
| `logo-wordmark.svg` / `.png` | Vector + 2000 px PNG, dark and light | SF Pro Rounded Heavy wordmark (check the font licence for logo use; outline it) |
| `screens-duo-inner-01…06.png` | 2007 × 2853 | Caption-free versions of the App Store frames |
| `screens-duo-outer-01…02.png` | 1398 × 2034 | Cover display |
| `screens-iphone-01…06.png` | 1320 × 2868 | Pinch Press |
| `trailer-30s.mp4` | 1080 × 1920 and 1920 × 1080, with sound | The App Preview cut plus a landscape version for YouTube embeds |
| `teaser-15s.mp4` | 1080 × 1920 | Social teaser with real hands (`preview-video.md` §B) |
| `broll-raw-*.mp4` | 1080 × 1920, no captions | One clip per object (6–10 s), rendered by the share-clip renderer |
| `gif-duck.gif`, `gif-bubblewrap.gif`, `gif-glass.gif` | ≤ 8 MB, 600 px wide | For live blogs and Slack |
| `specimen-cards/*.png` | 2000 px | Pressed specimen cards for all 9 public objects (not the secret) |
| `hands-on-photos/*.jpg` | 4000 px | Duo in tabletop pose, screen visible, nothing physical between the halves |
| `factsheet.pdf` | 1 page | This fact sheet |

**Never include** the secret object, Hydraulic Press Channel imagery, or any shot with real objects between the halves.

**Embargo-free launch note (put at the top of the press page):** *No embargo. Everything on this page is free to use now with a link to the App Store. Need a promo code, a TestFlight invite or a different format? Email [press email] and you'll hear back the same day.* (Live page today: "Need something else, such as a different format? Get in touch", linking to the GitHub support form, with no promo-code or same-day promise until there's a private channel.)

**Promo codes:** App promo codes are still available for paid app downloads (Apple retired the in-app purchase promo codes in March 2026, which doesn't affect us). Generate them in App Store Connect after approval. **Check the current per-version cap and expiry there**: historically 100 codes per version, valid 28 days. Track every code issued in a sheet (who, when, outlet).

---

## Pitch emails

General rules:
- Plain text. Clip link in the first two lines. Under 150 words.
- One follow-up after 4–5 days, then stop.
- Never attach large files; link to a page.
- Send tip-line emails **this week** (claim the idea), then a launch note on release day.

> Addresses marked [verify] come from older public listings. Check each site's current "tips" or "contact" page before sending.

### 1. Tip lines: TechCrunch, MacRumors, 9to5Mac
*To: tips@techcrunch.com / tips@macrumors.com / tips@9to5mac.com [verify] · send separately, never CC'd*

**Subject:** Tip: someone turned the iPhone Duo into a hydraulic press (15s clip)

> Hi [Outlet] team,
>
> 15-second clip: [link]
>
> I'm building **Squish**, an iPhone Duo toy where the hinge works as a hydraulic press. Pick a virtual object, push the top half down slowly, and it strains, cracks and gives way in sync with your hand, with matching haptics and sound. Close it for a "ka-chunk", reopen to find a pressed specimen card.
>
> - On every iPhone (drag to press); the Duo is the hero.
> - £2.99/$2.99, no ads, no IAP, no data collected.
> - Pre-order [~7 Nov], launch [24 Nov].
>
> Happy to send TestFlight, hi-res clips, or a quote. No embargo.
>
> [Founder name], [Studio name]
> https://pravegm.github.io/squish/press/

### 2. Digital Trends: Vikhyaat Vivek (wrote "The iPhone Duo has developers going wild", 10 Oct 2026)
*To: [find via Digital Trends author page / X / Muck Rack]*

**Subject:** One for the "developers going wild" pile: the Duo as a hydraulic press

> Hi Vikhyaat,
>
> Your piece on Duo developers (Duo-Man, Accorduon, Twofold) was the one that made me feel like it's 2009 on the App Store again. I liked your point that the best ones make the hinge *part of the interaction*, not just a layout trick.
>
> So: **Squish** makes the hinge the whole interaction. The phone is a hydraulic press. A virtual object sits on the lower screen, and as you close the top half the press follows your hand, degree by degree: bubble wrap pops bubble by bubble, a rubber duck's squeak climbs with the pressure, glass creaks before it goes. Snap it shut, reopen, and the result is stamped as a pressed specimen.
>
> 20s clip: [link] · TestFlight: [link]
> £2.99/$2.99, no ads, no IAP, launching [24 Nov]. It also runs on non-Duo iPhones.
>
> Happy to talk about how we map hinge angle to "pressure" and haptics, or anything else.
>
> [Founder name]

*(Founder decision: he was sceptical of "vibe-coding" as a standard. If the build process comes up, be straightforward about it rather than vague. See the open question in the summary.)*

### 3. PocketGamer / TouchArcade
*To: PocketGamer reviews/news desk [verify on pocketgamer.com contact page] · TouchArcade: "Submit a Tip" link / staff email at the bottom of the forums [verify]; also post a dev thread in TouchArcade's forums, identifying yourself as the developer*

**Subject:** Squish: a premium, ad-free crush toy for iPhone Duo (and every iPhone). Pre-order now

> Hi [name],
>
> Crush games on iOS are mostly ad farms that haven't been updated in years. **Squish** is the opposite: a £2.99/$2.99 toy with no ads, no IAP, no energy and no timers, where each object breaks its own way and you feel it through the haptics.
>
> On iPhone Duo, closing the phone *is* the press: the crush follows the hinge in real time, then a "ka-chunk" seals it and you reopen to a pressed specimen card. On other iPhones you drag the ram down.
>
> - 10 objects at launch, including one secret that doesn't behave
> - Perfect Squish (slow, steady closes) and 1-in-50 Golden variants, plus a collection shelf
> - Game Center achievements, full accessibility mode
> - Pre-order: [link] · Launch [24 Nov] · Free holiday object drop in December
>
> Trailer: [link] · Promo code or TestFlight on request.
>
> [Founder name], [Studio name]

### 4. Duo creator (TikTok / YouTube / Shorts)
*To: [creator business email from bio] · only creators who already own a Duo and post "apps you need" or "weird apps" content*

**Subject:** A free code for Squish: the Duo becomes a hydraulic press

> Hey [name],
>
> Loved your [specific video] (the [specific moment] got me).
>
> I make **Squish**: your Duo becomes a hydraulic press. Put a virtual egg on the bottom screen, close the phone slowly, and feel it crack in your hand, then *ka-chunk*. It reads really well on camera from a three-quarter overhead angle.
>
> Here's a free code: **[promo code]** (redeem in the App Store by [expiry date]). No strings attached: no script, no obligation to post. If you do make something:
> - Raw caption-free clips and a 10s hook you can drop in: [link]
> - Please keep everything on screen. No real objects between the halves (we're careful about that one).
> - If you post, a "gifted" tag keeps everyone right with the platform rules.
>
> The secret 10th object makes a good reveal if you get that far. I won't spoil it.
>
> Thanks either way!
> [Founder name], Squish

---

## Sources

- Digital Trends, "The iPhone Duo has developers going wild and I'm loving their creations", Vikhyaat Vivek, 10 Oct 2026: https://www.digitaltrends.com/phones/the-iphone-duo-has-developers-going-wild-and-im-loving-their-creations/
- Promo-code change (IAP promo codes retired 26 Mar 2026; app download codes remain): https://www.bgr.com/2011787/apple-retire-in-app-purchase-promo-codes/ · https://9to5mac.com/?p=1025773
- TouchArcade submission advice (staff email, forum dev threads; identify yourself as the developer): https://toucharcade.com/community/threads/where-do-we-submit-our-games-to-touch-arcade-to-possibly-be-reviewed.300756/
- Market context (Toastie, Duo-Man coverage path, ad-farm competitors): `research/06-market.md`