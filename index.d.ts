export interface RenderOptions {
  /** Whole number of pixels, 1 to 1024. A missing width or height is limited to 1024. */
  width?: number
  height?: number
  /** How hard to compress the PNG. Defaults to 'fast'. */
  compression?: 'none' | 'fastest' | 'fast' | 'balanced' | 'high'
}

/**
 * Renders an SVG to a PNG that fits `width` x `height`, keeping its aspect
 * ratio, on the libuv thread pool. Give at least one of `width` and `height`.
 */
export function render(svg: string | Uint8Array, options: RenderOptions): Promise<Buffer>
