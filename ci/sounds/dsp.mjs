// Small, dependency-free DSP helpers for the Squish sound pipeline (design/SOUND-2.md §5).
// WAV/CAF I/O, biquads, BS.1770-4 loudness, true peak, STFT features and onset detection.
// Pure Node (>= 18). Mono only: the pipeline decodes everything to 48 kHz mono first.

import fs from 'node:fs';

// ---------- WAV in ----------

/** Reads a PCM WAV (16/24/32-bit int or 32-bit float). Returns { rate, data: Float32Array } (mono mixdown). */
export function readWav(path) {
  const b = fs.readFileSync(path);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error(`not a WAV: ${path}`);
  let pos = 12, fmt = null, data = null;
  while (pos + 8 <= b.length) {
    const id = b.toString('ascii', pos, pos + 4);
    const size = b.readUInt32LE(pos + 4);
    const body = pos + 8;
    if (id === 'fmt ') {
      fmt = { format: b.readUInt16LE(body), channels: b.readUInt16LE(body + 2), rate: b.readUInt32LE(body + 4), bits: b.readUInt16LE(body + 14) };
      if (fmt.format === 0xfffe) fmt.format = b.readUInt16LE(body + 24);
    } else if (id === 'data') {
      data = b.subarray(body, Math.min(body + size, b.length));
    }
    pos = body + size + (size & 1);
  }
  if (!fmt || !data) throw new Error(`missing fmt/data: ${path}`);
  const bytes = fmt.bits / 8, frames = Math.floor(data.length / (bytes * fmt.channels));
  const out = new Float32Array(frames);
  for (let i = 0; i < frames; i++) {
    let s = 0;
    for (let c = 0; c < fmt.channels; c++) {
      const o = (i * fmt.channels + c) * bytes;
      let v;
      if (fmt.format === 3) v = data.readFloatLE(o);
      else if (fmt.bits === 16) v = data.readInt16LE(o) / 32768;
      else if (fmt.bits === 24) v = data.readIntLE(o, 3) / 8388608;
      else if (fmt.bits === 32) v = data.readInt32LE(o) / 2147483648;
      else throw new Error(`unsupported bits ${fmt.bits}`);
      s += v;
    }
    out[i] = s / fmt.channels;
  }
  return { rate: fmt.rate, data: out };
}

// ---------- CAF / WAV out ----------

function pcm16(data) {
  const pcm = Buffer.alloc(data.length * 2);
  // TPDF dither at 16-bit from a fixed-seed LCG, so re-running the pipeline gives byte-identical files.
  let seed = 0x5157;
  const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
  for (let i = 0; i < data.length; i++) {
    const d = (rnd() - rnd()) / 32768;
    const v = Math.max(-1, Math.min(1, data[i] + d));
    pcm.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  return pcm;
}

/** Writes a mono 16-bit little-endian linear PCM CAF (what AVAudioFile reads natively). */
export function writeCaf(path, data, rate = 48000) {
  const pcm = pcm16(data);
  const head = Buffer.alloc(8);
  head.write('caff', 0, 'ascii'); head.writeUInt16BE(1, 4); head.writeUInt16BE(0, 6);
  const desc = Buffer.alloc(12 + 32);
  desc.write('desc', 0, 'ascii'); desc.writeBigInt64BE(32n, 4);
  desc.writeDoubleBE(rate, 12);
  desc.write('lpcm', 20, 'ascii');
  desc.writeUInt32BE(2 /* kCAFLinearPCMFormatFlagIsLittleEndian */, 24);
  desc.writeUInt32BE(2, 28); // bytes per packet
  desc.writeUInt32BE(1, 32); // frames per packet
  desc.writeUInt32BE(1, 36); // channels
  desc.writeUInt32BE(16, 40); // bits
  const dataHead = Buffer.alloc(16);
  dataHead.write('data', 0, 'ascii'); dataHead.writeBigInt64BE(BigInt(pcm.length + 4), 4); dataHead.writeUInt32BE(0, 12); // edit count
  fs.writeFileSync(path, Buffer.concat([head, desc, dataHead, pcm]));
}

/** Writes a mono 16-bit WAV (for listening checks on any machine). */
export function writeWav(path, data, rate = 48000) {
  const pcm = pcm16(data);
  const h = Buffer.alloc(44);
  h.write('RIFF', 0, 'ascii'); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8, 'ascii');
  h.write('fmt ', 12, 'ascii'); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36, 'ascii'); h.writeUInt32LE(pcm.length, 40);
  fs.writeFileSync(path, Buffer.concat([h, pcm]));
}

/** Reads back a CAF written by writeCaf (round-trip check). */
export function readCaf(path) {
  const b = fs.readFileSync(path);
  if (b.toString('ascii', 0, 4) !== 'caff') throw new Error('not caf');
  let pos = 8, rate = 0, data = null;
  while (pos + 12 <= b.length) {
    const id = b.toString('ascii', pos, pos + 4);
    const size = Number(b.readBigInt64BE(pos + 4));
    const body = pos + 12;
    if (id === 'desc') rate = b.readDoubleBE(body);
    if (id === 'data') data = b.subarray(body + 4, body + size);
    pos = body + size;
  }
  const out = new Float32Array(data.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = data.readInt16LE(i * 2) / 32768;
  return { rate, data: out };
}

// ---------- Filters ----------

/** RBJ biquad. type: 'hp' | 'lp' | 'peak' | 'hshelf' | 'lshelf'. Returns coefficients. */
export function biquad(type, f, rate, q = 0.7071, gainDb = 0) {
  const w = 2 * Math.PI * f / rate, cw = Math.cos(w), sw = Math.sin(w), alpha = sw / (2 * q);
  const A = Math.pow(10, gainDb / 40);
  let b0, b1, b2, a0, a1, a2;
  switch (type) {
    case 'lp': b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = b0; a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
    case 'hp': b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = b0; a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
    case 'peak': b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A; a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A; break;
    case 'hshelf': {
      const s = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - s);
      a0 = (A + 1) - (A - 1) * cw + s; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - s; break;
    }
    case 'lshelf': {
      const s = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - s);
      a0 = (A + 1) + (A - 1) * cw + s; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - s; break;
    }
    default: throw new Error(type);
  }
  return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
}

export function filter(data, c) {
  const out = new Float32Array(data.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < data.length; i++) {
    const x = data[i];
    const y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y; out[i] = y;
  }
  return out;
}

// ---------- Loudness (ITU-R BS.1770-4) ----------

function kWeight(data, rate) {
  // Pre-filter coefficients derived for any rate (Brecht De Man's formulation of the 48 kHz constants).
  const f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196;
  const K = Math.tan(Math.PI * f0 / rate), Vh = Math.pow(10, G / 20), Vb = Math.pow(Vh, 0.4996667741545416);
  const a0 = 1 + K / Q + K * K;
  const s1 = { b0: (Vh + Vb * K / Q + K * K) / a0, b1: 2 * (K * K - Vh) / a0, b2: (Vh - Vb * K / Q + K * K) / a0, a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0 };
  const f1 = 38.13547087602444, Q1 = 0.5003270373238773, K1 = Math.tan(Math.PI * f1 / rate);
  const a01 = 1 + K1 / Q1 + K1 * K1;
  const s2 = { b0: 1, b1: -2, b2: 1, a1: 2 * (K1 * K1 - 1) / a01, a2: (1 - K1 / Q1 + K1 * K1) / a01 };
  return filter(filter(data, s1), s2);
}

/** Returns { integrated, momentaryMax, shortTermMax } in LUFS (mono, -0.691 offset). */
export function loudness(data, rate) {
  const k = kWeight(data, rate);
  const blockPower = (len, hop) => {
    const out = [];
    if (k.length < len) { // shorter than one block: one zero-padded block
      let s = 0; for (let i = 0; i < k.length; i++) s += k[i] * k[i];
      out.push(s / len); return out;
    }
    for (let start = 0; start + len <= k.length; start += hop) {
      let s = 0; for (let i = start; i < start + len; i++) s += k[i] * k[i];
      out.push(s / len);
    }
    return out;
  };
  const L = p => -0.691 + 10 * Math.log10(Math.max(p, 1e-12));
  const m = blockPower(Math.round(0.4 * rate), Math.round(0.1 * rate));
  const st = blockPower(Math.round(3 * rate), Math.round(0.1 * rate));
  const abs = m.filter(p => L(p) > -70);
  let integrated = -Infinity;
  if (abs.length) {
    const rel = L(abs.reduce((a, b) => a + b, 0) / abs.length) - 10;
    const gated = abs.filter(p => L(p) > rel);
    if (gated.length) integrated = L(gated.reduce((a, b) => a + b, 0) / gated.length);
  }
  return { integrated, momentaryMax: Math.max(...m.map(L)), shortTermMax: Math.max(...st.map(L)) };
}

/** True peak in dBTP via 4x windowed-sinc oversampling. */
export function truePeak(data) {
  const taps = 12, os = 4;
  let peak = 0;
  for (let i = 0; i < data.length; i++) peak = Math.max(peak, Math.abs(data[i]));
  for (let i = 0; i < data.length - 1; i++) {
    for (let p = 1; p < os; p++) {
      const t = p / os;
      let s = 0;
      for (let k = -taps + 1; k <= taps; k++) {
        const idx = i + k; if (idx < 0 || idx >= data.length) continue;
        const x = t - k;
        const sinc = Math.sin(Math.PI * x) / (Math.PI * x);
        const win = 0.5 + 0.5 * Math.cos(Math.PI * x / taps);
        s += data[idx] * sinc * win;
      }
      peak = Math.max(peak, Math.abs(s));
    }
  }
  return 20 * Math.log10(Math.max(peak, 1e-9));
}

export const db = x => 20 * Math.log10(Math.max(Math.abs(x), 1e-9));

// ---------- STFT features ----------

function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let j = 0; j < len / 2; j++) {
        const ar = re[i + j], ai = im[i + j];
        const br = re[i + j + len / 2] * cr - im[i + j + len / 2] * ci;
        const bi = re[i + j + len / 2] * ci + im[i + j + len / 2] * cr;
        re[i + j] = ar + br; im[i + j] = ai + bi;
        re[i + j + len / 2] = ar - br; im[i + j + len / 2] = ai - bi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}

/** Power spectra frames. Returns { frames: Float32Array[], hop, n, rate }. */
export function stft(data, rate, n = 1024, hop = 256) {
  const win = new Float32Array(n).map((_, i) => 0.5 - 0.5 * Math.cos(2 * Math.PI * i / n));
  const frames = [];
  for (let start = 0; start + n <= data.length; start += hop) {
    const re = new Float64Array(n), im = new Float64Array(n);
    for (let i = 0; i < n; i++) re[i] = data[start + i] * win[i];
    fft(re, im);
    const p = new Float32Array(n / 2);
    for (let i = 0; i < n / 2; i++) p[i] = re[i] * re[i] + im[i] * im[i];
    frames.push(p);
  }
  return { frames, hop, n, rate };
}

/** Band energy ratios over a set of frames: { centroid, hf (>6k), harsh (2.5–4.5k), low (<300) }. */
export function bands(spec, from = 0, to = spec.frames.length) {
  const { n, rate } = spec, bin = rate / n;
  let tot = 0, hf = 0, harsh = 0, low = 0, cen = 0;
  for (let f = Math.max(0, from); f < Math.min(to, spec.frames.length); f++) {
    const p = spec.frames[f];
    for (let i = 1; i < p.length; i++) {
      const hz = i * bin, v = p[i];
      tot += v; cen += v * hz;
      if (hz > 6000) hf += v;
      if (hz >= 2500 && hz <= 4500) harsh += v;
      if (hz < 300) low += v;
    }
  }
  if (tot <= 0) return { centroid: 0, hf: 0, harsh: 0, low: 0 };
  return { centroid: cen / tot, hf: hf / tot, harsh: harsh / tot, low: low / tot };
}

/** Onsets by log-spectral flux with an adaptive threshold. Returns [{ t, peakDb, decayMs }]. */
export function onsets(data, rate, { minGapMs = 35, k = 1.6, floorDb = -50 } = {}) {
  const spec = stft(data, rate, 1024, 256);
  const F = spec.frames.length;
  const flux = new Float32Array(F);
  for (let f = 1; f < F; f++) {
    let s = 0;
    const a = spec.frames[f], b = spec.frames[f - 1];
    for (let i = 2; i < a.length; i++) {
      const d = Math.log10(1e-10 + a[i]) - Math.log10(1e-10 + b[i]);
      if (d > 0) s += d;
    }
    flux[f] = s;
  }
  const hopS = spec.hop / rate, gap = Math.ceil(minGapMs / 1000 / hopS);
  const out = [];
  let last = -1e9;
  for (let f = 2; f < F - 1; f++) {
    const w0 = Math.max(0, f - 20), w1 = Math.min(F, f + 6);
    const win = Array.from(flux.subarray(w0, w1)).sort((x, y) => x - y);
    const med = win[Math.floor(win.length / 2)];
    const mad = win.map(v => Math.abs(v - med)).sort((x, y) => x - y)[Math.floor(win.length / 2)];
    if (flux[f] > med + k * (mad + 1e-3) && flux[f] >= flux[f - 1] && flux[f] >= flux[f + 1] && f - last >= gap) {
      const s0 = f * spec.hop, s1 = Math.min(data.length, s0 + spec.n + Math.round(0.05 * rate));
      let pk = 0, pkI = s0;
      for (let i = s0; i < s1; i++) if (Math.abs(data[i]) > pk) { pk = Math.abs(data[i]); pkI = i; }
      const peakDb = db(pk);
      if (peakDb < floorDb) continue;
      // Decay: time until a 10 ms RMS window falls 30 dB under the peak.
      const w = Math.round(0.01 * rate);
      let decay = 0;
      for (let i = pkI; i + w < data.length; i += w) {
        let s = 0; for (let j = i; j < i + w; j++) s += data[j] * data[j];
        if (db(Math.sqrt(s / w)) < peakDb - 30) { decay = (i - pkI) / rate * 1000; break; }
        decay = (i - pkI) / rate * 1000;
      }
      out.push({ t: s0 / rate, peakT: pkI / rate, peakDb, decayMs: decay, ...bands(spec, f, f + 6) });
      last = f;
    }
  }
  return out;
}

/** RMS envelope in dB with a given window (seconds). */
export function envelope(data, rate, winS = 0.01) {
  const w = Math.max(1, Math.round(winS * rate)), out = [];
  for (let i = 0; i + w <= data.length; i += w) {
    let s = 0; for (let j = i; j < i + w; j++) s += data[j] * data[j];
    out.push(db(Math.sqrt(s / w)));
  }
  return out;
}
