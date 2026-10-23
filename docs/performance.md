# Performance

## Threads and copies

`render` copies the SVG into Rust on the JavaScript thread, then parses,
draws and encodes it on the libuv thread pool. The PNG is handed back
without a copy, except in Electron, which doesn't allow Node to wrap memory
it didn't allocate, so there the PNG is copied once.

The input copy is needed because the caller could change a Buffer while it
is being rendered. It is small next to rendering: about 5 µs for a typical
icon. For a 2 MB SVG it took 0.06–0.1 ms from a Buffer and 0.5–0.7 ms from
a string, which has to be converted to UTF-8, on Macs and Linux, and up to
2 ms on a Windows CI runner.

## The thread pool and the event loop

The thread pool has four threads by default and also serves `fs`,
`dns.lookup`, `crypto` and `zlib`, so a large batch of renders can delay
those. Set `UV_THREADPOOL_SIZE`, or limit how many renders run at once, if
that matters.

On a machine with no more cores than pool threads, a large batch also
competes with the JavaScript thread for CPU time: on 3–4 core CI runners the
event loop's 99th-percentile delay rose by 3–40 ms while rendering.
Rendering every test icon at 240 px in a loop for a second on the machines
below left the 99th-percentile delay the same as when idle.

## Compression

`'balanced'` makes files 20–40% smaller than `'fast'`, more at larger sizes,
and takes about twice as long to render and encode. `'high'` takes longer
again and is rarely smaller than `'balanced'`.

## Benchmarks

Median times from `npm run bench`, all with `'fast'` compression:

| | Apple M-series Mac | iOS simulator | Android arm64 emulator |
|---|---|---|---|
| one icon at 60 px | 0.20 ms | 0.20 ms | 0.78 ms |
| one icon at 1024 px | 8.4 ms | 8.8 ms | 9.9 ms |
| all 36 icons at 60 px, at once | 1.9 ms | 2.0 ms | 2.9 ms |
| JavaScript-thread time per call, icon | 0.005 ms | 0.005 ms | 0.021 ms |

`npx nodejs-mobile-test <ios|android> nodejs-project --entry bench.js`, after
`scripts/assemble-project.sh <target>`, runs the benchmarks on a simulator or
emulator; the README has the full commands.
