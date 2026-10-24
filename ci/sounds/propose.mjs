// Proposes cuts.tsv rows by slicing a decoded source at its onsets (design/SOUND-2.md §5).
//   node ci/sounds/propose.mjs <decoded-dir> <src> <out-prefix> [options]
// Options (all optional):
//   --from S --to S        search window in seconds
//   --n N                  how many slices to keep (strongest first, then re-sorted by time)
//   --max S --min S        slice length bounds
//   --tail DB              end a slice once its 10 ms RMS falls DB below its peak (default 50)
//   --range DB             only keep onsets within DB of the loudest in the window (default 18)
//   --gap S                minimum time between kept onsets (default 0.08)
//   --pre MS               pre-roll before the detected attack (default 3)
//   --whole 1              keep a multi-transient event whole (no cut at the next onset; for breaks and heroes)
//   --hold MS              the tail must stay under --tail for this long before the slice ends (default 10)
//   --norm m-16 --hp 80 --lp 0 --fade 1,25 --eq pk3300:-6:1.5 --note "text" --first 1
// Prints rows; review them, then paste into ci/sounds/cuts.tsv.

import path from 'node:path';
import { readWav, onsets, db } from './dsp.mjs';

const [decoded, src, prefix, ...rest] = process.argv.slice(2);
const opt = { from: 0, to: 1e9, n: 8, max: 0.6, min: 0.03, tail: 50, range: 18, gap: 0.08, pre: 3, norm: 'm-16', hp: 80, lp: 0, fade: '1,25', eq: '-', note: '', first: 1, whole: 0, hold: 10 };
for (let i = 0; i < rest.length; i += 2) {
  const k = rest[i].replace(/^--/, ''), v = rest[i + 1];
  opt[k] = typeof opt[k] === 'number' ? +v : v;
}
const { rate, data } = readWav(path.join(decoded, `${src}.wav`));
const all = onsets(data, rate, { floorDb: -60 }).filter(o => o.t >= opt.from && o.t <= opt.to);
const loudest = Math.max(...all.map(o => o.peakDb));
const cand = [];
for (let j = 0; j < all.length; j++) {
  const o = all[j];
  if (o.peakDb < loudest - opt.range) continue;
  const pk = Math.pow(10, o.peakDb / 20);
  // Precise attack: first sample over -20 dB re the peak.
  let a = Math.round(o.t * rate);
  const pkI = Math.round(o.peakT * rate);
  while (a < pkI && Math.abs(data[a]) < pk * 0.1) a++;
  const start = Math.max(0, a - Math.round(opt.pre / 1000 * rate));
  if (opt.whole) {
    // Whole events start out of relative quiet: skip onsets that are a later transient of the same event.
    const b0 = Math.max(0, start - Math.round(0.06 * rate)), b1 = Math.max(b0 + 1, start - Math.round(0.005 * rate));
    let s = 0; for (let k = b0; k < b1; k++) s += data[k] * data[k];
    if (b1 - b0 > 10 && db(Math.sqrt(s / (b1 - b0))) > o.peakDb - 25) continue;
  }
  // Grains stop at the next strong onset; whole events (--whole 1) keep every transient up to --max.
  const next = opt.whole ? null : all.slice(j + 1).find(n => n.t > o.t + opt.gap && n.peakDb > o.peakDb - 24);
  const hardEnd = Math.min(data.length, start + Math.round(opt.max * rate), next ? Math.round(next.t * rate) : data.length);
  const w = Math.round(0.01 * rate), needQuiet = Math.max(1, Math.round(opt.hold / 10));
  let end = hardEnd, quiet = 0;
  for (let i = pkI; i + w < hardEnd; i += w) {
    let s = 0; for (let k = i; k < i + w; k++) s += data[k] * data[k];
    quiet = db(Math.sqrt(s / w)) < o.peakDb - opt.tail ? quiet + 1 : 0;
    if (quiet >= needQuiet) { end = i + w - (needQuiet - 1) * w; break; }
  }
  const len = (end - start) / rate;
  if (len < opt.min) continue;
  cand.push({ start: start / rate, end: end / rate, pk: o.peakDb, cen: o.centroid, harsh: o.harsh });
}
const kept = [];
for (const c of cand.sort((x, y) => y.pk - x.pk)) {
  if (kept.length >= opt.n) break;
  if (kept.some(k => Math.abs(k.start - c.start) < opt.gap)) continue;
  kept.push(c);
}
kept.sort((x, y) => x.start - y.start);
kept.forEach((c, i) => {
  const num = String(opt.first + i).padStart(2, '0');
  const note = `${opt.note}${opt.note ? '; ' : ''}pk ${c.pk.toFixed(1)} dB, centroid ${Math.round(c.cen)} Hz`;
  console.log([`${prefix}_${num}.caf`, src, c.start.toFixed(3), c.end.toFixed(3), opt.fade, opt.norm, opt.hp, opt.lp, 0, opt.eq, note].join('\t'));
});
if (!kept.length) console.error(`no slices for ${src} (${all.length} onsets in window)`);
