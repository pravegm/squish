// Cuts the bundled sample set from decoded sources (design/SOUND-2.md §5).
//   node ci/sounds/cut.mjs <decoded-dir> ci/sounds/cuts.tsv <out-dir> [--wav]
// For every row of cuts.tsv: slice [start, end] from <decoded>/<src>.wav, high-pass (and optional low-pass),
// fade, optionally make a seamless loop, normalise, cap the true peak at -1 dBTP and write a 48 kHz mono
// 16-bit CAF to <out>/<path>. Also writes ci/sounds/report.tsv (loudness per file; kept out of the bundle) and <out>/LICENSES.md
// (provenance for every file, generated from ci/sounds/sources.tsv so nothing can ship unrecorded).
//
// cuts.tsv columns (tab-separated, '#' lines ignored):
//   path    e.g. glass/glass_break_01.caf (basenames must be unique: Xcode flattens resources)
//   src     key in sources.tsv (Kenney zip members: <key>--<member>)
//   start   seconds
//   end     seconds
//   fade    "in,out" in ms (e.g. 2,40)
//   norm    m<LUFS> momentary-max loudness | i<LUFS> integrated (beds) | p<dBFS> sample peak (grains);
//           an "L<dB>" suffix (m-14L8) allows that much look-ahead limiting on peaky transients to reach the target
//   hp      high-pass Hz (0 = off)
//   lp      low-pass Hz (0 = off)
//   loop    0 | crossfade ms for a seamless loop (the file then starts and ends on the same material)
//   eq      '-' or ';'-separated bands: pk<Hz>:<dB>:<Q> (peak/notch), hs<Hz>:<dB> (high shelf), ls<Hz>:<dB> (low shelf)
//   note    free text: what the layer is for

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWav, writeCaf, writeWav, filter, biquad, loudness, truePeak, stft, bands, db, onsets } from './dsp.mjs';

const [decoded, cutsPath, outDir, ...flags] = process.argv.slice(2);
if (!decoded || !cutsPath || !outDir) {
  console.error('usage: node cut.mjs <decoded-dir> <cuts.tsv> <out-dir> [--wav]');
  process.exit(2);
}
const alsoWav = flags.includes('--wav');
const here = path.dirname(fileURLToPath(import.meta.url));
const sourcesPath = path.join(here, 'sources.tsv');
const CEILING = -1; // dBTP

const sources = {};
for (const line of fs.readFileSync(sourcesPath, 'utf8').split(/\r?\n/).slice(1)) {
  const [key, kind, url, sha256, source, author, title, page, licence] = line.split('\t');
  if (key) sources[key] = { key, kind, url, sha256, source, author, title, page, licence };
}

const rows = fs.readFileSync(cutsPath, 'utf8').split(/\r?\n/)
  .filter(l => l.trim() && !l.startsWith('#') && !l.startsWith('path\t'))
  .map(l => {
    const [p, src, start, end, fade, norm, hp, lp, loop, note = ''] = l.split('\t');
    return { path: p, src, start: +start, end: +end, fade: (fade || '2,30').split(',').map(Number), norm, hp: +hp || 0, lp: +lp || 0, loop: +loop || 0, note };
  });

const names = new Map();
for (const r of rows) {
  const base = path.basename(r.path);
  if (names.has(base)) throw new Error(`duplicate basename ${base} (${names.get(base)} and ${r.path})`);
  names.set(base, r.path);
}

/** Look-ahead peak limiter: 1.5 ms look-ahead (instant attack), 40 ms release. Keeps transients crisp but denser. */
function limit(x, rate, ceiling) {
  const la = Math.round(0.0015 * rate), rel = Math.exp(-1 / (0.04 * rate));
  const need = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) {
    let m = 0;
    for (let k = i; k < Math.min(x.length, i + la); k++) m = Math.max(m, Math.abs(x[k]));
    need[i] = m > ceiling ? ceiling / m : 1;
  }
  const out = new Float32Array(x.length);
  let g = 1;
  for (let i = 0; i < x.length; i++) {
    g = need[i] < g ? need[i] : 1 - (1 - g) * rel;
    if (g > need[i]) g = need[i];
    out[i] = x[i] * g;
  }
  return out;
}

const cache = new Map();
const load = key => {
  if (!cache.has(key)) cache.set(key, readWav(path.join(decoded, `${key}.wav`)));
  return cache.get(key);
};

const report = [['path', 'src', 'dur_s', 'lufs_i', 'lufs_m_max', 'true_peak_dbtp', 'gain_db', 'centroid_hz', 'harsh_2.5-4.5k', 'note']];
const used = new Map();
let totalBytes = 0;

for (const r of rows) {
  const { rate, data } = load(r.src);
  if (rate !== 48000) throw new Error(`${r.src}: expected 48 kHz, got ${rate}`);
  const s0 = Math.max(0, Math.round(r.start * rate));
  const s1 = Math.min(data.length, Math.round(r.end * rate));
  if (s1 - s0 < rate * 0.004) throw new Error(`${r.path}: slice too short`);
  // Filter a little context around the slice so the filters are settled at the cut.
  const pre = Math.min(s0, Math.round(0.05 * rate));
  let x = data.slice(s0 - pre, s1);
  if (r.hp) x = filter(filter(x, biquad('hp', r.hp, rate, 0.7071)), biquad('hp', r.hp, rate, 0.7071));
  if (r.lp) x = filter(filter(x, biquad('lp', r.lp, rate, 0.7071)), biquad('lp', r.lp, rate, 0.7071));
  for (const band of (r.eq && r.eq !== '-' ? r.eq.split(';') : [])) {
    const m = band.match(/^(pk|hs|ls)(d+(?:.d+)?):(-?d+(?:.d+)?)(?::(d+(?:.d+)?))?$/);
    if (!m) throw new Error(`${r.path}: bad eq band ${band}`);
    const type = { pk: 'peak', hs: 'hshelf', ls: 'lshelf' }[m[1]];
    x = filter(x, biquad(type, +m[2], rate, m[4] ? +m[4] : 0.7071, +m[3]));
  }
  x = x.slice(pre);
  if (!r.loop) {
    // Auto-trim: start 3 ms before the first sample within 40 dB of the peak; end once the 10 ms RMS stays 60 dB down.
    let peak = 0; for (const v of x) peak = Math.max(peak, Math.abs(v));
    const onAt = peak * Math.pow(10, -40 / 20);
    let a = 0; while (a < x.length && Math.abs(x[a]) < onAt) a++;
    a = Math.max(0, a - Math.round(0.003 * rate));
    const w = Math.round(0.01 * rate), offDb = db(peak) - 60;
    let z = x.length;
    for (let i = x.length - w; i > a; i -= w) {
      let s = 0; for (let k = i; k < i + w; k++) s += x[k] * x[k];
      if (db(Math.sqrt(s / w)) > offDb) { z = Math.min(x.length, i + 2 * w); break; }
    }
    x = x.slice(a, z);
  }

  if (r.loop) {
    // Seamless loop: crossfade the tail into the head (equal power), then drop the tail.
    const n = Math.min(Math.round(r.loop / 1000 * rate), Math.floor(x.length / 3));
    const body = x.slice(0, x.length - n);
    for (let i = 0; i < n; i++) {
      const t = i / n;
      body[i] = x[i] * Math.sin(t * Math.PI / 2) + x[x.length - n + i] * Math.cos(t * Math.PI / 2);
    }
    x = body;
  } else {
    const fi = Math.round(r.fade[0] / 1000 * rate), fo = Math.round(r.fade[1] / 1000 * rate);
    for (let i = 0; i < Math.min(fi, x.length); i++) x[i] *= 0.5 - 0.5 * Math.cos(Math.PI * i / fi);
    for (let i = 0; i < Math.min(fo, x.length); i++) x[x.length - 1 - i] *= 0.5 - 0.5 * Math.cos(Math.PI * i / fo);
  }

  // Normalise. "m-16L6" = momentary-max -16 LUFS, allowing up to 6 dB of transient limiting to get there.
  const nm = r.norm.match(/^([mip])(-?\d+(?:\.\d+)?)(?:L(\d+(?:\.\d+)?))?$/);
  if (!nm) throw new Error(`${r.path}: bad norm ${r.norm}`);
  const kind = nm[1], target = +nm[2], maxLimit = nm[3] ? +nm[3] : 0;
  const L = loudness(x, rate);
  let pk = 0; for (const v of x) pk = Math.max(pk, Math.abs(v));
  let gain;
  if (kind === 'm') gain = target - L.momentaryMax;
  else if (kind === 'i') gain = target - (Number.isFinite(L.integrated) ? L.integrated : L.momentaryMax);
  else gain = target - db(pk);
  const tp = truePeak(x);
  // Without limiting the true peak caps the gain; with it, the cap moves up by at most maxLimit dB.
  gain = Math.min(gain, CEILING + maxLimit - tp);
  const g = Math.pow(10, gain / 20);
  for (let i = 0; i < x.length; i++) x[i] *= g;
  if (maxLimit > 0) x = limit(x, rate, Math.pow(10, (CEILING - 0.5) / 20));
  const tpAfter = truePeak(x);
  if (tpAfter > CEILING) { const t = Math.pow(10, (CEILING - tpAfter) / 20); for (let i = 0; i < x.length; i++) x[i] *= t; }

  const out = path.join(outDir, r.path);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  writeCaf(out, x, rate);
  if (alsoWav) writeWav(out.replace(/\.caf$/, '.wav'), x, rate);
  totalBytes += fs.statSync(out).size;

  const after = loudness(x, rate);
  const spec = stft(x, rate, 1024, 512);
  const skip = Math.min(spec.frames.length - 1, Math.ceil(0.03 * rate / 512));
  const b = bands(spec, skip);
  report.push([r.path, r.src, (x.length / rate).toFixed(3), Number.isFinite(after.integrated) ? after.integrated.toFixed(1) : '-',
    after.momentaryMax.toFixed(1), truePeak(x).toFixed(1), gain.toFixed(1), Math.round(b.centroid), b.harsh.toFixed(2), r.note]);

  const srcKey = r.src.split('--')[0];
  if (!sources[srcKey]) throw new Error(`${r.path}: ${srcKey} is not in sources.tsv`);
  // Audio-derived haptic events (design/SOUND-2.md §4): one transient per audible onset, intensity from its level
  // relative to the file peak, sharpness from its spectral centroid. Loops get none (the bed is continuous).
  let haptics = [];
  if (!r.loop) {
    const fileDb = db(x.reduce((m, v) => Math.max(m, Math.abs(v)), 0));
    // The file's own attack (onset detection needs a couple of frames of history, so it can miss t ≈ 0).
    const filePk = Math.pow(10, fileDb / 20);
    let a0 = 0; while (a0 < x.length && Math.abs(x[a0]) < filePk * 0.25) a0++;
    let local = 0; for (let k = a0; k < Math.min(x.length, a0 + Math.round(0.02 * rate)); k++) local = Math.max(local, Math.abs(x[k]));
    const sp0 = stft(x.subarray(a0, Math.min(x.length, a0 + 4096)).length >= 1024 ? x.subarray(a0, a0 + 4096) : Float32Array.from({ length: 1024 }, (_, i) => x[a0 + i] || 0), rate, 1024, 256);
    const c0 = bands(sp0, 0, 4).centroid;
    haptics.push([+(a0 / rate).toFixed(3), +Math.min(1, Math.max(0.15, 1 + db(local / filePk) / 30)).toFixed(2), +Math.min(0.95, Math.max(0.05, Math.log(Math.max(c0, 200) / 200) / Math.log(40))).toFixed(2)]);
    let last = a0 / rate;
    for (const o of onsets(x, rate, { floorDb: fileDb - 30, minGapMs: 12 })) {
      // Haptic time = the attack (first sample at half the local peak), not the later peak.
      const pk = Math.pow(10, o.peakDb / 20) * 0.5;
      let a = Math.round(o.t * rate); const pi = Math.round(o.peakT * rate);
      while (a < pi && Math.abs(x[a]) < pk) a++;
      const t = a / rate;
      if (haptics.length >= 24 || t - last < 0.012) continue;
      const intensity = Math.min(1, Math.max(0.15, 1 + (o.peakDb - fileDb) / 30));
      const sharpness = Math.min(0.95, Math.max(0.05, Math.log(Math.max(o.centroid, 200) / 200) / Math.log(40)));
      haptics.push([+t.toFixed(3), +intensity.toFixed(2), +sharpness.toFixed(2)]);
      last = t;
    }
  }
  if (!used.has(r.path)) used.set(r.path, { row: r, source: sources[srcKey], member: r.src.includes('--') ? r.src.split('--')[1] : '', dur: +(x.length / rate).toFixed(3), haptics });
}

fs.writeFileSync(path.join(here, 'report.tsv'), report.map(r => r.join('\t')).join('\n') + '\n');

// ---------- LICENSES.md ----------
const byLicence = {};
for (const { source } of used.values()) byLicence[source.licence] = (byLicence[source.licence] || 0) + 1;
const lines = [];
lines.push('# Squish sound provenance');
lines.push('');
lines.push('Every audio file under `Squish/Resources/Sounds/` is listed here with its source, author, licence and URL.');
lines.push('This file is **generated** by `ci/sounds/cut.mjs` from `ci/sounds/sources.tsv` and `ci/sounds/cuts.tsv`. Do not edit it by hand: change those two files and re-run the cut.');
lines.push('');
lines.push('## Licences in use');
lines.push('');
for (const [lic, n] of Object.entries(byLicence)) lines.push(`- **${lic}**: ${n} files. ${lic === 'CC0-1.0' ? 'Creative Commons Zero 1.0 (public-domain dedication): commercial use, modification and redistribution allowed; no attribution required. https://creativecommons.org/publicdomain/zero/1.0/' : ''}`);
lines.push('');
lines.push('Only CC0 material is committed, because this repository is public. Sonniss GDC, Pixabay, ZapSplat and paid-library material may be bundled in the app but must never be committed here (see design/SOUND-2.md §2).');
lines.push('');
lines.push('Courtesy credits (not required by CC0): Freesound contributors listed below, BigSoundBank (Joseph Sardin), Kenney (kenney.nl).');
lines.push('');
lines.push('## Sources used');
lines.push('');
lines.push('| Source key | Library | Author | Title | Licence | Page | File fetched (sha256) |');
lines.push('|---|---|---|---|---|---|---|');
const seenSrc = new Set();
for (const { source } of used.values()) {
  if (seenSrc.has(source.key)) continue;
  seenSrc.add(source.key);
  lines.push(`| ${source.key} | ${source.source} | ${source.author} | ${source.title.replace(/\|/g, '/')} | ${source.licence} | ${source.page} | ${source.url} (\`${source.sha256.slice(0, 16)}…\`) |`);
}
lines.push('');
lines.push('## Files');
lines.push('');
lines.push('| File | Source key | Excerpt (s) | Role |');
lines.push('|---|---|---|---|');
for (const { row, member } of used.values()) {
  lines.push(`| ${row.path} | ${row.src.split('--')[0]}${member ? ` (${member})` : ''} | ${row.start.toFixed(3)}–${row.end.toFixed(3)} | ${row.note} |`);
}
lines.push('');
fs.writeFileSync(path.join(outDir, 'LICENSES.md'), lines.join('\n'));

// ---------- sounds-manifest.json ----------
// Groups = files sharing a prefix (glass_shatter_01..NN). Class defaults come from the layer name (design/SOUND-2.md §3.2):
// gainDb is the starting mix trim at the bus, pitch the random spread in semitones, wet layers are dropped in Soft style.
const CLASS = [
  [/_loop$/, { kind: 'loop', gainDb: -14, pitch: 0 }],
  [/^(glass_shatter|can_crush|steel_crash|steel_snap)$/, { kind: 'hero', gainDb: 0, pitch: 0.5 }],
  [/(crack|snap|splat|split|honk|collapse|buckle|open_fizz|squirt|icing)$|^steel_groan$/, { kind: 'body', gainDb: -2, pitch: 0.7 }],
  [/^bubblewrap_pop/, { kind: 'grain', gainDb: -4, pitch: 1.5 }],
  [/(crumb|grit|crunch|crumple|squelch|squish|tick|clink)$/, { kind: 'grain', gainDb: -12, pitch: 1.5 }],
  [/(debris|ring|wheeze|slurp|wobble|boing|release|yolk)$/, { kind: 'tail', gainDb: -8, pitch: 0.7 }],
  [/^press_kachunk/, { kind: 'detail', gainDb: -4, pitch: 0 }],
  [/^ui_/, { kind: 'ui', gainDb: -14, pitch: 0.3 }],
];
const WET = /squelch|splat|yolk|squirt|slurp/;
const groups = {};
for (const [, { row, dur, haptics }] of used) {
  const base = path.basename(row.path, '.caf').replace(/_\d\d$/, '');
  const g = groups[base] || (groups[base] = { files: [], ...(CLASS.find(([re]) => re.test(base))?.[1] ?? { kind: 'detail', gainDb: -8, pitch: 0.7 }), wet: WET.test(base), loopFiles: !!row.loop });
  g.files.push({ name: path.basename(row.path, '.caf'), path: row.path, dur, haptics });
}
fs.writeFileSync(path.join(outDir, 'sounds-manifest.json'), JSON.stringify({
  generatedBy: 'ci/sounds/cut.mjs',
  format: 'CAF, 48 kHz, mono, 16-bit little-endian PCM',
  note: 'Group = the files sharing a prefix. Pick round-robin without immediate repeats; apply pitch (± semitones) and ±2 dB per play. gainDb is the starting bus trim. wet groups are dropped in the Soft style. Loops loop seamlessly as cut. Look files up by name (Xcode flattens the folders into the bundle root). haptics = [time s, intensity, sharpness] transients derived from the audio onsets, for a Core Haptics pattern started on the same clock as the sample.',
  groups,
}, null, 1) + '\n');

console.log(`cut ${rows.length} files, ${(totalBytes / 1048576).toFixed(2)} MB, from ${seenSrc.size} sources`);
