#!/usr/bin/env node
// The still half of the kit (docs/marketing/PLAN.md §0, COPY.md §1–3): the launch carousel and three single posts
// (1080 × 1350, 4:5), the Story stills (1080 × 1920, with empty space kept for Instagram's own stickers, plus a -guide
// copy that marks it), the profile picture and five Story highlight covers. HTML/CSS through ci/marketing/render.mjs
// (Nunito Black, headless Chrome), on the app's real pictures: stills from the recorded clips, the App Store renders
// (FoldStoreShot) and Squish/Resources/ObjectArt.
//
//   node ci/marketing/statics.mjs --clips <dir> [--clips <dir>…] --assets <dir> --out <dir>
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as R from "./render.mjs";
import { FINE, PRICE, OUT_NOW } from "./cuts.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "../..");
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const OUT = path.resolve(opt("--out", "marketing-kit"));
const ASSETS = path.resolve(opt("--assets", "marketing-assets"));
const CLIP_DIRS = args.flatMap((a, i) => (a === "--clips" ? [path.resolve(args[i + 1])] : []));
const FW = 1080, FH = 1350, SW = 1080, SH = 1920;
const problems = [];
const made = [];
const FRAMES = path.join(OUT, "_work", "stills");
fs.mkdirSync(FRAMES, { recursive: true });

// ---- pictures --------------------------------------------------------------------------------------------------------
function imageSize(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32BE(0) === 0x89504e47) return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  let i = 2;
  while (i < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return { w: b.readUInt16BE(i + 7), h: b.readUInt16BE(i + 5) };
    i += 2 + b.readUInt16BE(i + 2);
  }
  return { w: 1, h: 1 };
}
const clips = new Map();
for (const dir of CLIP_DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".marks.txt"))) {
    const name = f.slice(0, -10), marks = new Map();
    for (const l of fs.readFileSync(path.join(dir, f), "utf8").split("\n")) {
      const [k, v] = l.trim().split(/\s+/); if (k && v !== undefined && !marks.has(k)) marks.set(k, parseFloat(v));
    }
    clips.set(name, { file: path.join(dir, name + ".mov"), marks });
  }
}
/** A still from a recorded clip at "<mark>±s" (comma fallbacks), as PNG; null when the clip or mark is missing. */
function still(clip, spec, label) {
  const c = clips.get(clip);
  if (!c || !fs.existsSync(c.file)) { problems.push(`still ${label}: clip ${clip} missing`); return null; }
  let t = null;
  for (const alt of spec.split(",")) {
    const m = alt.match(/^(.+?)(?:([+-])([0-9.]+))?$/);
    if (m && c.marks.has(m[1])) { t = c.marks.get(m[1]) + (m[3] ? parseFloat(m[3]) * (m[2] === "-" ? -1 : 1) : 0); break; }
  }
  if (t === null) { problems.push(`still ${label}: ${clip} has no mark ${spec}`); return null; }
  const out = path.join(FRAMES, `${label}.png`);
  const r = spawnSync("ffmpeg", ["-nostdin", "-y", "-v", "error", "-ss", Math.max(0, t).toFixed(3), "-i", c.file, "-frames:v", "1", "-update", "1", out]);
  if (r.status !== 0 || !fs.existsSync(out)) { problems.push(`still ${label}: ffmpeg failed`); return null; }
  return out;
}
const asset = (rel) => { const f = path.join(ASSETS, rel); if (fs.existsSync(f)) return f; problems.push(`asset ${rel} missing`); return null; };
const art = (kind, state = "rest") => path.join(REPO, "Squish/Resources/ObjectArt", `objectart-${kind}-${state}.jpg`);

/**
 * A picture cropped into a box: `crop` = [x, y, w, h] fractions of the source, scaled to cover the box (so the crop's
 * centre is the box's centre). Returns an absolutely positioned <div> with the <img> inside.
 */
function pic(file, { x, y, w, h, crop = [0, 0, 1, 1], radius = 0, shadow = false, extra = "", fit = "cover", feather = 0 }) {
  if (!file) return `<div style="position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;background:#ddd6cb;border-radius:${radius}px"></div>`;
  const { w: iw, h: ih } = imageSize(file);
  const [cx, cy, cw, ch] = crop;
  const cropW = cw * iw, cropH = ch * ih;
  const s = fit === "cover" ? Math.max(w / cropW, h / cropH) : Math.min(w / cropW, h / cropH);
  const dw = iw * s, dh = ih * s;
  const left = w / 2 - (cx + cw / 2) * dw, top = h / 2 - (cy + ch / 2) * dh;
  return `<div style="position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;overflow:hidden;border-radius:${radius}px;${feather ? featherCSS(feather) : ""}${shadow ? "box-shadow:0 22px 50px rgba(30,28,25,.28),0 0 0 2px rgba(43,45,49,.06);" : ""}${extra}">
    <img src="${R.fileURL(file)}" style="position:absolute;left:${left.toFixed(1)}px;top:${top.toFixed(1)}px;width:${dw.toFixed(1)}px;height:${dh.toFixed(1)}px;max-width:none"></div>`;
}

/** Soft edges, so a render's own backdrop melts into the page instead of showing a box. */
const featherCSS = (f) => `-webkit-mask-image:linear-gradient(to right,transparent 0,#000 ${f}px,#000 calc(100% - ${f}px),transparent 100%),linear-gradient(to bottom,transparent 0,#000 ${f}px,#000 calc(100% - ${f}px),transparent 100%);-webkit-mask-composite:source-in;mask-composite:intersect;`;

// ---- page chrome --------------------------------------------------------------------------------------------------------
const icon = asset("icon.png");
function page(w, h, body, { bg = "var(--paper)", extraCSS = "" } = {}) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${R.baseCSS()}
  body{width:${w}px;height:${h}px;position:relative;overflow:hidden;background:${bg};}
  .grain{position:absolute;inset:0;background:radial-gradient(1200px 900px at 50% 30%,rgba(255,252,246,.9),rgba(243,238,230,0) 70%);}
  .band{position:absolute;left:0;right:0;height:22px;background:repeating-linear-gradient(-45deg,var(--graphite) 0 22px,var(--yellow) 22px 44px);}
  .h{position:absolute;color:var(--graphite);line-height:1.04;letter-spacing:-.012em;}
  .s{position:absolute;color:#4a4741;font-weight:800;line-height:1.2;}
  .mark{position:absolute;display:flex;align-items:center;gap:14px;font-size:40px;letter-spacing:-.01em;}
  .mark img{width:60px;height:60px;border-radius:14px;box-shadow:0 4px 10px rgba(0,0,0,.2);}
  .fine{position:absolute;left:0;right:0;text-align:center;font-size:26px;font-weight:800;color:#6a665f;}
  .pill{display:inline-block;padding:14px 30px 18px;border-radius:999px;background:var(--yellow);font-size:38px;}
  .tag{position:absolute;padding:8px 18px 11px;border-radius:999px;background:var(--graphite);color:var(--paper);font-size:30px;}
  ${extraCSS}</style></head><body><div class="grain"></div>${body}</body></html>`;
}
const wordmark = (x, y) => `<div class="mark" style="left:${x}px;top:${y}px">${icon ? `<img src="${R.fileURL(icon)}">` : ""}<span>squish</span></div>`;
const headline = (text, { x = 84, y = 96, w = 912, size = 92, lines = 3 } = {}) =>
  `<div class="h fit" data-max="${size}" data-min="44" data-lines="${lines}" style="left:${x}px;top:${y}px;width:${w}px;font-size:${size}px">${R.rich(text)}</div>`;
const sub = (text, { x = 84, y, w = 912, size = 38 } = {}) =>
  `<div class="s fit" data-max="${size}" data-min="26" data-lines="3" style="left:${x}px;top:${y}px;width:${w}px;font-size:${size}px">${R.rich(text)}</div>`;

/** A dashed, labelled box where the founder drops an Instagram sticker (guide copies only). */
const stickerBox = ([x, y, w, h], label, guide) => guide
  ? `<div style="position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;border:5px dashed #D7263D;border-radius:28px;
      display:flex;align-items:center;justify-content:center;color:#D7263D;font-size:34px;background:rgba(215,38,61,.06)">${label}</div>` : "";
/** The Stories keep-clear bands (guide copies only). */
const storyBands = (guide) => guide
  ? `<div style="position:absolute;left:0;top:0;width:${SW}px;height:270px;background:rgba(215,38,61,.18)"></div>
     <div style="position:absolute;left:0;bottom:0;width:${SW}px;height:384px;background:rgba(215,38,61,.18)"></div>` : "";

// ---- the designs ---------------------------------------------------------------------------------------------------------
const OBJECTS = [["bubbleWrap", "bubble wrap"], ["rubberDuck", "rubber duck"], ["jelly", "jelly"], ["crayon", "crayon box"],
  ["egg", "egg"], ["cakeSlice", "cake slice"], ["sodaCan", "soda can"], ["gummyBear", "gummy bear"], ["glassBottle", "glass bottle"]];

function objectGrid({ state, y0, tile = 170, gap = 16, cols = 5, x0 }) {
  const items = [...OBJECTS.map(([k, n]) => ({ k, n })), { secret: true, n: "???" }];
  const totalW = cols * tile + (cols - 1) * gap;
  const left = x0 ?? Math.round((FW - totalW) / 2);
  return items.map((it, i) => {
    const x = left + (i % cols) * (tile + gap), y = y0 + Math.floor(i / cols) * (tile + 70 + gap);
    const img = it.secret
      ? `<div style="position:absolute;left:${x}px;top:${y}px;width:${tile}px;height:${tile}px;border-radius:30px;background:#e6dfd3;display:flex;align-items:center;justify-content:center;box-shadow:inset 0 3px 8px rgba(0,0,0,.12)"><div style="width:${tile * 0.42}px;height:${tile * 0.42}px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#f5f2ec,#c9c3b8)"></div></div>`
      : pic(art(it.k, state), { x, y, w: tile, h: tile, crop: [0.12, 0.12, 0.76, 0.76], radius: 30, extra: "background:#f2ede6;box-shadow:0 8px 20px rgba(30,28,25,.14);" });
    return `${img}<div style="position:absolute;left:${x - 10}px;top:${y + tile + 12}px;width:${tile + 20}px;text-align:center;font-size:27px;line-height:1.05;color:var(--graphite)">${it.n}</div>`;
  }).join("");
}

async function main() {
  const b = await R.browser();
  const out = (rel) => { const f = path.join(OUT, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); made.push(rel); return f; };
  const render = (html, rel, w, h) => b.png(html, out(rel), { width: w, height: h, transparent: false });

  // Pictures from this run's clips (Duo tabletop 2006 × 2852; P-48 1320 × 2868) and the store renders.
  const S = {
    shelf: still("d-shelf", "shelffill-done+1.6", "shelf-full"),
    eggCard: still("d-egg", "reveal+2.2", "egg-card"),
    glassCard: still("d-glass", "reveal+2.2", "glass-card"),
    open: still("d-glass", "script-begin+0.3", "glass-open"),
    closing: still("d-glass", "failure-1.2", "glass-closing"),
    glassIdle: still("d-glass", "script-begin+0.3", "glass-idle"),
    jellyIdle: still("d-jelly", "script-begin+0.3", "jelly-idle"),
    canIdle: still("d-can", "script-begin+0.3", "can-idle"),
    duckIdle: still("d-duck", "script-begin+0.3", "duck-idle"),
    p48: still("p-duck", "failure-0.9", "p48-duck"),
    glassStrain: still("d-glass", "failure-0.7", "glass-strain"),
    glassGone: still("d-glass", "failure+0.45", "glass-gone"),
    p48can: still("p-can", "failure-0.6", "p48-can"),
  };
  const ST = {
    heroDuck: asset("store/rubberDuck-storeshot-hero.png"),
    heroGlass: asset("store/glassBottle-storeshot-hero.png"),
    pairCan: asset("store/sodaCan-storeshot-pair.png"),
    revealDuck: asset("store/rubberDuck-storeshot-reveal.png"),
    open112: asset("store/glassBottle-storeshot-112.png"),
  };
  // Crops (fractions of 2007 × 2853) that keep each render's device and drop its baked-in store caption.
  const HERO = [0, 0.185, 1, 0.75], REVEAL = [0, 0.18, 1, 0.78], PAIR = [0, 0.125, 1, 0.84];
  const R1 = { fit: "contain", feather: 70 };
  const ANVIL = [0.18, 0.52, 0.64, 0.33];   // the object on the lower half of a tabletop still
  const TABLETOP = [0, 0, 1, 1];

  // ---- feed: the launch carousel (8 slides, 1080 × 1350; key content inside the 3:4 grid crop, x 34–1046) ----------
  const C = "feed/carousel";
  await render(page(FW, FH, `<div class="band" style="top:0"></div>${wordmark(84, 66)}
    ${headline("your phone is a *hydraulic press*.", { y: 160, size: 96 })}
    ${pic(ST.heroDuck, { x: 20, y: 390, w: 1040, h: 880, crop: HERO, ...R1 })}
    <div class="fine" style="top:1272px">${FINE}</div>`), `${C}/01-hero.png`, FW, FH);

  const steps = [[S.open, "lay it *open*.", "the object lands on the lower screen."],
    [S.closing, "close it *slowly*.", "the hinge is the lever. feel it give."],
    [S.eggCard, "open it. it's *filed*.", "every press becomes a pressed specimen."]];
  await render(page(FW, FH, `${wordmark(84, 66)}${headline("how it *works*.", { y: 150, size: 92, lines: 1 })}
    ${steps.map(([f, t, d], i) => `
      ${pic(f, { x: 84, y: 330 + i * 320, w: 300, h: 280, crop: i === 2 ? [0.05, 0.1, 0.9, 0.8] : [0.1, 0.3, 0.8, 0.55], radius: 34, shadow: true })}
      <div style="position:absolute;left:420px;top:${360 + i * 320}px;width:70px;height:70px;border-radius:50%;background:var(--graphite);color:var(--paper);display:flex;align-items:center;justify-content:center;font-size:42px">${i + 1}</div>
      <div class="h" style="left:510px;top:${356 + i * 320}px;width:500px;font-size:56px">${R.rich(t)}</div>
      <div class="s" style="left:420px;top:${450 + i * 320}px;width:590px;font-size:34px">${R.rich(d)}</div>`).join("")}`),
  `${C}/02-how-it-works.png`, FW, FH);

  await render(page(FW, FH, `${wordmark(84, 66)}${headline("ten objects. ten ways to *give*.", { y: 150, size: 88, lines: 2 })}
    ${objectGrid({ state: "rest", y0: 470 })}
    ${sub("bubble wrap to glass bottle. one of them won't squish at all.", { y: 1180, size: 34 })}`), `${C}/03-ten-objects.png`, FW, FH);

  await render(page(FW, FH, `${wordmark(84, 66)}${headline("each one gives its *own* way.", { y: 150, size: 88, lines: 2 })}
    ${objectGrid({ state: "crushed", y0: 470 })}
    ${sub("pops, splats, snaps, fizz. the same press every time.", { y: 1180, size: 34 })}`), `${C}/04-each-gives.png`, FW, FH);

  await render(page(FW, FH, `${wordmark(84, 66)}${headline("open up. file the *evidence*.", { y: 150, size: 88, lines: 2 })}
    ${pic(S.eggCard, { x: 120, y: 400, w: 840, h: 840, crop: [0.02, 0.06, 0.96, 0.66], radius: 40, shadow: true })}
    ${sub("every press is stamped, measured and kept.", { y: 1262, size: 34 })}`), `${C}/05-specimens.png`, FW, FH);

  await render(page(FW, FH, `${wordmark(84, 66)}${headline("collect every pressed *specimen*.", { y: 150, size: 88, lines: 2 })}
    ${pic(S.shelf, { x: 90, y: 400, w: 900, h: 860, crop: [0, 0, 1, 0.67], radius: 40, shadow: true })}`), `${C}/06-shelf.png`, FW, FH);

  await render(page(FW, FH, `${wordmark(84, 66)}${headline("no foldable? *drag* it.", { y: 150, size: 92, lines: 1 })}
    ${sub("works on every iPhone. made for the fold.", { y: 270, size: 38 })}
    ${pic(S.p48, { x: 230, y: 360, w: 620, h: 930, crop: [0, 0.06, 1, 0.86], radius: 48, shadow: true })}`), `${C}/07-every-iphone.png`, FW, FH);

  await render(page(FW, FH, `<div class="band" style="top:0"></div><div class="band" style="bottom:0"></div>
    <div style="position:absolute;left:0;right:0;top:250px;display:flex;flex-direction:column;align-items:center;text-align:center">
      ${icon ? `<img src="${R.fileURL(icon)}" style="width:300px;height:300px;border-radius:67px;box-shadow:0 26px 60px rgba(30,28,25,.35)">` : ""}
      <div style="font-size:150px;line-height:1;margin-top:40px;letter-spacing:-.02em">squish</div>
      <div style="font-size:54px;margin-top:26px">${OUT_NOW}</div>
      <div class="pill" style="margin-top:34px">${PRICE["ad-uk"]}</div>
      <div class="s" style="position:static;margin-top:34px;font-size:34px">best on iPhone Duo. works on every iPhone.</div>
    </div>`), `${C}/08-get-it.png`, FW, FH);

  // ---- feed: three single posts (COPY.md posts 0, 5, 7) -------------------------------------------------------------------
  // The glass post shows the object only: the Duo renders draw the shattered glass's print on the upper screen, which
  // could read as a cracked phone screen (CrackGate, PLAN.md §0.1 hard no's).
  await render(page(FW, FH, `${wordmark(84, 66)}${headline("it creaks. then it *doesn't*.", { y: 150, size: 92, lines: 2 })}
    ${pic(S.glassStrain, { x: 84, y: 400, w: 448, h: 800, crop: [0.2, 0.5, 0.6, 0.38], radius: 40, shadow: true })}
    ${pic(S.glassGone, { x: 548, y: 400, w: 448, h: 800, crop: [0.2, 0.5, 0.6, 0.38], radius: 40, shadow: true })}
    <div class="tag" style="left:110px;top:1140px">creak…</div><div class="tag" style="left:574px;top:1140px">…then not.</div>
    <div class="fine" style="top:1262px">a glass bottle, on screen. nothing real goes inside.</div>`),
  "feed/post-1-glass.png", FW, FH);
  await render(page(FW, FH, `${wordmark(84, 66)}${headline("he'll be fine. *probably*.", { y: 150, size: 92, lines: 2 })}
    ${pic(ST.heroDuck, { x: 20, y: 380, w: 1040, h: 890, crop: HERO, ...R1 })}<div class="fine" style="top:1272px">${FINE}</div>`),
  "feed/post-2-duck.png", FW, FH);
  await render(page(FW, FH, `${wordmark(84, 66)}${headline("count the *buckles*.", { y: 150, size: 92, lines: 1 })}
    ${sub("five, if you go slowly enough. then the fizz goes.", { y: 270, size: 38 })}
    ${pic(ST.pairCan, { x: 20, y: 360, w: 1040, h: 910, crop: PAIR, ...R1 })}<div class="fine" style="top:1272px">${FINE}</div>`),
  "feed/post-3-can.png", FW, FH);

  // ---- Story stills (1080 × 1920; text inside y 270–1536; sticker spaces left empty) ---------------------------------------
  const story = async (rel, body, stickers = []) => {
    for (const guide of [false, true]) {
      const html = page(SW, SH, body + stickers.map(([box, label]) => stickerBox(box, label, guide)).join("") + storyBands(guide));
      await render(html, guide ? rel.replace("stories/", "stories/guides/").replace(".png", "-guide.png") : rel, SW, SH);
    }
  };
  const sh = (t, y, size = 84, lines = 2) => headline(t, { y, size, lines, x: 90, w: 900 });
  await story("stories/story-1-2-shelf.png", `${wordmark(90, 300)}${sh("8 down. *2* to go.", 400)}
    ${pic(S.shelf, { x: 90, y: 600, w: 900, h: 640, crop: [0, 0.02, 1, 0.5], radius: 40, shadow: true })}`,
  [[[140, 1270, 800, 250], "poll sticker: how do you close it?"]]);
  await story("stories/story-1-4-card.png", `${wordmark(90, 300)}${sh("every press, *filed*.", 400)}
    ${pic(S.eggCard, { x: 140, y: 580, w: 800, h: 640, crop: [0.02, 0.08, 0.96, 0.62], radius: 40, shadow: true })}
    <div class="s" style="left:90px;top:1460px;width:900px;text-align:center;font-size:36px">${PRICE["ad-uk"]}</div>`,
  [[[240, 1260, 600, 160], "link sticker: get squish"]]);
  const vs = async (rel, a, an, bb, bn) => story(rel, `${wordmark(90, 300)}${sh("which one *first*?", 400, 84, 1)}
    ${pic(a, { x: 90, y: 560, w: 440, h: 560, crop: ANVIL, radius: 40, shadow: true })}<div class="tag" style="left:110px;top:1080px">${an}</div>
    ${pic(bb, { x: 550, y: 560, w: 440, h: 560, crop: ANVIL, radius: 40, shadow: true })}<div class="tag" style="left:570px;top:1080px">${bn}</div>`,
  [[[140, 1190, 800, 300], "poll sticker"]]);
  await vs("stories/story-2-1-glass-or-jelly.png", S.glassIdle, "glass bottle", S.jellyIdle, "jelly");
  await vs("stories/story-2-2-can-or-duck.png", S.canIdle, "soda can", S.duckIdle, "rubber duck");
  await story("stories/story-2-3-quiz.png", `${wordmark(90, 300)}${sh("which one has the *longest* creak?", 400, 80, 3)}
    ${["glassBottle", "sodaCan", "jelly"].map((k, i) => pic(art(k), { x: 120 + i * 290, y: 680, w: 260, h: 260, crop: [0.1, 0.1, 0.8, 0.8], radius: 34, extra: "background:#f2ede6;box-shadow:0 8px 20px rgba(30,28,25,.14);" })).join("")}`,
  [[[140, 1010, 800, 470], "quiz sticker"]]);
  await story("stories/story-2-5-link.png", `<div style="position:absolute;left:0;right:0;top:420px;display:flex;flex-direction:column;align-items:center;text-align:center">
      ${icon ? `<img src="${R.fileURL(icon)}" style="width:280px;height:280px;border-radius:62px;box-shadow:0 26px 60px rgba(30,28,25,.35)">` : ""}
      <div class="h" style="position:static;margin-top:48px;font-size:96px">press it <em class="hl">yourself</em>.</div>
      <div class="s" style="position:static;margin-top:24px;font-size:40px">${OUT_NOW}</div></div>`,
  [[[240, 1180, 600, 160], "link sticker: press it yourself"]]);
  await story("stories/story-3-1-quiz.png", `${wordmark(90, 300)}${sh("quick *quiz*.", 420, 110, 1)}
    ${pic(S.closing, { x: 140, y: 600, w: 800, h: 420, crop: [0.05, 0.42, 0.9, 0.42], radius: 40, shadow: true })}`,
  [[[140, 1060, 800, 440], "quiz sticker: how do you get a Perfect Squish?"]]);
  await story("stories/story-3-2-golden-rule.png", `${wordmark(90, 300)}${sh("and the golden rule:", 400, 84, 1)}
    ${pic(ST.open112, { x: 20, y: 510, w: 1040, h: 780, crop: [0, 0.2, 1, 0.7], ...R1 })}
    <div class="h fit" data-max="62" data-min="40" data-lines="2" style="left:90px;top:1300px;width:900px;font-size:62px;text-align:center">everything's on screen. <em class="hl">nothing real</em> goes inside.</div>`);
  await story("stories/story-3-4-whats-next.png", `${wordmark(90, 300)}${sh("what should we press *next*?", 400, 84, 2)}
    <div class="s" style="left:90px;top:1440px;width:900px;text-align:center;font-size:40px">ice cube? marshmallow? fortune cookie?</div>`,
  [[[140, 640, 800, 420], "question sticker"], [[240, 1140, 600, 160], "link sticker"]]);

  // ---- profile kit ------------------------------------------------------------------------------------------------------
  // The avatar: the icon inside the circle Instagram crops to, on the icon's own graphite (nothing important near the rim).
  for (const size of [1080, 320]) {
    await b.png(`<!doctype html><html><head><style>html,body{margin:0;width:${size}px;height:${size}px;background:radial-gradient(circle at 50% 40%,#3a3c41,#242529);}
      img{position:absolute;left:${size * 0.07}px;top:${size * 0.07}px;width:${size * 0.86}px;height:${size * 0.86}px;border-radius:${size * 0.19}px;}</style></head>
      <body><img src="${icon ? R.fileURL(icon) : ""}"></body></html>`, out(`profile/avatar-${size}.png`), { width: size, height: size, transparent: false });
  }
  // Highlight covers (1080 × 1920; Instagram shows the central circle only): a yellow disc with one picture and a word.
  const covers = [["objects", art("rubberDuck"), "objects"], ["how-it-works", null, "how it works"], ["safety", null, "safety"],
    ["press", S.p48can, "press"], ["specimens", art("egg", "crushed"), "specimens"]];
  for (const [slug, img, word] of covers) {
    const glyph = slug === "how-it-works"
      ? `<svg width="380" height="300" viewBox="0 0 380 300"><path d="M40 250 H340" stroke="#2B2D31" stroke-width="30" stroke-linecap="round"/><path d="M60 250 L250 70" stroke="#2B2D31" stroke-width="30" stroke-linecap="round"/><circle cx="60" cy="250" r="26" fill="#2B2D31"/><path d="M150 250 A90 90 0 0 0 128 186" stroke="#F3EEE6" stroke-width="18" fill="none" stroke-linecap="round"/></svg>`
      : slug === "safety"
        ? `<svg width="380" height="320" viewBox="0 0 380 320"><rect x="40" y="40" width="300" height="70" rx="22" fill="#2B2D31"/><rect x="40" y="210" width="300" height="70" rx="22" fill="#2B2D31"/><path d="M80 160 H300" stroke="#F3EEE6" stroke-width="16" stroke-dasharray="8 26" stroke-linecap="round"/></svg>`
        : img ? `<div style="width:420px;height:420px;border-radius:50%;overflow:hidden;position:relative;background:#f2ede6">${pic(img, { x: 0, y: 0, w: 420, h: 420, crop: slug === "press" ? [0.1, 0.32, 0.8, 0.45] : [0.14, 0.14, 0.72, 0.72] })}</div>` : "";
    await b.png(`<!doctype html><html><head><meta charset="utf-8"><style>${R.baseCSS()}
      body{width:${SW}px;height:${SH}px;margin:0;background:var(--paper);display:flex;align-items:center;justify-content:center;}
      .disc{width:720px;height:720px;border-radius:50%;background:var(--yellow);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;
        box-shadow:inset 0 -16px 0 rgba(0,0,0,.08);}
      .w{font-size:64px;color:var(--graphite);letter-spacing:-.01em;}</style></head>
      <body><div class="disc">${glyph}<div class="w">${word}</div></div></body></html>`, out(`profile/highlight-${slug}.png`), { width: SW, height: SH, transparent: false });
  }
  await b.close();

  fs.writeFileSync(path.join(OUT, "_work", "statics.json"), JSON.stringify({ made, problems }, null, 1));
  console.log(`statics: ${made.length} file(s); problems: ${problems.length ? "\n  " + problems.join("\n  ") : "none"}`);
}
await main();
