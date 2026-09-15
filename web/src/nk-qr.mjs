/**
 * A QR encoder, because the pairing code has to be drawn by this site and not
 * by somebody else's server.
 *
 * Every other option was worse. A CDN would break the rule the privacy notice
 * states — that every script and every font comes from this domain — and an
 * image service would mean sending it the one string that must never leave the
 * browser: the private half of an identity key. So the code is generated here,
 * in the page, and nothing about it is fetched.
 *
 * Deliberately small: byte mode, error level M, versions 1 to 6. That is up to
 * 106 bytes, which holds the pairing URI (68) with room to spare and stops well
 * short of version 7, where a version-information block would be required.
 * Anything longer is refused rather than silently mis-drawn.
 *
 * `web/test/qr.mjs` encodes a known string and decodes the result with an
 * independent reader. Without that this file would be unverifiable by reading,
 * which for a thing that is either exactly right or useless is not good enough.
 */

// ─── Galois field, for the Reed–Solomon codewords ──────────────────────────
const EXP = new Uint8Array(512)
const LOG = new Uint8Array(256)
for (let i = 0, x = 1; i < 255; i++) {
  EXP[i] = x
  LOG[x] = i
  x <<= 1
  if (x & 0x100) x ^= 0x11d
}
for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]

const mul = (a, b) => (a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]])

/**
 * The generator polynomial for `n` error-correction codewords, highest degree
 * first — the same order the division below reads. Getting these two to
 * disagree produces codewords that look plausible and correct nothing, which is
 * exactly the failure `web/test/qr.mjs` exists to catch.
 */
function generator (n) {
  let poly = [1]
  for (let i = 0; i < n; i++) {
    const next = new Array(poly.length + 1).fill(0)
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j]                  // times x
      next[j + 1] ^= mul(poly[j], EXP[i]) // times alpha^i
    }
    poly = next
  }
  return poly
}

/** Polynomial division; the remainder is the error correction. */
function ecCodewords (data, count) {
  const gen = generator(count)
  const rest = [...data, ...new Array(count).fill(0)]
  for (let i = 0; i < data.length; i++) {
    const factor = rest[i]
    if (factor === 0) continue
    for (let j = 1; j < gen.length; j++) rest[i + j] ^= mul(gen[j], factor)
  }
  return rest.slice(data.length)
}

// ─── The versions this file speaks ─────────────────────────────────────────
// [total codewords, ec codewords per block, [blocks, data codewords] …]
const VERSIONS = {
  1: { total: 26, ec: 10, groups: [[1, 16]] },
  2: { total: 44, ec: 16, groups: [[1, 28]] },
  3: { total: 70, ec: 26, groups: [[1, 44]] },
  4: { total: 100, ec: 18, groups: [[2, 32]] },
  5: { total: 134, ec: 24, groups: [[2, 43]] },
  6: { total: 172, ec: 16, groups: [[4, 27]] },
}
const ALIGN = { 1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34] }

const capacity = (v) =>
  VERSIONS[v].groups.reduce((sum, [blocks, data]) => sum + blocks * data, 0)

// ─── Bit stream ────────────────────────────────────────────────────────────
class Bits {
  constructor () { this.bits = [] }
  push (value, length) {
    for (let i = length - 1; i >= 0; i--) this.bits.push((value >> i) & 1)
  }
  get length () { return this.bits.length }
  toBytes () {
    const out = []
    for (let i = 0; i < this.bits.length; i += 8) {
      let byte = 0
      for (let j = 0; j < 8; j++) byte = (byte << 1) | (this.bits[i + j] ?? 0)
      out.push(byte)
    }
    return out
  }
}

/** Data codewords for one version: mode, length, payload, terminator, padding. */
function codewords (bytes, version) {
  const room = capacity(version)
  const bits = new Bits()
  bits.push(0b0100, 4)          // byte mode
  bits.push(bytes.length, 8)    // versions 1–9 count the length in 8 bits
  for (const b of bytes) bits.push(b, 8)
  const total = room * 8
  bits.push(0, Math.min(4, total - bits.length))
  while (bits.length % 8 !== 0) bits.push(0, 1)
  const out = bits.toBytes()
  // 236 and 17, alternating, are what the standard pads with.
  for (let i = 0; out.length < room; i++) out.push(i % 2 === 0 ? 0xec : 0x11)
  return out
}

/** Split into blocks, add error correction, interleave. */
function interleave (data, version) {
  const { ec, groups } = VERSIONS[version]
  const blocks = []
  let at = 0
  for (const [count, size] of groups) {
    for (let i = 0; i < count; i++) {
      const block = data.slice(at, at + size)
      at += size
      blocks.push({ data: block, ec: ecCodewords(block, ec) })
    }
  }
  const out = []
  const longest = Math.max(...blocks.map((b) => b.data.length))
  for (let i = 0; i < longest; i++) {
    for (const b of blocks) if (i < b.data.length) out.push(b.data[i])
  }
  for (let i = 0; i < ec; i++) for (const b of blocks) out.push(b.ec[i])
  return out
}

// ─── The matrix ────────────────────────────────────────────────────────────
function blank (size) {
  return {
    modules: Array.from({ length: size }, () => new Array(size).fill(false)),
    reserved: Array.from({ length: size }, () => new Array(size).fill(false)),
  }
}

function placeFinder (m, size, row, col) {
  for (let r = -1; r <= 7; r++) {
    for (let c = -1; c <= 7; c++) {
      const rr = row + r
      const cc = col + c
      if (rr < 0 || rr >= size || cc < 0 || cc >= size) continue
      const on = (r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
                 (c >= 0 && c <= 6 && (r === 0 || r === 6)) ||
                 (r >= 2 && r <= 4 && c >= 2 && c <= 4)
      m.modules[rr][cc] = on
      m.reserved[rr][cc] = true
    }
  }
}

function placeAlignment (m, version) {
  const centres = ALIGN[version]
  for (const r of centres) {
    for (const c of centres) {
      if (m.reserved[r][c]) continue
      for (let dr = -2; dr <= 2; dr++) {
        for (let dc = -2; dc <= 2; dc++) {
          const on = Math.max(Math.abs(dr), Math.abs(dc)) !== 1
          m.modules[r + dr][c + dc] = on
          m.reserved[r + dr][c + dc] = true
        }
      }
    }
  }
}

const FORMAT_MASK = 0b101010000010010
/** 15 bits of BCH(15,5), then the standard's fixed mask over the result. */
function formatBits (maskPattern) {
  const data = (0b00 << 3) | maskPattern // 00 is error level M
  let rest = data << 10
  for (let i = 4; i >= 0; i--) {
    if ((rest >> (i + 10)) & 1) rest ^= 0b10100110111 << i
  }
  return ((data << 10) | rest) ^ FORMAT_MASK
}

function placeFormat (m, size, maskPattern) {
  const value = formatBits(maskPattern)
  // Bit 14 is the most significant, and that is the one the standard places
  // first. Reading the string the other way round draws a code with a perfect
  // shape that no reader accepts.
  const bit = (n) => ((value >> n) & 1) === 1

  // Around the top-left finder.
  for (let j = 0; j <= 5; j++) m.modules[8][j] = bit(14 - j)
  m.modules[8][7] = bit(8)
  m.modules[8][8] = bit(7)
  m.modules[7][8] = bit(6)
  for (let j = 0; j <= 5; j++) m.modules[j][8] = bit(j)

  // The second copy: up the left edge from the bottom, then along row 8 to the
  // right edge.
  for (let i = 0; i <= 6; i++) m.modules[size - 1 - i][8] = bit(14 - i)
  for (let i = 0; i <= 7; i++) m.modules[8][size - 8 + i] = bit(7 - i)

  m.modules[size - 8][8] = true // the module that is always dark
}

const MASKS = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (_r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
]

/** The four penalty rules, which decide which mask a reader will like best. */
function penalty (modules, size) {
  let score = 0
  const run = (get) => {
    for (let a = 0; a < size; a++) {
      let last = null
      let length = 0
      for (let b = 0; b < size; b++) {
        const v = get(a, b)
        if (v === last) length++
        else { if (length >= 5) score += 3 + (length - 5); last = v; length = 1 }
      }
      if (length >= 5) score += 3 + (length - 5)
    }
  }
  run((r, c) => modules[r][c])
  run((c, r) => modules[r][c])

  for (let r = 0; r < size - 1; r++) {
    for (let c = 0; c < size - 1; c++) {
      const v = modules[r][c]
      if (v === modules[r][c + 1] && v === modules[r + 1][c] && v === modules[r + 1][c + 1]) {
        score += 3
      }
    }
  }

  const pattern = [true, false, true, true, true, false, true, false, false, false, false]
  const matches = (get, a, b) => {
    for (let i = 0; i < pattern.length; i++) if (get(a, b + i) !== pattern[i]) return false
    return true
  }
  const reversed = [...pattern].reverse()
  const matchesR = (get, a, b) => {
    for (let i = 0; i < reversed.length; i++) if (get(a, b + i) !== reversed[i]) return false
    return true
  }
  for (let a = 0; a < size; a++) {
    for (let b = 0; b + pattern.length <= size; b++) {
      if (matches((x, y) => modules[x][y], a, b)) score += 40
      if (matchesR((x, y) => modules[x][y], a, b)) score += 40
      if (matches((x, y) => modules[y][x], a, b)) score += 40
      if (matchesR((x, y) => modules[y][x], a, b)) score += 40
    }
  }

  let dark = 0
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (modules[r][c]) dark++
  const percent = (dark * 100) / (size * size)
  score += Math.floor(Math.abs(percent - 50) / 5) * 10
  return score
}

function draw (bytes, version, maskPattern) {
  const size = version * 4 + 17
  const m = blank(size)
  placeFinder(m, size, 0, 0)
  placeFinder(m, size, 0, size - 7)
  placeFinder(m, size, size - 7, 0)
  for (let i = 8; i < size - 8; i++) {
    const on = i % 2 === 0
    m.modules[6][i] = on
    m.reserved[6][i] = true
    m.modules[i][6] = on
    m.reserved[i][6] = true
  }
  placeAlignment(m, version)
  // The format areas are reserved before the data is laid out, and written
  // afterwards — otherwise the data would walk straight through them.
  for (let i = 0; i <= 8; i++) {
    m.reserved[8][i] = true
    m.reserved[i][8] = true
    if (i < 8) {
      m.reserved[8][size - 1 - i] = true
      m.reserved[size - 1 - i][8] = true
    }
  }

  const bits = []
  for (const byte of bytes) for (let i = 7; i >= 0; i--) bits.push(((byte >> i) & 1) === 1)

  let at = 0
  let upward = true
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col-- // the vertical timing line is not a data column
    for (let i = 0; i < size; i++) {
      const row = upward ? size - 1 - i : i
      for (const c of [col, col - 1]) {
        if (m.reserved[row][c]) continue
        let bit = at < bits.length ? bits[at++] : false
        if (MASKS[maskPattern](row, c)) bit = !bit
        m.modules[row][c] = bit
      }
    }
    upward = !upward
  }

  placeFormat(m, size, maskPattern)
  return { size, modules: m.modules }
}

/** The smallest version that holds this many bytes, or nothing. */
function versionFor (length) {
  for (const v of [1, 2, 3, 4, 5, 6]) {
    // 4 bits of mode + 8 of length, rounded up to whole codewords.
    if (length + 2 <= capacity(v)) return v
  }
  return null
}

/**
 * The modules for `text`, as an array of rows of booleans. Dark is `true`.
 * The quiet zone is not included — whoever draws it adds it, and every caller
 * here does.
 */
export function qrMatrix (text) {
  const bytes = [...new TextEncoder().encode(text)]
  const version = versionFor(bytes.length)
  if (!version) {
    // 106, not 108: the mode and the length take twelve bits of the first two
    // codewords before any of the text does.
    throw new Error(`${bytes.length} bytes is more than this encoder draws (106 at most)`)
  }
  const data = interleave(codewords(bytes, version), version)
  let best = null
  for (let mask = 0; mask < 8; mask++) {
    const candidate = draw(data, version, mask)
    const score = penalty(candidate.modules, candidate.size)
    if (!best || score < best.score) best = { ...candidate, score }
  }
  return best
}

/**
 * An SVG of `text`, drawn as one path so it stays sharp at any size and costs
 * one element. Four modules of quiet zone, because readers need it and a code
 * pasted onto a coloured card without it is a code that does not scan.
 */
export function qrSvg (text, { size = 240, label = 'QR code' } = {}) {
  const { modules, size: n } = qrMatrix(text)
  const quiet = 4
  const span = n + quiet * 2
  let path = ''
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (modules[r][c]) path += `M${c + quiet} ${r + quiet}h1v1h-1z`
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${span} ${span}" ` +
    `width="${size}" height="${size}" role="img" aria-label="${label}" ` +
    `style="background:#fff;border-radius:10px">` +
    `<path d="${path}" fill="#000"/></svg>`
}
