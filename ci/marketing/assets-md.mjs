#!/usr/bin/env node
// Writes the file table of docs/marketing/ASSETS.md (between the GENERATED markers) and its thumbnails from a composed
// kit: node ci/marketing/assets-md.mjs <kit dir> [<docs/marketing dir>]. Thumbnails are small JPEGs made with ffmpeg.
import fs from "node:fs";
import path from "node:path";
import { CUTS, STORY_CUTS } from "./cuts.mjs";
import * as R from "./render.mjs";

const KIT = path.resolve(process.argv[2] || "marketing-kit");
const DOCS = path.resolve(process.argv[3] || "docs/marketing");
const THUMBS = path.join(DOCS, "thumbs");
fs.mkdirSync(THUMBS, { recursive: true });
const results = JSON.parse(fs.readFileSync(path.join(KIT, "results.json"), "utf8"));
const rel = (f) => path.relative(KIT, f).replace(/\\/g, "/");
const browser = await R.browser();
function size(file) { const b = fs.readFileSync(file); if (b.readUInt32BE(0) === 0x89504e47) return [b.readUInt32BE(16), b.readUInt32BE(20)];
  let i = 2; while (i < b.length) { if (b[i] !== 0xff) { i++; continue; } const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return [b.readUInt16BE(i + 7), b.readUInt16BE(i + 5)]; i += 2 + b.readUInt16BE(i + 2); } return [1, 1]; }
const thumb = async (src, name, w) => {
  const out = path.join(THUMBS, name);
  const [iw, ih] = size(src), h = Math.round(w * ih / iw);
  await browser.png(`<!doctype html><html><body style="margin:0"><img src="${R.fileURL(src)}" style="display:block;width:${w}px;height:${h}px"></body></html>`,
    out, { width: w, height: h, transparent: false, format: "jpeg", quality: 80 });
  return `thumbs/${name}`;
};
const mb = (f) => (fs.statSync(f).size / 1e6).toFixed(1) + " MB";
const L = [];

L.push("### Reels and ads (1080 × 1920, 9:16)", "",
  "| File | Spec | Use | Caption hook (burned in) | Contact sheet |", "|---|---|---|---|---|");
for (const cut of CUTS) {
  for (const r of results.filter((x) => x.id === cut.id)) {
    const v = r.facts.v || {}, a = r.facts.a || {};
    const sheet = path.join(KIT, "qc", "sheets", path.basename(r.file, ".mp4") + ".jpg");
    const t = fs.existsSync(sheet) ? await thumb(sheet, path.basename(r.file, ".mp4") + ".jpg", 540) : null;
    const hook = typeof cut.hook === "object" ? (cut.hook[r.variant] ?? cut.hook.default) : cut.hook;
    L.push(`| \`${rel(r.file)}\`${cut.week !== "launch" ? " **(WEEK 3+)**" : ""} | ${(+r.facts.dur).toFixed(1)} s, ${v.width}×${v.height} ${v.codec_name} ${v.profile} ${v.r_frame_rate} fps, AAC ${a.sample_rate} Hz ${a.channels} ch, ${r.loud.I} LUFS / ${r.loud.TP} dBTP, ${mb(r.file)} | ${cut.concept} ${r.variant}: ${cut.use} | "${(hook || "").replace(/\*/g, "")}" | ${t ? `![](${t})` : "–"} |`);
  }
  const cover = path.join(KIT, cut.week === "launch" ? "reels" : "reels-week3+", `${cut.id}-cover.png`);
  if (fs.existsSync(cover)) {
    const t = await thumb(cover, `${cut.id}-cover.jpg`, 180);
    L.push(`| \`${rel(cover)}\` | 1080×1920 PNG | ${cut.concept} cover frame (the mid-break frame with the hook) | | ${t ? `![](${t})` : ""} |`);
  }
}
L.push("", "### Story clips (1080 × 1920; text inside y 270–1536)", "", "| File | Spec | Use | Contact sheet |", "|---|---|---|---|");
for (const sc of STORY_CUTS) {
  const r = results.find((x) => x.id === sc.id);
  if (!r) continue;
  const sheet = path.join(KIT, "qc", "sheets", sc.id + ".jpg");
  const t = fs.existsSync(sheet) ? await thumb(sheet, sc.id + ".jpg", 540) : null;
  L.push(`| \`${rel(r.file)}\` | ${(+r.facts.dur).toFixed(1)} s, H.264 + AAC, ${r.loud.I} LUFS | ${sc.use} | ${t ? `![](${t})` : "–"} |`);
}
// The stills, found on disk (the kit artifact leaves _work/ out).
const walk = (d) => fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]) : [];
const statics = { made: ["feed", "stories", "profile"].flatMap((d) => walk(path.join(KIT, d))).filter((f) => f.endsWith(".png") && !f.includes("guides")).map(rel).sort() };
const groups = [["feed/carousel/", "Launch carousel (1080 × 1350, 4:5; post the slides in order)"], ["feed/post-", "Single posts (1080 × 1350)"],
  ["stories/story", "Story stills (1080 × 1920); the `stories/guides/` copies mark the sticker spaces"], ["profile/", "Profile kit"]];
for (const [prefix, title] of groups) {
  const files = statics.made.filter((f) => f.startsWith(prefix));
  if (!files.length) continue;
  L.push("", `### ${title}`, "", "| File | Thumbnail |", "|---|---|");
  for (const f of files) {
    const t = await thumb(path.join(KIT, f), f.replace(/[\\/]/g, "_").replace(".png", ".jpg"), prefix === "profile/" ? 120 : 160);
    L.push(`| \`${f}\` | ${t ? `![](${t})` : ""} |`);
  }
}
const md = path.join(DOCS, "ASSETS.md");
const text = fs.readFileSync(md, "utf8");
const a = text.indexOf("<!-- GENERATED -->"), b = text.indexOf("<!-- /GENERATED -->");
if (a < 0 || b < 0) throw new Error("ASSETS.md needs <!-- GENERATED --> … <!-- /GENERATED --> markers");
fs.writeFileSync(md, text.slice(0, a + 18) + "\n" + L.join("\n") + "\n" + text.slice(b));
await browser.close();
console.log(`ASSETS.md: ${L.length} lines; thumbnails in ${THUMBS}`);
