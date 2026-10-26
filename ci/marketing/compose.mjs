#!/usr/bin/env node
// Composes the Instagram Reels / ad masters (docs/marketing/PLAN.md §0) from the recorded clips (ci/marketing-record.sh)
// with ffmpeg, and checks them. Data: ci/marketing/cuts.mjs. Overlays: ci/marketing/render.mjs (Nunito, headless Chrome).
//
//   node ci/marketing/compose.mjs --clips <dir> [--clips <dir>…] --assets <dir> --out <dir> [--footage <dir>]
//                                [--only <regex>] [--dry]
//
// Per cut and variant (organic, ad-uk, ad-us): one intermediate per segment (1080 × 1920, 30 fps, CRF 12, PCM), joined,
// sound mastered (gain to −14.5 LUFS, a 4× oversampled limiter at −1.6 dBFS so the AAC file stays ≤ −1 dBTP, measured
// again), then one encode with every overlay: H.264 High 4.2, 30 fps CFR, bt709, AAC 256 kbit/s 48 kHz stereo.
// QC (written to <out>/qc and <out>/REPORT.md): ffprobe facts, loudness (EBU R128 integrated + true peak), stills at the
// hook / break / middle / end, safe-zone composites, a contact sheet, a sync check at each break (flash vs sound onset)
// and a box check of every text overlay against the Reels-ad keep-clear bands.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as R from "./render.mjs";
import { CUTS, STORY_CUTS, FINE, PRICE, OUT_NOW } from "./cuts.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const opts = (k) => args.flatMap((a, i) => (a === k ? [args[i + 1]] : []));
const DRY = args.includes("--dry");
const OUT = path.resolve(opt("--out", "marketing-kit"));
const ASSETS = path.resolve(opt("--assets", "marketing-assets"));
const FOOTAGE = path.resolve(opt("--footage", path.join(HERE, "footage")));
const ONLY = opt("--only", "");
const CLIP_DIRS = opts("--clips").map((d) => path.resolve(d));
const W = 1080, H = 1920, FPS = 30;
const VARIANTS = ["organic", "ad-uk", "ad-us"];
const SAFE = R.SAFE.reels;
const LOUD_TARGET = -14.5, TP_LIMIT = -1.6;

const WORK = path.join(OUT, "_work");
const QC = path.join(OUT, "qc");
for (const d of [OUT, WORK, QC]) fs.mkdirSync(d, { recursive: true });
const report = [];
const problems = [];
const log = (s) => { console.log(s); report.push(s); };
const problem = (s) => { console.log("PROBLEM " + s); problems.push(s); };

// ---- tools ------------------------------------------------------------------------------------------------------
function run(cmd, argv, { quiet = false, allowFail = false } = {}) {
  if (DRY) { console.log("[dry] " + cmd + " " + argv.map((a) => (/[\s'"(),;[\]]/.test(a) ? JSON.stringify(a) : a)).join(" ")); return { stdout: "", stderr: "", status: 0 }; }
  const r = spawnSync(cmd, argv, { encoding: "utf8", maxBuffer: 1 << 28 });
  if (r.status !== 0 && !allowFail) {
    throw new Error(`${cmd} failed (${r.status}): ${(r.stderr || "").split("\n").slice(-12).join("\n")}\nargs: ${argv.join(" ").slice(0, 3000)}`);
  }
  if (!quiet && r.stderr && r.status !== 0) console.log(r.stderr.slice(-2000));
  return r;
}
const ff = (argv, o) => run("ffmpeg", ["-nostdin", "-hide_banner", "-y", "-v", "error", ...argv], o);
const f3 = (x) => (Math.round(x * 1000) / 1000).toFixed(3);
const even = (x) => Math.max(2, 2 * Math.round(x / 2));
const clamp = (x, a, b) => Math.min(Math.max(x, a), b);

function imageSize(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32BE(0) === 0x89504e47) return [b.readUInt32BE(16), b.readUInt32BE(20)];
  let i = 2;
  while (i < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return [b.readUInt16BE(i + 7), b.readUInt16BE(i + 5)];
    i += 2 + b.readUInt16BE(i + 2);
  }
  return [1, 1];
}
function probeDuration(file) {
  if (DRY) return 10;
  const r = run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file], { quiet: true });
  return parseFloat(r.stdout) || 0;
}

// ---- clips ------------------------------------------------------------------------------------------------------
const CLIPS = new Map();
for (const dir of CLIP_DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith(".info")) continue;
    const name = f.slice(0, -5);
    const info = Object.fromEntries(fs.readFileSync(path.join(dir, f), "utf8").split("\n").filter(Boolean)
      .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
    const marks = new Map();
    const mf = path.join(dir, name + ".marks.txt");
    if (fs.existsSync(mf)) {
      for (const l of fs.readFileSync(mf, "utf8").split("\n")) {
        const [k, v] = l.trim().split(/\s+/);
        if (k && v !== undefined && !marks.has(k)) marks.set(k, parseFloat(v));
      }
    }
    CLIPS.set(name, { name, file: path.join(dir, name + ".mov"), info, marks,
      w: +info.width, h: +info.height, dur: +info.duration, pose: info.pose });
  }
}
log(`clips: ${[...CLIPS.keys()].sort().join(" ") || "(none)"}`);

/** A clip mark spec ("failure-3.0,phase-sealed+0.2", or a number) → clip seconds, or null. */
function clipTime(clip, spec) {
  if (typeof spec === "number") return spec;
  for (const alt of String(spec).split(",")) {
    const m = alt.trim().match(/^(.+?)(?:([+-])([0-9.]+))?$/);
    if (!m) continue;
    let base = null;
    if (m[1] === "start") base = 0; else if (m[1] === "end") base = clip.dur; else if (clip.marks.has(m[1])) base = clip.marks.get(m[1]);
    if (base === null || Number.isNaN(base)) continue;
    const d = m[3] ? parseFloat(m[3]) * (m[2] === "-" ? -1 : 1) : 0;
    return base + d;
  }
  return null;
}
/** A variant-dependent value: plain, or { organic, "ad-uk", "ad-us", ad, default }. */
function pick(v, variant) {
  if (v === null || v === undefined || typeof v !== "object" || Array.isArray(v)) return v;
  if (variant in v) return v[variant];
  if (variant.startsWith("ad") && "ad" in v) return v.ad;
  return v.default;
}

// ---- layouts ----------------------------------------------------------------------------------------------------
// zoom: scale relative to fitting the source's width to the canvas; (fx, fy): the source point (fractions) put at
// (ox, oy) (fractions of the canvas); a source wider/taller than the canvas is clamped so it always covers it.
// obj: where the object sits in the source, for overlays that follow it.
const GRAPHITE = "0x2B2D31", PAPER = "0xF3EEE6";
const LAYOUTS = {
  duo: { zoom: 1.0, fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.4, bg: GRAPHITE, obj: [0.5, 0.677] },
  // The anvil crops may leave graphite below the source (in the bottom keep-clear band, under Instagram's own UI) so
  // the object sits in the middle of the safe zone instead of low in it.
  anvil: { zoom: 2.1, fx: 0.5, fy: 0.677, ox: 0.5, oy: 0.58, bg: GRAPHITE, obj: [0.5, 0.677], clampY: false },
  "anvil-wide": { zoom: 1.85, fx: 0.5, fy: 0.66, ox: 0.5, oy: 0.56, bg: GRAPHITE, obj: [0.5, 0.677], clampY: false },
  // The reveal ceremony: the PRESSED print and the specimen ticket, cut just under the bezel (no gauge, lamps or keys).
  reveal: { zoom: 1.8, top: 0.115, fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.5, bg: GRAPHITE, obj: [0.5, 0.42] },
  slomo: { zoom: 2.0, fx: 0.5, fy: 0.70, ox: 0.5, oy: 0.58, bg: GRAPHITE, obj: [0.5, 0.70], clampY: false },
  // The sealed card drawn full screen on the 6.9" canvas (p-cover-*): the card, big, mid frame.
  pcover: { zoom: 1.1, fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.45, bg: GRAPHITE, obj: [0.5, 0.5] },
  // The P-48's specimen card drops in over the top of the machine: frame the card, not the anvil.
  p69card: { zoom: 1.15, top: 0.045, fx: 0.5, fy: 0.25, ox: 0.5, oy: 0.35, bg: PAPER, obj: [0.5, 0.25] },   // under the status bar
  "p69-ram": { zoom: 1.75, fx: 0.5, fy: 0.6, ox: 0.5, oy: 0.47, bg: PAPER, obj: [0.5, 0.66], clampY: false },
  cover: { zoom: 1.25, fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.48, bg: GRAPHITE, obj: [0.5, 0.5] },
  book: { zoom: 1.0, fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.40, bg: PAPER, obj: [0.75, 0.5] },
  p69: { zoom: 1.13, fx: 0.5, fy: 0.703, ox: 0.5, oy: 0.64, bg: PAPER, obj: [0.5, 0.703], clampY: false },
  "p69-tight": { zoom: 1.6, fx: 0.5, fy: 0.69, ox: 0.5, oy: 0.47, bg: PAPER, obj: [0.5, 0.69] },
  real: { zoom: "cover", fx: 0.5, fy: 0.5, ox: 0.5, oy: 0.5, bg: GRAPHITE, obj: [0.5, 0.55] },
};
function place(src, layoutName, CW = W, CH = H, over = {}) {
  const L = { ...LAYOUTS[layoutName] || LAYOUTS.duo, ...over };
  let zoom = L.zoom;
  if (zoom === "cover") zoom = Math.max(1, (CH / CW) / (src.h / src.w));
  const sw = even(CW * zoom), sh = even(src.h * sw / src.w);
  let x = Math.round(L.ox * CW - L.fx * sw), y = Math.round(L.oy * CH - L.fy * sh);
  x = sw >= CW ? clamp(x, CW - sw, 0) : Math.round((CW - sw) / 2);
  if (L.top !== undefined) y = Math.round(-L.top * sh);
  else if (sh >= CH && L.clampY !== false) y = clamp(y, CH - sh, 0);
  if (L.clampY === false && L.top === undefined) y = Math.min(0, y);
  const obj = [x + L.obj[0] * sw, y + L.obj[1] * sh];
  return { sw, sh, x, y, bg: L.bg, obj, gapBottom: Math.max(0, CH - (y + sh)), gapTop: Math.max(0, y) };
}

// ---- real-hand footage (SHOOT-GUIDE.md S1–S12) -------------------------------------------------------------------
function realClip(shot) {
  if (!shot) return null;
  for (const ext of [".mp4", ".mov", ".MP4", ".MOV"]) {
    const f = path.join(FOOTAGE, shot + ext);
    if (fs.existsSync(f)) {
      const inFile = path.join(FOOTAGE, shot + ".in");
      const start = fs.existsSync(inFile) ? parseFloat(fs.readFileSync(inFile, "utf8")) || 0 : 0;
      let w = 2160, h = 3840;
      if (!DRY) {
        const r = run("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", f], { quiet: true });
        [w, h] = r.stdout.trim().split(",").map(Number);
      }
      return { name: shot, file: f, w, h, dur: probeDuration(f), marks: new Map(), info: { pose: "real" }, start };
    }
  }
  return null;
}

// ---- plan a cut ---------------------------------------------------------------------------------------------------
function planCut(cut, variant) {
  const segs = [];
  let t = 0;
  const defs = cut.segments.filter((s) => !s.only || s.only === variant || (s.only === "ad" && variant.startsWith("ad")));
  for (const [i, s] of defs.entries()) {
    const seg = { ...s, index: i, kind: s.grid ? "grid" : s.still ? "still" : "clip" };
    const durWanted = pick(s.dur, variant);
    if (seg.kind === "clip") {
      const real = realClip(s.real);
      const clip = real || CLIPS.get(s.clip);
      if (!clip) { problem(`${cut.id}/${variant}: clip ${s.clip} is missing; segment ${i} skipped`); continue; }
      seg.clip = clip; seg.isReal = !!real;
      if (real) {
        // The founder's shot, from its .in second, as long as the simulator segment it replaces; time references into
        // it still resolve through the simulator clip's marks (simClip / simFrom).
        const sim = CLIPS.get(s.clip);
        const simFrom = sim ? clipTime(sim, s.from ?? 0) : null;
        let simDur = durWanted;
        if (simDur === undefined && sim && simFrom !== null) {
          const to = clipTime(sim, s.to ?? "end");
          simDur = to === null ? (s.maxDur ?? 4) : Math.min(to - simFrom, s.maxDur ?? 99);
        }
        seg.from = real.start;
        seg.dur = Math.min(simDur ?? 4, Math.max(0.5, real.dur - real.start));
        seg.layout = "real";
        if (sim && simFrom !== null) { seg.simClip = sim; seg.simFrom = simFrom; }
        log(`${cut.id}/${variant}: segment ${i} uses the founder's ${real.name} (${path.basename(real.file)} from ${real.start} s)`);
      } else {
        const from = clipTime(clip, s.from ?? 0);
        if (from === null) { problem(`${cut.id}/${variant}: ${clip.name} has no mark for '${s.from}'; segment ${i} skipped`); continue; }
        seg.from = Math.max(0, from);
        let dur = durWanted;
        if (dur === undefined) {
          const to = clipTime(clip, s.to ?? "end");
          dur = to === null ? (s.maxDur ?? 3) : to - from;
          if (s.maxDur) dur = Math.min(dur, s.maxDur);
          if (to === null) problem(`${cut.id}/${variant}: ${clip.name} has no mark for '${s.to}'; used ${f3(dur)} s`);
        }
        seg.dur = Math.max(0.3, Math.min(dur, clip.dur - seg.from));
        if (seg.dur < (durWanted ?? 0) - 0.05) problem(`${cut.id}/${variant}: ${clip.name} ends early (${f3(seg.dur)} of ${durWanted} s)`);
      }
    } else if (seg.kind === "still") {
      seg.file = path.join(ASSETS, s.still);
      if (!fs.existsSync(seg.file) && !DRY) { problem(`${cut.id}/${variant}: still ${s.still} missing; segment ${i} skipped`); continue; }
      seg.dur = durWanted ?? 1.2;
    } else {
      seg.tiles = s.grid.map((g) => ({ ...g, clip: CLIPS.get(g.clip) })).filter((g) => g.clip);
      if (seg.tiles.length < 4) { problem(`${cut.id}/${variant}: grid needs 4 clips; segment ${i} skipped`); continue; }
      seg.tiles.forEach((g) => { g.from = Math.max(0, clipTime(g.clip, g.from) ?? 0); });
      seg.dur = durWanted ?? 1.5;
    }
    seg.start = t;
    t += seg.dur;
    segs.push(seg);
  }
  const contentEnd = t;
  let card = null;
  if (variant !== "organic" && cut.end && pick(cut.end, variant)) {
    card = { kind: "card", start: t, dur: 1.5, end: pick(cut.end, variant) };
    segs.push(card);
    t += 1.5;
  }
  return { segs, contentEnd, total: t, card };
}

/** A time reference in a planned cut → seconds. */
function cutTime(plan, ref) {
  if (typeof ref === "number") return ref;
  const r = String(ref).trim();
  let m = r.match(/^end([+-][0-9.]+)?$/);
  if (m) return plan.contentEnd + (m[1] ? parseFloat(m[1]) : 0);
  for (const alt of r.split(",")) {
    m = alt.trim().match(/^(\d+):(.+?)(?:([+-])([0-9.]+))?$/);
    if (!m) continue;
    const seg = plan.segs.find((s) => s.index === +m[1]);
    if (!seg) continue;
    const d = m[4] ? parseFloat(m[4]) * (m[3] === "-" ? -1 : 1) : 0;
    if (m[2] === "start") return seg.start + d;
    if (m[2] === "end") return seg.start + seg.dur + d;
    if (seg.kind !== "clip") continue;
    const c = seg.isReal ? seg.simClip : seg.clip, from = seg.isReal ? seg.simFrom : seg.from;
    if (!c) continue;
    const ct = clipTime(c, m[2]);
    if (ct === null) continue;
    return seg.start + (ct - from) + d;
  }
  return null;
}

// ---- segment renders ----------------------------------------------------------------------------------------------
const sfmt = "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p";
function layoutFilter(inLabel, src, layoutName, dur, outLabel, CW = W, CH = H, over = {}) {
  const p = place(src, layoutName, CW, CH, over);
  // On the Duo the app's console (Menu · object chip · Shelf) is cropped to graphite: it sits in the keep-clear band
  // anyway, and its chip names the object's failure ("EGG · CRACKS") right under the phone's screen (CrackGate).
  // (The P-48 takes run with `nochrome`, so their console is never drawn and needs no mask.)
  const maskAt = src.pose === "tabletop" || src.pose === "book" ? 0.925 : null;
  const maskY = maskAt === null ? CH : Math.round(p.y + maskAt * p.sh);
  const mask = maskY < CH ? `,drawbox=x=0:y=${Math.max(0, maskY)}:w=${CW}:h=${CH - Math.max(0, maskY)}:color=${GRAPHITE}:t=fill` : "";
  return `${inLabel}scale=${p.sw}:${p.sh}:flags=lanczos,setsar=1[sv_${outLabel}];` +
    `color=c=${p.bg}:s=${CW}x${CH}:r=${FPS}:d=${f3(dur)}[bg_${outLabel}];` +
    `[bg_${outLabel}][sv_${outLabel}]overlay=${p.x}:${p.y}:shortest=1:eof_action=repeat${mask},format=yuv420p[${outLabel}]`;
}
const aOut = (dur) => `aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,apad,atrim=0:${f3(dur)},asetpts=PTS-STARTPTS`;
const venc = ["-r", String(FPS), "-c:v", "libx264", "-preset", "fast", "-crf", "12", "-pix_fmt", "yuv420p", "-g", "30"];
const aenc = ["-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"];

/** Audio input args + filter for a segment's sound: its own clip, another clip's window, the slowed break, or none. */
function segAudio(seg, inputs, dur) {
  const a = seg.audio;
  if (a === "none") return null;
  if (a === "slomo") {
    // The SLO-MO film replays the break at 0.35×: the clip's own break sound, slowed to match (pitch 0.55, tempo 0.636).
    const c = seg.clip, fail = clipTime(c, "failure") ?? clipTime(c, "fracture-1");
    if (fail === null) return null;
    const idx = inputs.length; inputs.push(["-i", c.file]);
    const lead = 0.5, at = (seg.slomoAt ? clipTime(c, seg.slomoAt) : null) ?? detectFlash(c, seg.from, seg.from + dur) ?? (seg.from + 0.45);
    const delay = Math.max(0, (at - seg.from) - lead / 0.35);
    return `[${idx}:a]atrim=start=${f3(Math.max(0, fail - lead))}:duration=2.2,asetpts=PTS-STARTPTS,asetrate=48000*0.55,aresample=48000,atempo=0.636,` +
      `adelay=delays=${Math.round(delay * 1000)}:all=1,volume=1.4,${aOut(dur)},afade=t=out:st=${f3(Math.max(0, dur - 0.25))}:d=0.25`;
  }
  if (a && typeof a === "object") {
    const c = CLIPS.get(a.clip);
    const from = c ? clipTime(c, a.from) : null;
    if (!c || from === null) return null;
    const idx = inputs.length; inputs.push(["-i", c.file]);
    return `[${idx}:a]atrim=start=${f3(Math.max(0, from))}:duration=${f3(dur)},asetpts=PTS-STARTPTS,${aOut(dur)},afade=t=out:st=${f3(Math.max(0, dur - 0.2))}:d=0.2`;
  }
  if (seg.kind === "clip") {
    return `[0:a]atrim=start=${f3(seg.from)}:duration=${f3(dur)},asetpts=PTS-STARTPTS,${aOut(dur)},afade=t=in:d=0.02,afade=t=out:st=${f3(Math.max(0, dur - 0.03))}:d=0.03`;
  }
  return null;
}

/** The time (clip s) of the biggest frame-to-frame brightness rise in [a, b] of a clip (a failure flash), or null. */
const flashCache = new Map();
function detectFlash(clip, a, b, crop = "") {
  const key = `${clip.file}|${f3(a)}|${f3(b)}|${crop}`;
  if (flashCache.has(key)) return flashCache.get(key);
  if (DRY) return null;
  const r = run("ffmpeg", ["-nostdin", "-v", "error", "-i", clip.file, "-vf",
    `trim=start=${f3(a)}:duration=${f3(b - a)},setpts=PTS-STARTPTS,${crop}scale=180:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-`,
    "-f", "null", "-"], { quiet: true, allowFail: true });
  let last = null, best = 0, at = null, t = 0;
  for (const l of (r.stdout || "").split("\n")) {
    const pm = l.match(/pts_time:([0-9.]+)/); if (pm) t = parseFloat(pm[1]);
    const ym = l.match(/YAVG=([0-9.]+)/);
    if (ym) { const v = parseFloat(ym[1]); if (last !== null && v - last > best) { best = v - last; at = t; } last = v; }
  }
  const res = at === null || best < 4 ? null : a + at;
  flashCache.set(key, res);
  return res;
}

function renderSegment(seg, out, cut, variant, assets) {
  const dur = seg.dur;
  const inputs = [];
  let vf;
  if (seg.kind === "clip") {
    inputs.push(["-i", seg.clip.file]);
    const trim = `[0:v]trim=start=${f3(seg.from)}:duration=${f3(dur + 0.2)},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1,`;
    vf = layoutFilter(trim, seg.clip, seg.layout || "duo", dur, "v", W, H, seg.place || {});
  } else if (seg.kind === "still") {
    inputs.push(["-i", seg.file]);
    const [cx, cy, cw, ch] = seg.crop || [0, 0, 1, 1];
    const n = Math.round(dur * FPS);
    const [k0, k1] = seg.kb || [1, 1];
    // Fit the crop to 2× the frame's width, extend it to a 2× frame by smearing its own top and bottom rows (the
    // render's backdrop carries on, no box edge), then zoompan down to 1080 × 1920 (smooth at 2×).
    const [iw, ih] = DRY ? [2007, 2853] : imageSize(seg.file);
    const hs = Math.min(2 * H, even(2 * W * (ch * ih) / (cw * iw)));
    const top = even(((2 * H - hs) / 2) * 0.82), bottom = 2 * H - hs - top;
    vf = `[0:v]crop=iw*${cw}:ih*${ch}:iw*${cx}:ih*${cy},scale=${2 * W}:${hs}:flags=lanczos,format=gbrp,` +
      `pad=${2 * W}:${2 * H}:0:${top}:color=${seg.bg || PAPER}${top > 0 || bottom > 0 ? `,fillborders=top=${top}:bottom=${bottom}:mode=smear` : ""},` +
      `zoompan=z='${k0}+(${k1}-${k0})*on/${Math.max(1, n - 1)}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${n}:s=${W}x${H}:fps=${FPS},` +
      `${sfmt}[v]`;
  } else if (seg.kind === "grid") {
    const g = GRID;
    const parts = [];
    seg.tiles.forEach((tile, i) => {
      inputs.push(["-i", tile.clip.file]);
      const trim = `[${i}:v]trim=start=${f3(tile.from)}:duration=${f3(dur + 0.2)},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1,`;
      parts.push(layoutFilter(trim, tile.clip, seg.layout || "anvil", dur, `t${i}`, g.tile, g.tile, { oy: 0.5 }));
    });
    const matte = inputs.length; inputs.push(["-loop", "1", "-framerate", String(FPS), "-t", f3(dur + 0.1), "-i", assets.gridMatte]);
    let chain = `color=c=${PAPER}:s=${W}x${H}:r=${FPS}:d=${f3(dur)}[g0]`;
    seg.tiles.forEach((_, i) => {
      const x = g.x0 + (i % 2) * (g.tile + g.gap), y = g.y0 + Math.floor(i / 2) * (g.tile + g.gap);
      chain += `;[g${i}][t${i}]overlay=${x}:${y}:shortest=1[g${i + 1}]`;
    });
    chain += `;[${matte}:v]format=rgba,scale=out_color_matrix=bt709:out_range=tv,format=yuva420p[mt];[g4][mt]overlay=0:0:shortest=1,format=yuv420p[v]`;
    vf = parts.join(";") + ";" + chain;
  } else if (seg.kind === "card") {
    inputs.push(["-i", assets.cards[`${cut.id}-${variant}`]]);
    const n = Math.round(dur * FPS);
    vf = `[0:v]scale=${2 * W}:${2 * H}:flags=lanczos,zoompan=z='1+0.025*on/${n - 1}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${n}:s=${W}x${H}:fps=${FPS},${sfmt}[v]`;
  }
  let af = segAudio(seg, inputs, dur);
  if (!af && seg.kind === "card") {
    // The card keeps the room: the previous segment's clip carries on under it, fading out.
    const prev = seg.prev;
    if (prev && prev.kind === "clip") {
      const idx = inputs.length; inputs.push(["-i", prev.clip.file]);
      af = `[${idx}:a]atrim=start=${f3(prev.from + prev.dur)}:duration=${f3(dur)},asetpts=PTS-STARTPTS,${aOut(dur)},afade=t=out:st=0:d=${f3(dur)}`;
    }
  }
  if (!af) {
    const idx = inputs.length; inputs.push(["-f", "lavfi", "-t", f3(dur), "-i", "anullsrc=r=48000:cl=stereo"]);
    af = `[${idx}:a]${aOut(dur)}`;
  }
  ff([...inputs.flat(), "-filter_complex", `${vf};${af}[a]`, "-map", "[v]", "-map", "[a]", "-t", f3(dur), ...venc, ...aenc, out]);
}

const GRID = { x0: 130, y0: 500, tile: 400, gap: 20 };

// ---- overlays -----------------------------------------------------------------------------------------------------
// Each: { png, w, h, cx, cy | yExpr, from, to, fadeIn, fadeOut, rise, text: true when it must respect the safe zone }
async function buildOverlays(cut, variant, plan, browser, assets) {
  const dir = path.join(WORK, cut.id, variant, "ov");
  fs.mkdirSync(dir, { recursive: true });
  const ovs = [];
  let n = 0;
  async function add(html, o, clipPad = 12) {
    const png = path.join(dir, `o${String(++n).padStart(2, "0")}.png`);
    const box = DRY ? { width: 600, height: 140 } : await browser.png(html, png, { clip: ".o", pad: clipPad });
    ovs.push({ png, w: box.width, h: box.height, fadeIn: 0.12, fadeOut: 0.18, ...o });
  }
  const hook = pick(cut.hook, variant);
  if (hook) await add(R.hookHTML(hook, { size: cut.hookSize ?? 86 }), { cx: W / 2, cy: cut.hookY ?? 430, from: 0.2, to: 1.8, rise: 16, text: true, role: "hook" });
  for (const l of cut.lines || []) {
    const from = cutTime(plan, pick(l.from, variant)), to = cutTime(plan, pick(l.to, variant));
    if (from === null || to === null) { problem(`${cut.id}/${variant}: line "${l.text}" has no time (${l.from} / ${l.to})`); continue; }
    await add(R.captionHTML(pick(l.text, variant)), { cx: W / 2, cy: l.y ?? 430, from, to: Math.min(to, plan.contentEnd), rise: 12, text: true, role: "line" });
  }
  // The fine print, on every segment that shows a phone, and on the end card when it asks for it.
  const fineSegs = plan.segs.filter((s) => s.fine || s.isReal);
  if (fineSegs.length) {
    const html = R.finePrintHTML(FINE);
    for (const s of fineSegs) await add(html, { cx: W / 2, cy: cut.fineY ?? 560, from: s.start + 0.05, to: s.start + s.dur - 0.02, fadeIn: 0.1, fadeOut: 0.1, text: true, role: "fine" }, 10);
  }
  const end = pick(cut.end, variant);
  if (variant === "organic" && end) {
    const at = end.at ? cutTime(plan, end.at) : plan.contentEnd - 1.5;
    await add(R.endPillHTML({ icon: R.fileURL(assets.icon), line: pick(end.line, variant) || OUT_NOW }),
      { cx: W / 2, cy: cut.endY ?? 430, from: at, to: plan.contentEnd, rise: 14, fadeOut: 0, text: true, role: "end" }, 12);
    if (end.fine) await add(R.finePrintHTML(FINE), { cx: W / 2, cy: cut.fineY ?? 560, from: at + 0.05, to: plan.contentEnd, fadeOut: 0, text: true, role: "fine" }, 10);
  }
  if (cut.watermark && (cut.watermark === variant || cut.watermark === "all")) {
    await add(R.watermarkHTML(), { x: 86, y: 292, from: 0, to: plan.contentEnd, fadeIn: 0, fadeOut: 0, text: true, role: "watermark" }, 10);
  }
  if (cut.numbers) {
    for (const s of plan.segs) {
      if (s.number) await add(R.numberHTML(s.number), { cx: 170, cy: 400, from: s.start, to: s.start + s.dur, fadeIn: 0, fadeOut: 0, text: true, role: "number" }, 12);
      if (s.kind === "grid") {
        for (let i = 0; i < 4; i++) {
          const x = GRID.x0 + (i % 2) * (GRID.tile + GRID.gap), y = GRID.y0 + Math.floor(i / 2) * (GRID.tile + GRID.gap);
          await add(R.numberHTML(i + 1, { size: 80 }), { cx: x + 58, cy: y + 58, from: s.start, to: s.start + s.dur, fadeIn: 0, fadeOut: 0, text: true, role: "number" }, 12);
        }
      }
    }
  }
  if (cut.touch) {
    // The finger on the P-48 ram until the founder's S10: the ram's on-screen height follows the scripted slowpress
    // depth curve (PressDirector.slowPressDepth), anchored at the contact mark (depth 0.30).
    const seg = plan.segs.find((s) => s.index === cut.touch.seg);
    if (seg && seg.kind === "clip" && !seg.isReal) {
      const D = cut.touch.slow, contact = clipTime(seg.clip, "phase-pressing");
      if (contact !== null) {
        const t0 = contact - 0.35 - 0.16 * D;   // slowpress start (clip s): the lead-in, then u = 0.16 at contact
        const p = place(seg.clip, seg.layout || "p69");
        const depth = (tc) => { const u = (tc - t0 - 0.35) / D; return u <= 0 ? 0 : slowDepth(u); };
        const yAt = (tc) => p.y + (cut.touch.y0 + (cut.touch.y1 - cut.touch.y0) * depth(tc)) * p.sh;
        const until = cutTime(plan, cut.touch.until) ?? seg.start + seg.dur;
        const keys = [];
        for (let t = seg.start; t <= until + 1e-6; t += 0.1) keys.push([t, yAt(seg.from + (t - seg.start))]);
        await add(R.touchHTML(), { cx: W / 2 + 150, yKeys: keys, from: seg.start, to: until, fadeIn: 0.15, fadeOut: 0.2, text: false, role: "touch" }, 8);
      }
    }
  }
  return ovs;
}
function slowDepth(u) {   // PressDirector.slowPressDepth without the 1.3 Hz waver, u = t / duration
  const s = (x) => { const c = clamp(x, 0, 1); return c * c * (3 - 2 * c); };
  if (u < 0.16) return 0.30 * s(u / 0.16);
  if (u < 0.52) return 0.30 + 0.22 * s((u - 0.16) / 0.36);
  if (u < 0.66) return 0.52 + 0.015 * ((u - 0.52) / 0.14);
  return Math.min(1, 0.535 + 0.465 * s((u - 0.66) / 0.34));
}
/** A piecewise-linear ffmpeg expression in t through (t, v) keys. */
function pwl(keys) {
  let e = f3(keys[keys.length - 1][1]);
  for (let i = keys.length - 2; i >= 0; i--) {
    const [ta, va] = keys[i], [tb, vb] = keys[i + 1];
    e = `if(lt(t,${f3(tb)}),${f3(va)}+(${f3(vb - va)})*(t-${f3(ta)})/${f3(Math.max(0.001, tb - ta))},${e})`;
  }
  return e;
}
function ovBox(o) {
  const x = o.x ?? Math.round(o.cx - o.w / 2), y = o.y ?? (o.cy !== undefined ? Math.round(o.cy - o.h / 2) : null);
  return { x, y, w: o.w, h: o.h };
}

// ---- master: join, sound, overlays, encode ------------------------------------------------------------------------
function loudness(file) {
  if (DRY) return { I: -14.5, TP: -2, LRA: 5 };
  const r = run("ffmpeg", ["-nostdin", "-hide_banner", "-v", "info", "-i", file, "-af", "ebur128=peak=true:framelog=quiet", "-f", "null", "-"], { quiet: true, allowFail: true });
  const s = r.stderr || "";
  const tail = s.slice(s.lastIndexOf("Summary:"));
  const g = (re) => { const m = tail.match(re); return m ? parseFloat(m[1]) : NaN; };
  return { I: g(/I:\s+(-?[0-9.]+) LUFS/), TP: g(/Peak:\s+(-?[0-9.]+|-inf) dBFS/), LRA: g(/LRA:\s+(-?[0-9.]+) LU/) };
}

function masterAudio(inWav, sfx, outWav, total, limit = TP_LIMIT) {
  // 1. mix the sfx layers over the joined sound; 2. gain to target; 3. a true-peak-safe limiter (4× oversampled).
  const inputs = ["-i", inWav];
  let fc = "", mixIns = "[0:a]";
  sfx.forEach((s, i) => {
    inputs.push("-i", s.file);
    fc += `[${i + 1}:a]atrim=start=${f3(Math.max(0, s.from))}:duration=${f3(s.dur)},asetpts=PTS-STARTPTS,afade=t=out:st=${f3(Math.max(0, s.dur - 0.3))}:d=0.3,` +
      `volume=${s.gain ?? 0}dB,adelay=delays=${Math.round(s.at * 1000)}:all=1,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[x${i}];`;
    mixIns += `[x${i}]`;
  });
  const mixed = path.join(path.dirname(outWav), "mixed.wav");
  fc += sfx.length ? `${mixIns}amix=inputs=${sfx.length + 1}:duration=first:normalize=0,atrim=0:${f3(total)}[m]` : `[0:a]atrim=0:${f3(total)}[m]`;
  ff([...inputs, "-filter_complex", fc, "-map", "[m]", "-c:a", "pcm_f32le", "-ar", "48000", "-ac", "2", mixed]);
  let gain = 0, measured = loudness(mixed);
  for (let pass = 0; pass < 3; pass++) {
    gain += LOUD_TARGET - (Number.isFinite(measured.I) ? measured.I : LOUD_TARGET);
    const lim = Math.pow(10, limit / 20).toFixed(4);
    ff(["-i", mixed, "-af", `volume=${gain.toFixed(2)}dB,aresample=192000,alimiter=limit=${lim}:attack=2:release=60:level=false:latency=true,aresample=48000`,
      "-c:a", "pcm_f32le", "-ar", "48000", "-ac", "2", outWav]);
    measured = loudness(outWav);
    if (!Number.isFinite(measured.I) || Math.abs(measured.I - LOUD_TARGET) <= 0.3) break;
  }
  return measured;
}

function encodeMaster(base, wav, ovs, out, total) {
  const inputs = ["-i", base, "-i", wav];
  let fc = "[0:v]setpts=PTS-STARTPTS[b0]";
  ovs.forEach((o, i) => {
    const k = i + 2;
    inputs.push("-loop", "1", "-framerate", String(FPS), "-t", f3(Math.min(total, o.to) + 0.1), "-i", o.png);
    const fades = [o.fadeIn > 0 ? `fade=t=in:st=${f3(o.from)}:d=${f3(o.fadeIn)}:alpha=1` : null,
      o.fadeOut > 0 ? `fade=t=out:st=${f3(Math.max(o.from, o.to - o.fadeOut))}:d=${f3(o.fadeOut)}:alpha=1` : null].filter(Boolean).join(",");
    fc += `;[${k}:v]format=rgba${fades ? "," + fades : ""},scale=out_color_matrix=bt709:out_range=tv,format=yuva420p[o${i}]`;
    const b = ovBox(o);
    const x = b.x;
    let y;
    if (o.yKeys) y = `'${pwl(o.yKeys.map(([t, v]) => [t, v - o.h / 2]))}'`;
    else if (o.rise) y = `'${b.y}+${o.rise}*max(0,1-(t-${f3(o.from)})/0.2)'`;
    else y = String(b.y);
    fc += `;[b${i}][o${i}]overlay=x=${x}:y=${y}:enable='between(t,${f3(o.from)},${f3(o.to)})':eof_action=pass[b${i + 1}]`;
  });
  fc += `;[b${ovs.length}]format=yuv420p[vout]`;
  ff([...inputs, "-filter_complex", fc, "-map", "[vout]", "-map", "1:a", "-t", f3(total),
    "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level:v", "4.2", "-pix_fmt", "yuv420p", "-r", String(FPS),
    "-crf", "16", "-maxrate", "14M", "-bufsize", "28M", "-g", "30", "-keyint_min", "30",
    "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
    "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", out]);
}

// ---- QC ---------------------------------------------------------------------------------------------------------------
function probeFacts(file) {
  if (DRY) return {};
  const r = run("ffprobe", ["-v", "error", "-show_entries",
    "format=duration,size,bit_rate:stream=codec_type,codec_name,profile,level,width,height,r_frame_rate,avg_frame_rate,pix_fmt,sample_rate,channels,color_space",
    "-of", "json", file], { quiet: true });
  const j = JSON.parse(r.stdout);
  const v = j.streams.find((s) => s.codec_type === "video") || {}, a = j.streams.find((s) => s.codec_type === "audio") || {};
  return { dur: +j.format.duration, size: +j.format.size, kbps: Math.round(+j.format.bit_rate / 1000), v, a };
}
function stills(file, name, times, sub = "frames") {
  const dir = path.join(QC, sub); fs.mkdirSync(dir, { recursive: true });
  const outs = [];
  for (const [label, t] of times) {
    const o = path.join(dir, `${name}-${label}.png`);
    ff(["-ss", f3(Math.max(0, t)), "-i", file, "-frames:v", "1", "-update", "1", o], { allowFail: true });
    outs.push(o);
  }
  return outs;
}
function safeComposite(frame, mask, out) {
  ff(["-i", frame, "-i", mask, "-filter_complex", "[0:v][1:v]overlay=0:0", "-frames:v", "1", "-update", "1", out], { allowFail: true });
}
function contactSheet(file, out, total, n = 6) {
  const times = Array.from({ length: n }, (_, i) => (total * (i + 0.5)) / n);
  const parts = times.map((t, i) => `[i${i}]trim=start=${f3(t)}:duration=0.04,setpts=PTS-STARTPTS,scale=180:320[c${i}]`);
  ff(["-i", file, "-filter_complex", `[0:v]split=${n}${times.map((_, i) => `[i${i}]`).join("")};` + parts.join(";") + `;${times.map((_, i) => `[c${i}]`).join("")}hstack=inputs=${n}[s]`,
    "-map", "[s]", "-frames:v", "1", "-q:v", "3", "-update", "1", out], { allowFail: true });
}
/** Sync at a break: the brightness jump and the sound's biggest onset near the expected time, both in the master. */
function syncCheck(file, t) {
  if (DRY) return null;
  const a = Math.max(0, t - 0.3), d = 0.6;
  const v = run("ffmpeg", ["-nostdin", "-v", "error", "-i", file, "-vf", `trim=start=${f3(a)}:duration=${d},setpts=PTS-STARTPTS,scale=180:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-`, "-f", "null", "-"], { quiet: true, allowFail: true }).stdout || "";
  const au = run("ffmpeg", ["-nostdin", "-v", "error", "-i", file, "-af", `atrim=start=${f3(a)}:duration=${d},asetpts=PTS-STARTPTS,asetnsamples=480,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-`, "-f", "null", "-"], { quiet: true, allowFail: true }).stdout || "";
  const rise = (txt, key) => {
    let tt = 0, last = null, best = -1e9, at = null;
    for (const l of txt.split("\n")) {
      const pm = l.match(/pts_time:([0-9.]+)/); if (pm) tt = parseFloat(pm[1]);
      const m = l.match(new RegExp(key + "=(-?[0-9.]+|-inf)"));
      if (m) { const val = m[1] === "-inf" ? -120 : parseFloat(m[1]); if (last !== null && val - last > best) { best = val - last; at = tt; } last = val; }
    }
    return at === null ? null : { t: a + at, rise: best };
  };
  const fv = rise(v, "lavfi.signalstats.YAVG"), fa = rise(au, "lavfi.astats.Overall.RMS_level");
  if (!fv || !fa || fv.rise < 6 || fa.rise < 6) return null;   // no clear flash or onset: not a measurable break
  return { flash: fv.t, flashRise: fv.rise, onset: fa.t, onsetRise: fa.rise, offset: fa.t - fv.t };
}

// ---- main ---------------------------------------------------------------------------------------------------------------
const browser = DRY ? null : await R.browser();
const fontInfo = R.fontReport();
log(`font: ${fontInfo.nunito || "NO NUNITO FILE (fallback face; not final)"}`);
if (!fontInfo.nunito) problem("Nunito not found: set NUNITO_FONT (the workflow fetches it)");
const assets = { icon: path.join(ASSETS, "icon.png"), cards: {}, gridMatte: path.join(WORK, "grid-matte.png") };
if (!DRY) {
  await browser.png(R.gridMatteHTML(GRID), assets.gridMatte, { transparent: true });
  await browser.png(R.safeZoneHTML(R.SAFE.reels), path.join(WORK, "safe-reels.png"), { transparent: true });
  await browser.png(R.safeZoneHTML(R.SAFE.stories), path.join(WORK, "safe-stories.png"), { transparent: true });
}
const results = [];

async function buildMaster(cut, variant, outFile, { safe = SAFE, safePng = "safe-reels.png" } = {}) {
  const plan = planCut(cut, variant);
  if (!plan.segs.length) { problem(`${cut.id}/${variant}: nothing to cut`); return null; }
  const wdir = path.join(WORK, cut.id, variant); fs.mkdirSync(wdir, { recursive: true });
  if (plan.card) {
    const e = plan.card.end;
    const png = path.join(wdir, "card.png");
    assets.cards[`${cut.id}-${variant}`] = png;
    if (!DRY) await browser.png(R.endCardHTML({ icon: R.fileURL(assets.icon), headline: pick(e.headline, variant) || "",
      line: pick(e.line, variant) ?? OUT_NOW, price: e.price === "" ? "" : (pick(e.price, variant) ?? PRICE[variant] ?? ""),
      fine: e.fine ? FINE : "", badge: fs.existsSync(path.join(ASSETS, "badge.png")) ? R.fileURL(path.join(ASSETS, "badge.png")) : null }),
      png, { transparent: false });
  }
  // segments
  const files = [];
  plan.segs.forEach((s, i) => { s.prev = plan.segs[i - 1]; });
  for (const [i, s] of plan.segs.entries()) {
    const f = path.join(wdir, `s${String(i).padStart(2, "0")}.mov`);
    renderSegment(s, f, cut, variant, assets);
    files.push(f);
  }
  const list = path.join(wdir, "list.txt");
  fs.writeFileSync(list, files.map((f) => `file '${f.replace(/'/g, "'\\''")}'`).join("\n") + "\n");
  const base = path.join(wdir, "base.mov"), joinedWav = path.join(wdir, "joined.wav"), wav = path.join(wdir, "master.wav");
  ff(["-f", "concat", "-safe", "0", "-i", list, "-map", "0:v", "-c:v", "copy", "-an", base]);
  ff(["-f", "concat", "-safe", "0", "-i", list, "-map", "0:a", "-c:a", "pcm_f32le", joinedWav]);
  // sfx (e.g. the ka-chunk under the sealed card)
  const sfx = [];
  for (const s of plan.segs) for (const x of s.sfx || []) {
    const c = CLIPS.get(x.clip); const from = c ? clipTime(c, x.from) : null;
    if (!c || from === null) { problem(`${cut.id}/${variant}: sfx ${x.clip}@${x.from} unavailable`); continue; }
    sfx.push({ file: c.file, from, dur: x.dur, gain: x.gain, at: s.start + (x.at ?? 0) });
  }
  const loud = masterAudio(joinedWav, sfx, wav, plan.total);
  const ovs = await buildOverlays(cut, variant, plan, browser, assets);
  // The safe-zone check of every text overlay (the touch indicator and footage are exempt).
  for (const o of ovs.filter((o) => o.text)) {
    const b = ovBox(o);
    const top = b.y ?? Math.min(...(o.yKeys || [[0, 0]]).map(([, v]) => v - o.h / 2));
    const ok = b.x >= safe.side && b.x + b.w <= W - safe.side && top >= safe.top && top + b.h <= H - safe.bottom;
    if (!ok) problem(`${cut.id}/${variant}: ${o.role} overlay ${b.w}×${b.h} at ${b.x},${top} leaves the safe zone`);
  }
  encodeMaster(base, wav, ovs, outFile, plan.total);
  // AAC can overshoot the limiter at hard cuts: re-master with a lower ceiling until the file's true peak is ≤ −1 dBTP.
  let lq = loudness(outFile), limit = TP_LIMIT;
  for (let k = 0; k < 3 && Number.isFinite(lq.TP) && lq.TP > -1.05; k++) {
    limit -= lq.TP + 1.25;
    log(`${path.basename(outFile)}: true peak ${lq.TP} dBTP; re-mastering with a ${limit.toFixed(2)} dBFS ceiling`);
    masterAudio(joinedWav, sfx, wav, plan.total, limit);
    encodeMaster(base, wav, ovs, outFile, plan.total);
    lq = loudness(outFile);
  }
  // QC
  const name = path.basename(outFile, ".mp4");
  const facts = probeFacts(outFile);
  const breaks = [];
  for (const s of plan.segs) {
    if (s.kind !== "clip" || s.isReal || s.audio === "slomo" || s.layout === "cover") continue;
    const f = clipTime(s.clip, "failure");
    // Only breaks at least 0.35 s from a cut: a cut is itself a brightness jump and a sound onset.
    if (f !== null && f > s.from + 0.35 && f < s.from + s.dur - 0.35) breaks.push(s.start + (f - s.from));
  }
  const coverT = cut.cover ? cutTime(plan, cut.cover) : null;
  const times = [["hook", 0.5], ["break", breaks[0] !== undefined ? breaks[0] + 0.5 : (coverT ?? plan.total / 2)], ["mid", plan.total / 2], ["end", plan.total - 0.1]];
  const fr = DRY ? [] : stills(outFile, name, times);
  if (!DRY) {
    safeComposite(fr[0], path.join(WORK, safePng), path.join(QC, "frames", `${name}-hook-safe.png`));
    safeComposite(fr[3], path.join(WORK, safePng), path.join(QC, "frames", `${name}-end-safe.png`));
    fs.mkdirSync(path.join(QC, "sheets"), { recursive: true });
    contactSheet(outFile, path.join(QC, "sheets", `${name}.jpg`), plan.total);
  }
  const syncs = breaks.map((t) => ({ t, ...(syncCheck(outFile, t) || {}) }));
  const res = { id: cut.id, variant, file: outFile, total: plan.total, facts, mix: loud, loud: lq, syncs,
    segs: plan.segs.map((s) => `${s.kind}${s.clip ? ":" + s.clip.name + (s.isReal ? "(REAL)" : "") : ""}@${f3(s.start)}+${f3(s.dur)}`),
    overlays: ovs.map((o) => `${o.role} ${f3(o.from)}–${f3(o.to)}`), coverT, plan };
  checkSpecs(res, safe);
  results.push(res);
  return res;
}

function checkSpecs(r) {
  if (DRY) return;
  const v = r.facts.v || {}, a = r.facts.a || {};
  const bad = [];
  if (v.width !== W || v.height !== H) bad.push(`size ${v.width}x${v.height}`);
  if (v.codec_name !== "h264" || !/High/.test(v.profile || "")) bad.push(`video ${v.codec_name} ${v.profile}`);
  if (v.r_frame_rate !== "30/1") bad.push(`fps ${v.r_frame_rate}`);
  if (a.codec_name !== "aac" || +a.sample_rate !== 48000 || +a.channels !== 2) bad.push(`audio ${a.codec_name} ${a.sample_rate} ${a.channels}ch`);
  if (!(r.loud.I <= -13.5 && r.loud.I >= -16.5)) bad.push(`loudness ${r.loud.I} LUFS`);
  if (!(r.loud.TP <= -1.0)) bad.push(`true peak ${r.loud.TP} dBTP`);
  for (const s of r.syncs) if (Number.isFinite(s.offset) && Math.abs(s.offset) > 0.1) bad.push(`sync ${f3(s.offset)} s at ${f3(s.t)} s`);
  if (bad.length) problem(`${path.basename(r.file)}: ${bad.join("; ")}`);
}

// Reels / ad masters
for (const cut of CUTS) {
  if (ONLY && !new RegExp(ONLY).test(cut.id)) continue;
  const dir = path.join(OUT, cut.week === "launch" ? "reels" : "reels-week3+");
  fs.mkdirSync(dir, { recursive: true });
  for (const variant of VARIANTS) {
    try {
      const r = await buildMaster(cut, variant, path.join(dir, `${cut.id}-${variant}.mp4`));
      if (r && variant === "organic" && r.coverT !== null && !DRY) {
        // The cover: the mid-break frame with the hook text on it.
        const hookOv = (await buildOverlays(cut, "organic", r.plan, browser, assets)).find((o) => o.role === "hook");
        const cover = path.join(dir, `${cut.id}-cover.png`);
        const frame = path.join(WORK, `${cut.id}-coverframe.png`);
        ff(["-ss", f3(r.coverT), "-i", r.file, "-frames:v", "1", "-update", "1", frame]);
        if (hookOv) {
          const b = ovBox(hookOv);
          ff(["-i", frame, "-i", hookOv.png, "-filter_complex", `[0:v][1:v]overlay=${b.x}:${b.y}`, "-frames:v", "1", "-update", "1", cover]);
        } else fs.copyFileSync(frame, cover);
      }
    } catch (e) { problem(`${cut.id}/${variant}: ${e.message.split("\n").slice(0, 6).join(" | ")}`); }
  }
}

// Story clips (Stories keep-clear: top 270, bottom 384)
for (const sc of STORY_CUTS) {
  if (ONLY && !new RegExp(ONLY).test(sc.id)) continue;
  const parent = sc.from ? CUTS.find((c) => c.id === sc.from) : null;
  const cut = { ...(parent || {}), ...sc, id: sc.id, week: "launch" };
  if (parent && sc.segments && typeof sc.segments[0] === "number") cut.segments = sc.segments.map((i) => parent.segments[i]);
  cut.segments = (cut.segments || []).filter((s) => !s.only || s.only === "organic");
  if (sc.noEnd) cut.end = null;
  if ("hook" in sc) cut.hook = sc.hook;
  const dir = path.join(OUT, "stories"); fs.mkdirSync(dir, { recursive: true });
  try { await buildMaster(cut, "organic", path.join(dir, `${sc.id}.mp4`), { safe: R.SAFE.stories, safePng: "safe-stories.png" }); }
  catch (e) { problem(`${sc.id}: ${e.message.split("\n").slice(0, 6).join(" | ")}`); }
}
// One sheet of every cover (qc/contact-sheet.png) and one of every master's hook / break / end frames
// (qc/frames-sheet.png), for review at a glance.
if (browser) {
  const covers = CUTS.map((c) => path.join(OUT, c.week === "launch" ? "reels" : "reels-week3+", `${c.id}-cover.png`)).filter((f) => fs.existsSync(f));
  if (covers.length) {
    await browser.png(`<!doctype html><html><head><meta charset="utf-8"><style>${R.baseCSS()}
      body{margin:0;background:#1d1e21;width:${covers.length * 370 + 10}px;height:720px;display:flex;gap:10px;padding:10px;box-sizing:border-box}
      figure{margin:0;width:360px;color:#F3EEE6;font-size:22px;text-align:center} img{width:360px;height:640px;display:block;border-radius:12px}</style></head>
      <body>${covers.map((f) => `<figure><img src="${R.fileURL(f)}"><figcaption>${path.basename(f, "-cover.png")}</figcaption></figure>`).join("")}</body></html>`,
    path.join(QC, "contact-sheet.png"), { width: covers.length * 370 + 10, height: 720, transparent: false });
  }
  const rows = results.filter((r) => r.variant === "organic" || r.variant === "ad-uk");
  const cell = (r, label) => { const f = path.join(QC, "frames", `${path.basename(r.file, ".mp4")}-${label}.png`); return fs.existsSync(f) ? `<img src="${R.fileURL(f)}">` : "<div></div>"; };
  if (rows.length) {
    const h = rows.length * 330 + 20;
    await browser.png(`<!doctype html><html><head><meta charset="utf-8"><style>${R.baseCSS()}
      body{margin:0;background:#1d1e21;width:1060px;height:${h}px;padding:10px;box-sizing:border-box;color:#F3EEE6;font-size:20px}
      .r{display:flex;gap:8px;height:322px;margin-bottom:8px;align-items:center} .r span{width:220px} img,.r div{width:180px;height:320px;border-radius:8px}</style></head>
      <body>${rows.map((r) => `<div class="r"><span>${path.basename(r.file, ".mp4")}</span>${cell(r, "hook")}${cell(r, "break")}${cell(r, "mid")}${cell(r, "end")}</div>`).join("")}</body></html>`,
    path.join(QC, "frames-sheet.png"), { width: 1060, height: h, transparent: false });
  }
  await browser.close();
}

// ---- report ---------------------------------------------------------------------------------------------------------------
const lines = ["# Marketing kit: compose report", "", `Generated ${new Date().toISOString()}.`, "",
  "| File | Length | Size | Video | Audio | Loudness (I / true peak / LRA) | Sync at the break (sound − flash) |",
  "|---|---|---|---|---|---|---|"];
for (const r of results) {
  const v = r.facts.v || {}, a = r.facts.a || {};
  lines.push(`| ${path.relative(OUT, r.file).replace(/\\/g, "/")} | ${f3(r.facts.dur || r.total)} s | ${((r.facts.size || 0) / 1e6).toFixed(1)} MB | ${v.width}×${v.height} ${v.codec_name} ${v.profile} L${v.level} ${v.r_frame_rate} ${r.facts.kbps} kb/s | ${a.codec_name} ${a.sample_rate} Hz ${a.channels} ch | ${r.loud.I} LUFS / ${r.loud.TP} dBTP / ${r.loud.LRA} LU | ${r.syncs.map((s) => (Number.isFinite(s.offset) ? `${f3(s.offset)} s` : "n/a")).join(", ") || "–"} |`);
}
lines.push("", "## Cut lists", "");
for (const r of results) lines.push(`- **${path.basename(r.file)}**: ${r.segs.join(" · ")}; overlays: ${r.overlays.join(", ")}`);
lines.push("", "## Problems", "", ...(problems.length ? problems.map((p) => `- ${p}`) : ["- none"]), "", "## Log", "", ...report.map((l) => `    ${l}`));
fs.writeFileSync(path.join(OUT, "REPORT.md"), lines.join("\n") + "\n");
fs.writeFileSync(path.join(OUT, "results.json"), JSON.stringify(results.map(({ plan, ...r }) => r), null, 1));
console.log(`\n${results.length} master(s), ${problems.length} problem(s). REPORT: ${path.join(OUT, "REPORT.md")}`);
