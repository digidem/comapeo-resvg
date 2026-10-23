// Snapshot tests: renders the CoMapeo default category icons at map sizes and
// compares the pixels with the PNGs in test/snapshots/. `npm run test:update`
// rewrites the snapshots; review them in the diff before committing.

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')
const { PNG } = require('pngjs')
const { render } = require('comapeo-resvg')

// 15 and 20 dp at 1x, 1.5x, 2x, 3x and 4x.
const SIZES = [15, 20, 23, 30, 40, 45, 60, 80]
const COMPRESSIONS = ['none', 'fastest', 'fast', 'balanced', 'high']

const iconsDir = path.join(__dirname, 'icons')
const snapshotsDir = path.join(__dirname, 'snapshots')
const updating = process.execArgv.includes('--test-update-snapshots')

const icons = fs
  .readdirSync(iconsDir)
  .filter((f) => f.endsWith('.svg'))
  .sort()
  .map((f) => ({ name: f.slice(0, -4), svg: fs.readFileSync(path.join(iconsDir, f), 'utf8') }))

const svg = (attrs, body = '') => `<svg xmlns="http://www.w3.org/2000/svg" ${attrs}>${body}</svg>`
const decode = (png) => PNG.sync.read(png)
const size = (png) => `${decode(png).width}x${decode(png).height}`
const samePixels = (a, b) => a.width === b.width && a.height === b.height && a.data.equals(b.data)

if (updating) {
  fs.rmSync(snapshotsDir, { recursive: true, force: true })
  fs.mkdirSync(snapshotsDir)
}

for (const { name, svg } of icons) {
  test(`${name} matches its snapshots`, async () => {
    for (const px of SIZES) {
      const file = path.join(snapshotsDir, `${name}-${px}.png`)
      if (updating) fs.writeFileSync(file, await render(svg, { width: px, height: px }))
      const snapshot = decode(fs.readFileSync(file))
      assert.equal(`${snapshot.width}x${snapshot.height}`, `${px}x${px}`)
      for (const compression of COMPRESSIONS) {
        const img = decode(await render(svg, { width: px, height: px, compression }))
        assert.ok(samePixels(img, snapshot), `${name}-${px}.png differs with ${compression} compression`)
      }
    }
  })
}

test('every snapshot belongs to an icon and size', { skip: updating }, () => {
  const expected = icons.flatMap(({ name }) => SIZES.map((px) => `${name}-${px}.png`)).sort()
  assert.deepEqual(fs.readdirSync(snapshotsDir).sort(), expected)
})

// A sample of resvg's own regression tests for filters, masks, clip paths,
// gradients and patterns, with resvg's reference PNGs, copied from the tag
// that matches the resvg version in Cargo.toml.
const resvgDir = path.join(__dirname, 'resvg')
const resvgTests = fs
  .readdirSync(resvgDir, { recursive: true })
  .filter((f) => f.endsWith('.svg'))
  .sort()
  .map((f) => f.slice(0, -4).split(path.sep).join('/'))

// resvg's own test runner allows each channel to be off by one.
const closePixels = (a, b) =>
  a.width === b.width && a.height === b.height && a.data.every((v, i) => Math.abs(v - b.data[i]) <= 1)

for (const name of resvgTests) {
  test(`resvg test ${name} matches resvg's reference`, async () => {
    const file = path.join(resvgDir, ...name.split('/'))
    // resvg renders its tests 300 px wide.
    const img = decode(await render(fs.readFileSync(`${file}.svg`), { width: 300 }))
    assert.ok(closePixels(img, decode(fs.readFileSync(`${file}.png`))))
  })
}

test('more compression gives smaller files', async () => {
  const [{ svg }] = icons
  const [none, fast, high] = await Promise.all(
    ['none', 'fast', 'high'].map((compression) => render(svg, { width: 60, compression })),
  )
  assert.ok(none.length > fast.length && fast.length > high.length)
})

test('a Buffer and a Uint8Array view render like the string', async () => {
  const [{ svg }] = icons
  const bytes = Buffer.from(svg)
  const offset = new Uint8Array(bytes.length + 3)
  offset.set(bytes, 3)
  const fromString = await render(svg, { width: 60 })
  for (const input of [bytes, offset.subarray(3)]) {
    assert.ok((await render(input, { width: 60 })).equals(fromString))
  }
})

test('the PNG fits the width and height and keeps the aspect ratio', async () => {
  const tall = svg('viewBox="0 0 10 20"', '<rect width="10" height="20"/>')
  assert.equal(size(await render(tall, { width: 30, height: 30 })), '15x30')
  assert.equal(size(await render(tall, { width: 30 })), '30x60')
  assert.equal(size(await render(tall, { height: 30 })), '15x30')
  assert.equal(size(await render(tall, { width: 100, height: 10 })), '5x10')
  const wide = svg('width="24.5" height="24"', '<rect width="24.5" height="24"/>')
  assert.equal(size(await render(wide, { width: 60, height: 60 })), '60x59')
})

test('a missing width or height is limited to 1024', async () => {
  const veryTall = svg('viewBox="0 0 10 40"', '<rect width="10" height="40"/>')
  assert.equal(size(await render(veryTall, { width: 1024 })), '256x1024')
})

test('an <image> naming a local file is not drawn', async () => {
  // An absolute path to a file that exists, so only the blocking stops it being drawn.
  const href = path.join(iconsDir, icons[0].name + '.svg')
  const fileImage = svg('width="10" height="10"', `<image href="${href}" width="10" height="10"/>`)
  const empty = await render(svg('width="10" height="10"'), { width: 10 })
  assert.ok((await render(fileImage, { width: 10 })).equals(empty))
  const rect = svg('width="10" height="10"', '<rect width="10" height="10"/>')
  assert.ok(!(await render(rect, { width: 10 })).equals(empty))
})

const square = svg('viewBox="0 0 1 1"')
for (const [input, options, what] of [
  ['<svg', { width: 60 }, 'invalid SVG'],
  [{}, { width: 60 }, 'an object instead of an SVG'],
  [square, undefined, 'no options'],
  [square, {}, 'no width or height'],
  [square, { width: 0 }, 'width 0'],
  [square, { width: -1 }, 'width -1'],
  [square, { width: 1.5 }, 'width 1.5'],
  [square, { width: NaN }, 'width NaN'],
  [square, { width: 1025 }, 'width 1025'],
  [square, { height: 1025 }, 'height 1025'],
  [square, { width: '60' }, 'width as a string'],
  [square, { width: 60, compression: 'best' }, 'an unknown compression'],
  [svg('', '<g>'.repeat(1100) + '</g>'.repeat(1100)), { width: 60 }, '1100 nested elements'],
]) {
  test(`${what} rejects with an Error`, async () => {
    await assert.rejects(render(input, options), Error)
  })
}

test('rendering runs off the JavaScript thread', async () => {
  // Takes well over 50 ms, so a 10 ms timer only fires first if the event loop is free.
  const slow = svg(
    'width="10" height="10"',
    '<filter id="f"><feTurbulence baseFrequency="0.1" numOctaves="300"/></filter><rect width="10" height="10" filter="url(#f)"/>',
  )
  let ticks = 0
  const timer = setInterval(() => ticks++, 10)
  await render(slow, { width: 128 })
  clearInterval(timer)
  assert.ok(ticks >= 5, `the event loop ran ${ticks} times during the render`)
})

test('repeated renders do not leak memory', { skip: updating }, async (t) => {
  require('node:v8').setFlagsFromString('--expose-gc')
  const gc = require('node:vm').runInNewContext('gc')
  const settle = async () => {
    gc()
    await new Promise(setImmediate)
    gc()
    return process.memoryUsage()
  }
  // Large inputs and outputs, so a leaked copy of either shows up in the totals.
  // Random padding, because macOS and iOS compress idle memory that repeats.
  const [{ svg: icon }] = icons
  const padding = require('node:crypto').randomBytes(1.5 * 1024 * 1024).toString('base64')
  const bigInvalid = '<svg' + padding
  const bigDeep = '<g>'.repeat(1100) + padding
  const batch = async () => {
    for (let i = 0; i < 50; i++) {
      // No compression, so each PNG is about 1 MB and a leaked one shows up too.
      const renders = [1, 2, 3, 4].map(() => render(icon, { width: 512, height: 512, compression: 'none' }))
      renders.push(render(bigInvalid, { width: 60 }).catch(() => {}))
      renders.push(render(Buffer.from(bigDeep), { width: 60 }).catch(() => {}))
      await Promise.all(renders)
    }
  }

  // The allocator holds on to memory as the thread pool warms up, so measure after that.
  for (let i = 0; i < 4; i++) await batch()
  const before = await settle()
  for (let i = 0; i < 4; i++) await batch()
  const after = await settle()

  // 800 renders and 400 failures: a leaked PNG, image or input would add hundreds of MB,
  // though macOS, iOS and Android compress idle memory. external only shows Buffers that
  // JavaScript still holds, so leaks in Rust need RSS.
  const mb = (bytes) => (bytes / 1024 / 1024).toFixed(1)
  const external = after.external - before.external
  const rss = after.rss - before.rss
  t.diagnostic(`RSS grew by ${mb(rss)} MB`)
  // A few of the last 1 MB PNGs may still be waiting for the garbage collector.
  assert.ok(external < 16 * 1024 * 1024, `PNG buffers grew by ${mb(external)} MB`)
  assert.ok(rss < 50 * 1024 * 1024, `RSS grew by ${mb(rss)} MB`)
})
