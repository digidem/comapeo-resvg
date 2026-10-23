# @comapeo/resvg

Minimal Node.js bindings for [resvg](https://github.com/linebender/resvg):
one function that renders an SVG to a PNG. resvg's text and image support is
left out, which keeps the addon small and away from the filesystem. Prebuilt
for Node and Electron on desktop and for
[nodejs-mobile](https://github.com/digidem/nodejs-mobile) on iOS and Android.
Maintained by Awana Digital for CoMapeo.

## Usage

```js
import { render } from "@comapeo/resvg";

const png = await render(svg, { width: 60, height: 60 }); // Buffer holding a PNG
```

`svg` is a string, Buffer or other Uint8Array. Options:

- `width`, `height`: whole numbers from 1 to 1024. The PNG fits this box and
  keeps the SVG's aspect ratio, so a 1:2 SVG in a 60 × 60 box is 30 × 60.
  Give at least one; a missing one is limited to 1024, so `{ width: 60 }`
  renders a 1:2 SVG at 60 × 120.
- `compression`: `'none'`, `'fastest'`, `'fast'` (the default), `'balanced'`
  or `'high'`. `'balanced'` makes files noticeably smaller than `'fast'` and
  takes about twice as long; `'high'` is slower again and rarely smaller.

Types are in `index.d.ts`.

`render` rejects on an invalid SVG, invalid options, an argument of the wrong
type, elements nested more than 1024 deep, or a panic inside resvg.

Performance details are in [docs/performance.md](docs/performance.md).

## Limitations

resvg's optional features are turned off, so:

- `<text>` is not drawn, and there is no font stack.
- Embedded images, raster or SVG, are not drawn.
- An `<image>` naming a local file is not read.
- `.svgz` is not accepted.

Filters, masks, clip paths, gradients and patterns are drawn.

## Untrusted input

The size and depth limits stop mistakes and oversized files, but resvg is not
hardened against hostile input. Known ways an SVG can still crash or stall the
process:

- Thousands of chained `clip-path` or `mask` references overflow the stack.
- Extreme filter parameters, such as `feTurbulence numOctaves="10000"`, can
  occupy a thread-pool thread for minutes.
- Deeply nested groups with opacity, masks or filters can use hundreds of MB.

If the SVG may come from someone you don't trust, render it in a child process
that you can kill on a timeout. A worker thread is not enough: a stack overflow
in the addon takes down the whole process.

## Prebuilds

The package ships these in `prebuilds/`, loaded with
[node-gyp-build](https://github.com/prebuild/node-gyp-build). Nothing is
compiled on install.

| prebuild                                      | for                                                                            |
| --------------------------------------------- | ------------------------------------------------------------------------------ |
| `darwin-arm64`, `darwin-x64`                  | macOS                                                                          |
| `linux-x64`                                   | Linux with glibc 2.34 or later                                                 |
| `win32-x64`                                   | Windows                                                                        |
| `android-arm64`, `android-arm`, `android-x64` | nodejs-mobile on Android                                                       |
| `ios-arm64`                                   | nodejs-mobile on iOS devices                                                   |
| `ios-arm64-simulator`                         | nodejs-mobile on the iOS simulator, for apps that package the addon themselves |

The nodejs-mobile builds link against the nodejs-mobile runtime and don't
load in other Node builds.

CI builds every prebuild and runs the tests in Node and Electron on macOS,
Linux and Windows, and with nodejs-mobile on the iOS simulator and on x86_64
Android emulators. The arm64 Android build has been run on an emulator by
hand; the iOS device and 32-bit ARM builds have not been run.

## Building and testing

Needs rustup (`rust-toolchain.toml` picks the toolchain and targets) and
Node.

```sh
npm install
scripts/build.sh host
npm test
npm run bench
```

Running on an iOS simulator or Android emulator uses
[nodejs-mobile-test-harness](https://github.com/digidem/nodejs-mobile-test-harness),
installed by `npm install`. iOS needs Xcode. Android needs `cargo-ndk`
(`cargo install cargo-ndk`), the SDK with NDK 27.2, an emulator image or a
device, and Java 17; the harness's README lists what its test app needs.

```sh
scripts/fetch-runtime.sh                          # nodejs-mobile runtimes -> vendor-runtime/
scripts/build.sh ios-arm64-simulator              # or android-arm64, android-x64, ...
scripts/assemble-project.sh ios-arm64-simulator   # or android-arm64, ...
npx nodejs-mobile-test ios nodejs-project --runtime-dir vendor-runtime/ios
npx nodejs-mobile-test android nodejs-project --runtime-dir vendor-runtime/android
```

Add `--entry bench.js` to run the benchmarks instead of the tests. On
Android, `--avd <name>` boots an emulator when no device is attached.

The tests render the icons in `test/icons/` and compare them with
`test/snapshots/`, and render a sample of resvg's own tests for filters,
masks, clip paths, gradients and patterns and compare them with resvg's
reference PNGs in `test/resvg/`. They also check the behavior above, that
rendering doesn't block the event loop, and that it doesn't leak memory.
`npm run test:update` rewrites the icon snapshots; review the changed PNGs
before committing.

## License

MIT: see `LICENSE`. The prebuilds include code from resvg and other Rust
crates, whose licenses are in `THIRD-PARTY-NOTICES.txt`. The test icons are from
[comapeo-default-categories](https://github.com/digidem/comapeo-default-categories)
(CC BY-NC 4.0). The tests in `test/resvg/` are from
[resvg](https://github.com/linebender/resvg/tree/v0.48.1/crates/resvg/tests)
(MIT or Apache 2.0).
