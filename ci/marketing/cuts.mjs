// The Reels / ad cuts (docs/marketing/PLAN.md §0, the authoritative brief), as data for ci/marketing/compose.mjs.
// Edit here and re-run `bash ci/marketing.sh compose` (or marketing.yml with record=false): no re-recording needed.
//
// Times are seconds in the finished cut, or references:
//   "<seg>:<mark>±s"  a mark of segment <seg>'s clip, where it lands in the cut (e.g. "0:failure+0.2");
//   "<seg>:start±s" / "<seg>:end±s"  that segment's ends;  "end-1.5"  from the end of the cut.
// Segment `from` / `to` are clip marks ("failure-3.0", comma fallbacks, as in ci/preview-lib.sh), `dur` fixes the length
// (`to` then only caps it), `maxDur` caps a `to`.
// Layouts (compose.mjs LAYOUTS): duo (the whole inner display, tabletop), anvil (tight on the object on the lower half),
// anvil-wide, slomo (the SLO-MO film over the anvil), book, p69 (the P-48 machine), cover (the sealed card).
// Text: `*word*` is the one hydraulic-yellow word. Lowercase, deadpan, ≤ 6 words for hooks (§0.1).
// Real-hand slots: a segment with `real: "S4"` uses the founder's shot (footage/S4.mp4 or .mov, optional footage/S4.in
// holding the start second) instead of the simulator clip, at the same length, when the file exists (SHOOT-GUIDE.md).
// Variants: every cut renders `organic` (no price; loops; small end pill) and `ad-uk` / `ad-us` (a 1.5 s card, which
// may carry the price). Text fields may be { organic, "ad-uk", "ad-us", default } to differ per variant.

export const FINE = "everything's on screen. nothing real goes inside.";
export const PRICE = { "ad-uk": "£2.49 · no ads · no in-app purchases", "ad-us": "$2.49 · no ads · no in-app purchases" };
export const OUT_NOW = "out now on the App Store";

// The ka-chunk: the P-48's seal (the Duo's comes on the magnet clap, which the scripted hinge never makes).
const KACHUNK = { clip: "p-can", from: "phase-sealed-0.12", dur: 1.3, gain: 0 };

export const CUTS = [
  {
    id: "c1-glass", concept: "C1", title: "it creaks. then it doesn't.", length: 11, week: "launch",
    use: "Organic Reel (teaser, Post 0) and Meta ad. Object first, then the phone.",
    caption: "A glass bottle. A slow press. A very long creak.",
    hook: "it *creaks*.",
    lines: [{ text: "then it *doesn't*.", from: "0:failure+0.0", to: "0:failure+1.8" }],
    segments: [
      { clip: "d-glass", from: "failure-3.0", dur: 3.8, layout: "anvil", real: "S1" },
      // The SLO-MO film replays the press at 0.35×; its break lands ~1.15 s before the film ends (marketing run 40309703073).
      { clip: "d-glass", from: "slomo-end-2.4", dur: 1.9, layout: "slomo", audio: "slomo", slomoAt: "slomo-end-1.15" },
      // The pull-back to the phone: the 112° render (the hero render draws the glass's cracked print on the upper screen,
      // which could read as a cracked phone: CrackGate). Replaced by the founder's S2 when it exists.
      { still: "store/glassBottle-storeshot-112.png", crop: [0, 0.27, 1, 0.70], dur: 1.1, kb: [1.1, 1.0],
        audio: { clip: "d-glass", from: "failure+0.6" }, fine: true, real: "S2" },
      { clip: "p-cover-glass", from: "origin+3.85", dur: 1.5, layout: "pcover", sfx: [KACHUNK], fine: true, real: "S7" },
      { clip: "d-glass", from: "reveal-0.2", dur: { organic: 2.3, default: 2.0 }, layout: "reveal" },
      { clip: "d-glass", from: "failure-3.7", dur: 0.6, layout: "anvil", only: "organic", loop: true },
    ],
    end: { organic: { line: OUT_NOW, fine: true }, ad: { line: OUT_NOW, fine: true } },
    cover: "0:failure+0.5",
  },
  {
    id: "c2-duo-flex", concept: "C2", title: "my £2,000 hydraulic press", length: 15, week: "launch",
    use: "Launch-day Reel (Post 1) and the £2,000-joke ad. Real hands later: S4, S6, S7, S11.",
    caption: "Close it slowly. Feel it give. Ka-chunk.",
    hook: { default: "my *£2,000* hydraulic press", "ad-us": "my *$2,000* hydraulic press" },
    lines: [
      { text: "*slowly*…", from: "0:failure-0.2", to: "0:failure+1.0" },
      { text: "*ka-chunk*.", from: "1:start+0.1", to: "1:end-0.1" },
    ],
    segments: [
      { clip: "d-egg", from: "failure-3.9", to: "script-58+0.3", maxDur: 5.6, layout: "anvil", real: "S4" },
      { clip: "p-cover-egg", from: "origin+3.85", dur: 2.0, layout: "pcover", sfx: [KACHUNK], real: "S6" },
      { clip: "d-egg", from: "reveal-0.2", dur: 1.8, layout: "reveal", real: "S7" },
      { clip: "d-egg", from: "slomo-end-2.3", dur: 1.5, layout: "slomo", audio: "slomo", slomoAt: "slomo-end-1.15" },
      { clip: "d-duck", from: "failure-0.45", dur: 0.7, layout: "anvil" },
      { clip: "d-bubble", from: "failure-0.45,fracture-20-0.3", dur: 0.7, layout: "anvil" },
      { clip: "d-can", from: "failure-0.45", dur: 0.7, layout: "anvil" },
      { clip: "d-cake", from: "failure-0.45", dur: 0.7, layout: "anvil" },
      { clip: "d-egg", from: "failure-4.7", dur: 0.8, layout: "anvil", only: "organic", loop: true },
    ],
    end: {
      organic: { line: OUT_NOW, fine: true },
      ad: { headline: { default: "£2,000 phone. *£2.49* press.", "ad-us": "$2,000 phone. *$2.49* press." },
        line: "no ads · no in-app purchases", price: "", fine: true },
    },
    cover: "2:start+1.3",
  },
  {
    id: "c3-bubbles", concept: "C3", title: "24 bubbles. one at a time.", length: 9, week: "launch",
    use: "ASMR loop Reel (Post 2, sound on) and the ASMR ad. Organic has no end card: a corner wordmark only.",
    caption: "Slow for a ripple. Fast for a rattle. Either way, ka-chunk. Sound on.",
    hook: "*24* bubbles. one at a time.",
    watermark: "organic",
    segments: [
      { clip: "d-bubble", from: "fracture-1-0.3", to: "failure+0.7,fracture-24+0.7,script-58+0.3", maxDur: 7.3, layout: "anvil", real: "S3" },
      { clip: "d-bubble", from: "reveal-0.1", dur: 1.2, layout: "reveal" },
      { clip: "d-bubble", from: "fracture-1-0.8", dur: 0.5, layout: "anvil", only: "organic", loop: true },
    ],
    end: { organic: null, ad: { line: OUT_NOW } },
    cover: "0:start+3.0",
  },
  {
    id: "c4-every-iphone", concept: "C4", title: "no foldable? drag it.", length: 10, week: "launch",
    use: "THE main ad cut (every iPhone), and Post 4. The finger is a touch indicator until the founder's S10.",
    caption: "Not everyone spent £2,000 on a phone. On any iPhone, the P-48 press sits under your finger.",
    hook: "no foldable? *drag* it.", hookY: 362, endY: 380,
    touch: { seg: 0, clip: "p-can", slow: 5, y0: 0.405, y1: 0.765, until: "0:failure+0.5" },
    segments: [
      { clip: "p-can", from: "phase-pressing-0.3", to: "failure+0.8", maxDur: 5.0, layout: "p69", real: "S10" },
      // The P-48's specimen card lands ~1.8 s after the reveal mark (the ram lifts first).
      { clip: "p-can", from: "reveal+1.5", dur: { organic: 2.0, default: 1.7 }, layout: "p69card" },
      { clip: "p-duck", from: "failure-0.45", dur: 0.7, layout: "p69" },
      { clip: "p-jelly", from: "failure-0.45,phase-sealed-0.6", dur: 0.7, layout: "p69" },
      { clip: "p-cake", from: "failure-0.45,phase-sealed-0.6", dur: 0.7, layout: "p69" },
      { clip: "p-can", from: "phase-pressing-0.9", dur: 0.6, layout: "p69", only: "organic", loop: true },
    ],
    end: {
      organic: { line: "works on every iPhone. made for the *fold*." },
      ad: { headline: "works on every iPhone. made for the *fold*.", line: "no ads · no in-app purchases",
        price: { "ad-uk": "£2.49", "ad-us": "$2.49" } },
    },
    cover: "0:start+2.6",
  },
  {
    id: "c5-lineup", concept: "C5", title: "which one goes first?", length: 15, week: "launch",
    use: "Comment-prompt Reel (Post 3) and the line-up ad. No phone in frame: app renders only.",
    caption: "Glass bottle, jelly, soda can, rubber duck. Comment your order, 1 to 4.",
    hook: "which one goes *first*?",
    lines: [{ text: "comment your *order*.", from: "5:start+0.2", to: { organic: "end-1.55", default: "end-0.05" }, y: 380 }],
    numbers: true,
    hookY: 380, hookSize: 72, endY: 380,
    segments: [
      { grid: [
        { clip: "d-glass", from: "script-begin+0.6" }, { clip: "d-jelly", from: "script-begin+0.6" },
        { clip: "d-can", from: "script-begin+0.6" }, { clip: "d-duck", from: "script-begin+0.6" }],
        dur: 1.5, layout: "anvil", audio: { clip: "d-glass", from: "script-begin+0.6" } },
      { clip: "d-glass", from: "failure-1.8", dur: { organic: 2.7, default: 2.5 }, layout: "anvil", number: 1 },
      { clip: "d-jelly", from: "failure-1.8,phase-pressing+2.0", dur: { organic: 2.7, default: 2.5 }, layout: "anvil", number: 2 },
      { clip: "d-can", from: "failure-1.8", dur: { organic: 2.7, default: 2.5 }, layout: "anvil", number: 3 },
      { clip: "d-duck", from: "failure-1.8", dur: { organic: 2.7, default: 2.5 }, layout: "anvil", number: 4 },
      { grid: [
        { clip: "d-glass", from: "reveal+1.3" }, { clip: "d-jelly", from: "reveal+1.3" },
        { clip: "d-can", from: "reveal+1.3" }, { clip: "d-duck", from: "reveal+1.3" }],
        dur: { organic: 2.7, default: 1.9 }, layout: "reveal", audio: { clip: "d-duck", from: "reveal+1.3" } },
    ],
    end: { organic: { line: "10 objects. all break *differently*.", at: "end-1.5" }, ad: { line: "10 objects. all break *differently*." } },
    cover: "0:start+0.9",
  },
  {
    id: "c6-fights-back", concept: "C6", title: "this one fights back.", length: 10, week: "week 3+",
    use: "WEEK 3+ ONLY (founder approved 26 Oct). The secret steel ball: the P-48's yellow ram cracks, never the phone.",
    caption: "There is a tenth object. It does not squish. Press the other nine to meet it.",
    hook: "this one *fights back*.",
    segments: [
      { clip: "p-ball", from: "phase-pressing-0.5", to: "failure-0.4", maxDur: 4.4, layout: "p69", real: "S9" },
      // The moment it fights back, close on the ram: the crack is the machine's, on its yellow ram and plate.
      { clip: "p-ball", from: "failure-0.4", dur: 1.8, layout: "p69-ram" },
      { clip: "p-ball", from: "reveal+1.5", dur: { organic: 2.6, default: 2.2 }, layout: "p69card" },
      // No Duo pull-back yet: the Duo's reveal draws the press damage as crack lines on the upper screen, which would read
      // as a cracked phone (CrackGate). The founder's S9 (phone open and intact) goes here.
      { clip: "p-ball", from: "phase-pressing-1.1", dur: 0.6, layout: "p69", only: "organic", loop: true },
    ],
    end: { organic: { line: "find the other *nine* first." }, ad: { line: "find the other *nine* first." } },
    cover: "1:failure+0.5",
  },
];

// Story clips (docs/marketing/COPY.md §3): 9:16 with the Stories keep-clear bands and room for the stickers the founder
// adds in Instagram. `sticker` reserves an empty box (and draws it on the -guide frame only).
export const STORY_CUTS = [
  { id: "story-1-1-its-out", from: "c2-duo-flex", variant: "organic", hook: "it's *out*.", lines: [], noEnd: true,
    use: "Story sequence 1, frame 1 (no sticker)." },
  { id: "story-1-3-every-iphone", from: "c4-every-iphone", variant: "organic", hook: null, lines: [], noEnd: true,
    sticker: { kind: "emoji slider", text: "how satisfying?", box: [140, 1020, 800, 230] },
    use: "Story sequence 1, frame 3: add the emoji slider 🗜️ \"how satisfying?\" in the reserved space." },
  { id: "story-2-4-glass-answer", from: "c1-glass", variant: "organic", hook: null, lines: [], noEnd: true, segments: [0, 1, 4],
    use: "Story sequence 2, frame 4: the answer to the quiz (the glass bottle has the longest creak)." },
  { id: "story-3-3-gentle-close", variant: "organic", noEnd: true, use: "Story sequence 3, frame 3 (until the founder's S2).",
    hook: null, lines: [{ text: "a gentle close. *always*.", from: 0.3, to: "end-0.2", y: 430 }],
    segments: [{ clip: "d-glass", from: "script-begin-0.3", to: "script-58+0.3", maxDur: 7.5, layout: "anvil", real: "S2", fine: true }] },
];
