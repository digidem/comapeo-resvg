// Benchmarks: render time per icon, concurrent throughput, the time each call
// spends on the JavaScript thread, and how much rendering delays the event
// loop. Run with `npm run bench`.

const fs = require('node:fs')
const path = require('node:path')
const { monitorEventLoopDelay } = require('node:perf_hooks')
const { render } = require('comapeo-resvg')

const iconsDir = path.join(__dirname, 'icons')
const icons = fs
  .readdirSync(iconsDir)
  .filter((f) => f.endsWith('.svg'))
  .sort()
  .map((f) => fs.readFileSync(path.join(iconsDir, f), 'utf8'))

const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]
const ms = (x) => x.toFixed(x < 0.1 ? 4 : x < 1 ? 3 : 1)

async function timeRuns(runs, fn) {
  await fn()
  const times = []
  for (let i = 0; i < runs; i++) {
    const t0 = performance.now()
    await fn()
    times.push(performance.now() - t0)
  }
  return median(times)
}

async function main() {
  console.log(`# ${process.platform}-${process.arch} node ${process.version}`)

  console.log('\n# One icon at a time: median ms per icon')
  for (const px of [15, 60, 240, 1024]) {
    const row = [`${px} px`]
    for (const compression of ['none', 'fast', 'balanced', 'high']) {
      const runs = px >= 1024 ? 2 : 5
      const total = await timeRuns(runs, async () => {
        for (const svg of icons) await render(svg, { width: px, height: px, compression })
      })
      row.push(`${compression} ${ms(total / icons.length)}`)
    }
    console.log(row.join('  '))
  }

  console.log(`\n# All ${icons.length} icons at once: median ms for the batch`)
  for (const px of [15, 60, 240]) {
    const t = await timeRuns(10, () => Promise.all(icons.map((svg) => render(svg, { width: px, height: px }))))
    console.log(`${px} px  ${ms(t)}`)
  }

  // The SVG is copied on the JavaScript thread before rendering starts; the rest runs on the thread pool.
  console.log('\n# Time each call spends on the JavaScript thread: median ms')
  const big = icons[0].replace('</svg>', `<!--${'x'.repeat(2 * 1024 * 1024)}--></svg>`)
  for (const [label, svg] of [
    ['icon (string)', icons[0]],
    ['icon (Buffer)', Buffer.from(icons[0])],
    ['2 MB SVG (string)', big],
    ['2 MB SVG (Buffer)', Buffer.from(big)],
  ]) {
    const times = []
    for (let i = 0; i < 50; i++) {
      const t0 = performance.now()
      const promise = render(svg, { width: 60 })
      times.push(performance.now() - t0)
      await promise
    }
    console.log(`${label}  ${ms(median(times))}`)
  }

  console.log('\n# Event loop delay: ms, idle vs rendering every icon at 240 px')
  for (const busy of [false, true]) {
    const histogram = monitorEventLoopDelay({ resolution: 1 })
    histogram.enable()
    const until = performance.now() + 1000
    while (performance.now() < until) {
      if (busy) await Promise.all(icons.map((svg) => render(svg, { width: 240, height: 240 })))
      else await new Promise((resolve) => setTimeout(resolve, 50))
    }
    histogram.disable()
    const p99 = histogram.percentile(99) / 1e6
    console.log(`${busy ? 'rendering' : 'idle'}  p99 ${ms(p99)}  max ${ms(histogram.max / 1e6)}`)
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 1
})
