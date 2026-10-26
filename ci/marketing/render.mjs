// Squish marketing renderer: HTML/CSS → PNG with headless Chrome over the DevTools protocol (no npm packages; Node 22+
// for the global WebSocket and fetch). Used by ci/marketing/compose.mjs for the video overlays (hook, captions, comic
// words, counters, end cards) and by ci/marketing/statics.mjs for the Stories, feed posts and profile kit.
//
// Type: Nunito Black (SIL Open Font License 1.1), docs/marketing/PLAN.md §0.1. Apple's SF Pro licence is written for
// designing Apple-platform UI, so marketing never uses it. CI fetches Nunito[wght].ttf from google/fonts at a pinned
// commit and checks its git blob hash (.github/workflows/marketing.yml); NUNITO_FONT points at it and the page loads it
// with @font-face url(file://…). Nothing is embedded in a deliverable: the text is rasterised into the PNG / video.
// Without NUNITO_FONT (a local preview) it falls back to any installed Nunito, then a heavy system face, so only CI
// output is final.
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const W = 1080;
export const H = 1920;

/** Brand tokens (bible §5 "Visual language"). */
export const C = {
  paper: "#F3EEE6", graphite: "#2B2D31", yellow: "#FFB81C", red: "#D7263D", raspberry: "#E8336F",
  lime: "#8BD448", duck: "#FFD23F", cobalt: "#2F5BEA", cream: "#FBF7F0", ink: "#1E1F23", steel: "#C9C6C0",
};

export function fontReport() {
  const home = os.homedir();
  const list = [process.env.NUNITO_FONT, path.join(home, "Library/Fonts/Nunito[wght].ttf"), "/Library/Fonts/Nunito[wght].ttf",
    path.join(home, "AppData/Local/Microsoft/Windows/Fonts/Nunito[wght].ttf")];
  return { nunito: list.find((f) => f && fs.existsSync(f)) || null };
}

/** Shared CSS: the faces, the tokens, and the highlight rule (`*word*` in copy). */
export function baseCSS() {
  const f = fontReport();
  const face = f.nunito
    ? `@font-face{font-family:SquishNunito;src:url("${pathToFileURL(f.nunito).href}") format("truetype");font-weight:200 1000;font-style:normal;}`
    : "";
  return `
${face}
:root{--paper:${C.paper};--graphite:${C.graphite};--yellow:${C.yellow};--red:${C.red};--cream:${C.cream};--ink:${C.ink};
  --rounded:SquishNunito,"Nunito","Nunito Black","Segoe UI Black","Arial Black",sans-serif;
  --mono:SquishNunito,"Nunito","Segoe UI Black",sans-serif;}
*{box-sizing:border-box;margin:0;padding:0;}
html,body{background:transparent;-webkit-font-smoothing:antialiased;text-rendering:geometricPrecision;}
body{font-family:var(--rounded);font-weight:900;color:var(--graphite);font-variant-numeric:tabular-nums;}
.mono{font-family:var(--mono);font-weight:800;letter-spacing:.08em;text-transform:uppercase;}
em.hl{font-style:normal;background:linear-gradient(transparent 12%,var(--yellow) 12%,var(--yellow) 88%,transparent 88%);
  padding:0 .12em;margin:0 -.04em;border-radius:.12em;-webkit-box-decoration-break:clone;box-decoration-break:clone;}
em.y{font-style:normal;color:var(--yellow);}
`;
}

/** `*word*` → highlighted span; escapes HTML. `style`: hl (yellow marker) | y (yellow text). */
export function rich(text, style = "hl") {
  const esc = String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return esc.replace(/\*([^*]+)\*/g, `<em class="${style}">$1</em>`).replace(/\n/g, "<br>");
}

/** Shrinks every `.fit` element's font until its text fits its box (no overflow, at most data-lines lines). */
export const FIT_JS = `
(async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map(i => i.decode ? i.decode().catch(() => {}) : 0));
  for (const el of document.querySelectorAll('.fit')) {
    const max = parseFloat(el.dataset.max || getComputedStyle(el).fontSize);
    const min = parseFloat(el.dataset.min || 20);
    const lines = parseInt(el.dataset.lines || '9', 10);
    const boxH = el.dataset.h ? parseFloat(el.dataset.h) : Infinity;
    let size = max;
    for (;;) {
      el.style.fontSize = size + 'px';
      const lh = parseFloat(getComputedStyle(el).lineHeight) || size * 1.1;
      const tooTall = el.scrollHeight > boxH + 1 || el.getBoundingClientRect().height > lh * lines + 2;
      const tooWide = el.scrollWidth > el.clientWidth + 1;
      if ((!tooTall && !tooWide) || size <= min) break;
      size = Math.max(min, size * 0.96);
    }
  }
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  return true;
})()`;

function chromePath() {
  const env = process.env.CHROME;
  const list = [env, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "C:/Program Files/Google/Chrome/Application/chrome.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"];
  const hit = list.find((p) => p && fs.existsSync(p));
  if (!hit) throw new Error("no Chrome found (set CHROME)");
  return hit;
}

/** A headless Chrome with one page, driven over CDP. `await b.png(html, out, opts)`; `await b.close()`. */
export async function browser({ port = 9300 + Math.floor(Math.random() * 500) } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "squish-render-"));
  const proc = spawn(chromePath(), [
    "--headless=new", `--remote-debugging-port=${port}`, "--no-first-run", "--no-default-browser-check",
    "--hide-scrollbars", "--allow-file-access-from-files", "--force-color-profile=srgb", "--disable-gpu",
    "--disable-lcd-text", "--font-render-hinting=none", `--user-data-dir=${path.join(tmp, "profile")}`, "about:blank",
  ], { stdio: ["ignore", "ignore", "ignore"] });
  let page;
  for (let i = 0; i < 100 && !page; i++) {
    await new Promise((r) => setTimeout(r, 150));
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      page = list.find((t) => t.type === "page");
    } catch { /* not up yet */ }
  }
  if (!page) { proc.kill(); throw new Error("Chrome did not start"); }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0;
  const pending = new Map();
  const waiters = [];
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) {
      const { res, rej } = pending.get(msg.id); pending.delete(msg.id);
      msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
    } else if (msg.method) {
      for (const w of [...waiters]) if (w.method === msg.method) { waiters.splice(waiters.indexOf(w), 1); w.res(msg.params); }
    }
  };
  const send = (method, params = {}) => new Promise((res, rej) => {
    const n = ++id; pending.set(n, { res, rej }); ws.send(JSON.stringify({ id: n, method, params }));
  });
  const once = (method, ms = 20000) => new Promise((res, rej) => {
    const w = { method, res }; waiters.push(w);
    setTimeout(() => { const i = waiters.indexOf(w); if (i >= 0) { waiters.splice(i, 1); rej(new Error("timeout " + method)); } }, ms);
  });
  await send("Page.enable");
  await send("Runtime.enable");
  let count = 0;

  /**
   * Renders `html` (a full document or a body fragment) to `out` (PNG).
   * opts: width, height (viewport), transparent (default true), clip: CSS selector to crop to (its bounding box, with
   * `pad` px), returns { width, height, x, y } of the written image (x, y: where it sat on the page).
   */
  async function png(html, out, { width = W, height = H, transparent = true, clip = null, pad = 0, format = "png", quality = 82 } = {}) {
    const doc = /<html/i.test(html) ? html
      : `<!doctype html><html><head><meta charset="utf-8"><style>${baseCSS()}</style></head><body>${html}</body></html>`;
    const file = path.join(tmp, `p${++count}.html`);
    fs.writeFileSync(file, doc);
    await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await send("Emulation.setDefaultBackgroundColorOverride", transparent ? { color: { r: 0, g: 0, b: 0, a: 0 } } : {});
    const loaded = once("Page.loadEventFired");
    await send("Page.navigate", { url: pathToFileURL(file).href });
    await loaded;
    await send("Runtime.evaluate", { expression: FIT_JS, awaitPromise: true });
    let box = { x: 0, y: 0, width, height };
    if (clip) {
      const r = await send("Runtime.evaluate", {
        expression: `(() => { const els = [...document.querySelectorAll(${JSON.stringify(clip)})]; if (!els.length) return null;
          let a = Infinity, b = Infinity, c = -Infinity, d = -Infinity;
          for (const e of els) { const q = e.getBoundingClientRect(); a = Math.min(a, q.left); b = Math.min(b, q.top); c = Math.max(c, q.right); d = Math.max(d, q.bottom); }
          return JSON.stringify({ x: a, y: b, width: c - a, height: d - b }); })()`,
        returnByValue: true,
      });
      if (r.result && r.result.value) {
        const q = JSON.parse(r.result.value);
        const x = Math.max(0, Math.floor(q.x - pad)), y = Math.max(0, Math.floor(q.y - pad));
        box = { x, y, width: Math.min(width - x, Math.ceil(q.width + 2 * pad)), height: Math.min(height - y, Math.ceil(q.height + 2 * pad)) };
        // Even sizes, so ffmpeg can place it at a centre without half pixels.
        box.width -= box.width % 2; box.height -= box.height % 2;
      }
    }
    const shot = await send("Page.captureScreenshot", {
      format, ...(format === "jpeg" ? { quality } : {}), fromSurface: true, captureBeyondViewport: false,
      clip: { x: box.x, y: box.y, width: box.width, height: box.height, scale: 1 },
    });
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, Buffer.from(shot.data, "base64"));
    return box;
  }

  async function close() {
    try { ws.close(); } catch { /* gone */ }
    proc.kill();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* still locked on Windows */ }
  }
  return { png, close };
}

export function fileURL(p) { return pathToFileURL(path.resolve(p)).href; }

// ---- video overlay templates (each rendered alone, cropped to `.o`) -----------------------------------------------
// The caption rule (PLAN.md §0.1): graphite #2B2D31 text on an off-white #F3EEE6 pill, one word in hydraulic yellow
// #FFB81C. The yellow word is a marker behind graphite type, not yellow type: yellow on off-white is ~1.6:1 contrast
// and would vanish on a phone; graphite on yellow is ~9:1.

const pillCSS = (size, pad = "0.34em 0.78em 0.40em") => `
  .wrap{position:absolute;left:0;top:40px;width:${W}px;display:flex;justify-content:center;}
  .o{max-width:${W - 2 * 72}px;padding:${pad};background:var(--paper);color:var(--graphite);border-radius:${Math.round(size * 0.62)}px;
     box-shadow:0 ${Math.round(size * 0.16)}px ${Math.round(size * 0.42)}px rgba(18,18,22,.30),0 0 0 2px rgba(43,45,49,.08);
     font-size:${size}px;line-height:1.08;text-align:center;letter-spacing:-.005em;}
  .o em.hl{padding:0 .14em;}`;

/** The hook: ≤ 6 words, lowercase, deadpan, the key word on a yellow marker. */
export function hookHTML(text, { size = 86 } = {}) {
  return `<style>${pillCSS(size)}</style><div class="wrap"><div class="o fit" data-max="${size}" data-min="48" data-lines="2">${rich(text)}</div></div>`;
}

/** A later line ("slowly…", "ka-chunk."): the same pill, a size down. */
export function captionHTML(text, { size = 64 } = {}) {
  return `<style>${pillCSS(size)}</style><div class="wrap"><div class="o fit" data-max="${size}" data-min="40" data-lines="2">${rich(text)}</div></div>`;
}

/** The required small line on cuts that show a phone: "everything's on screen. nothing real goes inside." */
export function finePrintHTML(text, { size = 30, dark = false } = {}) {
  return `<style>
  .wrap{position:absolute;left:0;top:40px;width:${W}px;display:flex;justify-content:center;}
  .o{padding:10px 22px 12px;border-radius:999px;font-size:${size}px;font-weight:800;letter-spacing:.01em;
     color:${dark ? "var(--paper)" : "var(--graphite)"};background:${dark ? "rgba(43,45,49,.72)" : "rgba(243,238,230,.88)"};}
  </style><div class="wrap"><div class="o">${rich(text)}</div></div>`;
}

/** A comic sound word, as the app's Captions setting writes them ("POP!"): yellow, graphite outline. Optional. */
export function wordHTML(text, { size = 120, rotate = -6, color = C.yellow } = {}) {
  return `<style>
  .wrap{position:absolute;left:0;top:120px;width:${W}px;display:flex;justify-content:center;}
  .o{display:inline-block;transform:rotate(${rotate}deg);padding:24px 30px;}
  .w{font-size:${size}px;line-height:1;letter-spacing:.01em;color:${color};-webkit-text-stroke:${Math.round(size / 9)}px var(--graphite);
     paint-order:stroke fill;text-shadow:0 ${Math.round(size / 14)}px 0 var(--graphite),0 ${Math.round(size / 7)}px 22px rgba(0,0,0,.35);
     white-space:nowrap;}
  </style><div class="wrap"><div class="o"><div class="w">${rich(text)}</div></div></div>`;
}

/** A number badge for the line-up (C5): a graphite disc with an off-white numeral. */
export function numberHTML(n, { size = 120 } = {}) {
  return `<style>
  .wrap{position:absolute;left:40px;top:40px;}
  .o{width:${size}px;height:${size}px;border-radius:50%;background:var(--graphite);color:var(--paper);display:flex;
     align-items:center;justify-content:center;font-size:${Math.round(size * 0.62)}px;line-height:1;
     box-shadow:0 8px 22px rgba(0,0,0,.35),0 0 0 6px var(--paper);}
  </style><div class="wrap"><div class="o">${n}</div></div>`;
}

/** The corner watermark for C3 (no end card): a small "squish" wordmark. */
export function watermarkHTML({ size = 44 } = {}) {
  return `<style>
  .wrap{position:absolute;left:40px;top:40px;}
  .o{padding:8px 20px 12px;border-radius:999px;background:rgba(243,238,230,.84);color:var(--graphite);font-size:${size}px;
     line-height:1;letter-spacing:-.01em;box-shadow:0 4px 14px rgba(0,0,0,.18);}
  </style><div class="wrap"><div class="o">squish</div></div>`;
}

/** A touch indicator (C4, until the founder's S10 finger shot): a soft white disc with a ring, like iOS's own. */
export function touchHTML({ size = 120 } = {}) {
  return `<style>
  .wrap{position:absolute;left:40px;top:40px;}
  .o{width:${size}px;height:${size}px;border-radius:50%;background:radial-gradient(circle,rgba(255,255,255,.78) 0 52%,rgba(255,255,255,.30) 53% 64%,rgba(255,255,255,0) 66%);
     box-shadow:0 0 0 5px rgba(43,45,49,.35);}
  </style><div class="wrap"><div class="o"></div></div>`;
}

/**
 * The end card (≤ 1.5 s, PLAN.md §0.1), full frame 1080 × 1920; everything inside the Reels-ad safe zone
 * (y 270–1248, x 65–1015).
 *  - organic (`overlay`): a panel with the small "squish" wordmark and "out now on the App Store", laid over the
 *    looping last frame by compose.mjs (transparent page);
 *  - ad: an opaque card that may add `headline` and `price` ("£2.49 · no ads · no in-app purchases").
 *  `fine`: the "everything's on screen. nothing real goes inside." line, on cuts that show a phone.
 * No Apple badge is ever drawn: `badge` is only the founder's own downloaded file (docs/marketing/ASSETS.md).
 */
export function endCardHTML({ icon, headline = "", line = "out now on the App Store", price = "", fine = "",
  badge = null, overlay = false }) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${baseCSS()}
  body{width:${W}px;height:${H}px;position:relative;overflow:hidden;background:${overlay ? "transparent" : "var(--paper)"};}
  .bg{position:absolute;inset:0;background:radial-gradient(1100px 900px at 50% 38%,#fffaf2 0%,var(--paper) 55%,#e6dfd3 100%);}
  .band{position:absolute;left:0;right:0;top:0;height:26px;background:repeating-linear-gradient(-45deg,var(--graphite) 0 24px,var(--yellow) 24px 48px);}
  .panel{position:absolute;left:90px;right:90px;top:${overlay ? 470 : 300}px;display:flex;flex-direction:column;align-items:center;
     text-align:center;${overlay ? "padding:44px 40px 48px;background:rgba(243,238,230,.95);border-radius:56px;box-shadow:0 24px 60px rgba(0,0,0,.35);" : ""}}
  .icon{width:${overlay ? 150 : 250}px;height:${overlay ? 150 : 250}px;border-radius:${overlay ? 34 : 56}px;
     box-shadow:0 18px 44px rgba(30,28,25,.32),0 0 0 2px rgba(0,0,0,.06);}
  .name{font-size:${overlay ? 104 : 140}px;line-height:1;margin-top:${overlay ? 18 : 32}px;letter-spacing:-.02em;}
  .head{font-size:62px;line-height:1.08;margin-top:28px;max-width:880px;}
  .line{font-size:50px;line-height:1.12;margin-top:${headline ? 20 : 24}px;color:#4a4741;max-width:880px;}
  .price{margin-top:28px;font-size:42px;padding:16px 36px 20px;background:var(--yellow);border-radius:999px;
     box-shadow:0 10px 24px rgba(180,120,0,.25);max-width:900px;}
  .fine{margin-top:${price ? 24 : 28}px;font-size:28px;font-weight:800;color:#6a665f;}
  .badge{margin-top:26px;height:110px;}
  </style></head><body>${overlay ? "" : "<div class=\"bg\"></div><div class=\"band\"></div>"}
  <div class="panel">
    <img class="icon" src="${icon}">
    <div class="name">squish</div>
    ${headline ? `<div class="head fit" data-max="62" data-min="40" data-lines="2">${rich(headline)}</div>` : ""}
    ${line ? `<div class="line fit" data-max="50" data-min="34" data-lines="2">${rich(line)}</div>` : ""}
    ${price ? `<div class="price fit" data-max="42" data-min="30" data-lines="1">${rich(price)}</div>` : ""}
    ${badge ? `<img class="badge" src="${badge}">` : ""}
    ${fine ? `<div class="fine">${rich(fine)}</div>` : ""}
  </div></body></html>`;
}

/** The organic end card (≤ 1.5 s over the looping last frame): icon, a small "squish" wordmark and one line. */
export function endPillHTML({ icon, line = "out now on the App Store" }) {
  return `<style>
  .wrap{position:absolute;left:0;top:40px;width:${W}px;display:flex;justify-content:center;}
  .o{display:flex;align-items:center;gap:26px;max-width:${W - 2 * 72}px;padding:22px 40px 22px 22px;background:var(--paper);
     border-radius:999px;box-shadow:0 14px 36px rgba(18,18,22,.32),0 0 0 2px rgba(43,45,49,.08);}
  .i{width:104px;height:104px;border-radius:24px;flex:none;box-shadow:0 6px 14px rgba(0,0,0,.25);}
  .t{display:flex;flex-direction:column;gap:2px;min-width:0;}
  .n{font-size:58px;line-height:1;letter-spacing:-.02em;}
  .l{font-size:36px;line-height:1.1;color:#4a4741;}
  </style><div class="wrap"><div class="o"><img class="i" src="${icon}"><div class="t"><div class="n">squish</div>
  <div class="l fit" data-max="36" data-min="26" data-lines="2">${rich(line)}</div></div></div></div>`;
}

/** The C5 grid matte: the background with rounded windows for the 2 × 2 tiles. */
export function gridMatteHTML({ x0, y0, tile, gap, radius = 34, color = C.graphite }) {
  const holes = [0, 1, 2, 3].map((i) => {
    const x = x0 + (i % 2) * (tile + gap), y = y0 + Math.floor(i / 2) * (tile + gap), r = radius;
    return `M${x + r},${y} h${tile - 2 * r} a${r},${r} 0 0 1 ${r},${r} v${tile - 2 * r} a${r},${r} 0 0 1 -${r},${r} h-${tile - 2 * r} a${r},${r} 0 0 1 -${r},-${r} v-${tile - 2 * r} a${r},${r} 0 0 1 ${r},-${r} z`;
  }).join(" ");
  return `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent;}</style></head><body>
  <svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#34363b"/><stop offset="1" stop-color="${color}"/></linearGradient></defs>
  <path fill="url(#g)" fill-rule="evenodd" d="M0,0 H${W} V${H} H0 Z ${holes}"/>
  ${[0, 1, 2, 3].map((i) => { const x = x0 + (i % 2) * (tile + gap), y = y0 + Math.floor(i / 2) * (tile + gap);
    return `<rect x="${x + 1.5}" y="${y + 1.5}" width="${tile - 3}" height="${tile - 3}" rx="${radius}" fill="none" stroke="rgba(243,238,230,.55)" stroke-width="3"/>`; }).join("")}
  </svg></body></html>`;
}

/** Instagram's 9:16 keep-clear bands: the Reels-ad zone (Meta Ads Guide) and the organic Stories zone. */
export const SAFE = {
  reels: { top: 270, bottom: 672, side: 65 },
  stories: { top: 270, bottom: 384, side: 65 },
};

/** A translucent red mask over a zone's keep-clear bands (QC only). */
export function safeZoneHTML({ top = 270, bottom = 672, side = 65 } = {}) {
  const t = top, b = bottom, s = side;
  return `<style>.z{position:absolute;background:rgba(230,30,40,.30);} .l{position:absolute;border:3px dashed rgba(230,30,40,.95);}</style>
  <div class="z" style="left:0;top:0;width:${W}px;height:${t}px"></div>
  <div class="z" style="left:0;top:${H - b}px;width:${W}px;height:${b}px"></div>
  <div class="z" style="left:0;top:${t}px;width:${s}px;height:${H - t - b}px"></div>
  <div class="z" style="left:${W - s}px;top:${t}px;width:${s}px;height:${H - t - b}px"></div>
  <div class="l" style="left:${s}px;top:${t}px;width:${W - 2 * s}px;height:${H - t - b}px"></div>`;
}
