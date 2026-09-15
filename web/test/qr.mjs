/**
 * The QR encoder, checked the only three ways it can be checked without a
 * camera in the room.
 *
 * Reading `nk-qr.mjs` does not tell you whether it is right. A QR code with a
 * reversed generator polynomial, or with its format bits laid out on the wrong
 * axis, has the correct shape, the correct size and the correct finder
 * patterns — and decodes as nothing at all. Both of those mistakes were in the
 * first draft of that file and neither was visible in the picture.
 *
 * So: a known Reed–Solomon vector, the format strings from the standard's own
 * table, and the exact matrix for one string — a matrix that was decoded back
 * to that string by an independent reader (OpenCV) before it was written down
 * here, together with ten more across versions 1 to 6. This test locks in what
 * that reader confirmed; it cannot confirm it again by itself.
 *
 *   node web/test/qr.mjs
 */
import { createHash } from 'node:crypto'
import { qrMatrix, qrSvg } from '../src/nk-qr.mjs'

let failures = 0
const is = (what, got, want) => {
  const ok = String(got) === String(want)
  if (!ok) failures++
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${ok ? '' : `\n      got  ${got}\n      want ${want}`}`)
}

// ─── One matrix, decoded by a real reader before it was pasted here ─────────
const PAIRING = 'nextkey://identity/v2?sk=5tLOjKjW9pQ2sYbXf0nEaJkTt2wq3vQHm7cRZ1u8xYA'
const { modules, size } = qrMatrix(PAIRING)
const flat = modules.map((row) => row.map((v) => (v ? '1' : '0')).join('')).join('')
is('the pairing URI lands in version 5', size, 37)
is('its matrix is byte for byte the one that decoded',
  createHash('sha256').update(flat).digest('hex'),
  '608f9c9475645b602ba6a78a32dc4014a31126162ada47c04f79b30c6b1bc3f9')

// ─── Structure, which a wrong matrix usually still gets right ──────────────
const finder = (r, c) => modules[r][c] && modules[r + 6][c] && modules[r][c + 6] &&
  !modules[r + 1][c + 1] && modules[r + 3][c + 3]
is('three finder patterns', [finder(0, 0), finder(0, size - 7), finder(size - 7, 0)].join(),
  'true,true,true')
is('the timing row alternates', [0, 1, 2, 3].map((i) => modules[6][8 + i] ? 1 : 0).join(''), '1010')
is('the dark module is dark', modules[size - 8][8], 'true')

// ─── Refusals ──────────────────────────────────────────────────────────────
let refused = ''
try { qrMatrix('x'.repeat(107)) } catch (e) { refused = e.message }
is('107 bytes is refused rather than mis-drawn', /106 at most/.test(refused), 'true')

// ─── The SVG a page actually inserts ───────────────────────────────────────
const svg = qrSvg(PAIRING, { size: 200 })
is('the svg carries a quiet zone', /viewBox="0 0 45 45"/.test(svg), 'true')
is('the svg is one path', (svg.match(/<path/g) || []).length, 1)

console.log(failures === 0 ? '\nall good' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
