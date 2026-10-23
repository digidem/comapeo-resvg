use napi::bindgen_prelude::{AsyncTask, Buffer, Either};
use napi::{Env, Error, Result, Task};
use napi_derive::napi;
use resvg::{tiny_skia, usvg};

const MAX_SIZE: u32 = 1024;
// usvg rejects nesting past 1024 anyway, but only after roxmltree has recursed through all of it.
const MAX_DEPTH: i32 = 1024;

fn err(e: impl ToString) -> Error {
    Error::from_reason(e.to_string())
}

fn too_deep(svg: &[u8]) -> bool {
    let mut depth = 0;
    for pair in svg.windows(2) {
        match pair {
            [b'<', b'/'] | [b'/', b'>'] => depth -= 1,
            [b'<', c] if c.is_ascii_alphabetic() => depth += 1,
            _ => {}
        }
        if depth > MAX_DEPTH {
            return true;
        }
    }
    false
}

fn render_png(svg: &[u8], width: u32, height: u32, compression: Compression) -> Result<Vec<u8>> {
    if too_deep(svg) {
        return Err(err(format!(
            "elements are nested more than {MAX_DEPTH} deep"
        )));
    }
    let mut options = usvg::Options::default();
    // The SVG may come from someone else, so never read local files it names.
    options.image_href_resolver.resolve_string = Box::new(|_, _| None);
    // Each embedded SVG gets its own element limit, so repeating one with <use> bypasses it.
    options.image_href_resolver.resolve_data = Box::new(|_, _, _| None);
    let tree = usvg::Tree::from_data(svg, &options).map_err(err)?;

    let box_size = tiny_skia::Size::from_wh(width as f32, height as f32).unwrap();
    let fitted = tree.size().scale_to(box_size).to_int_size();
    let mut pixmap = tiny_skia::Pixmap::new(fitted.width(), fitted.height())
        .ok_or_else(|| err("could not allocate the image"))?;
    let transform = tiny_skia::Transform::from_scale(
        fitted.width() as f32 / tree.size().width(),
        fitted.height() as f32 / tree.size().height(),
    );
    resvg::render(&tree, transform, &mut pixmap.as_mut());
    encode_png(&pixmap, compression)
}

fn encode_png(pixmap: &tiny_skia::Pixmap, compression: Compression) -> Result<Vec<u8>> {
    let rgba: Vec<u8> = pixmap
        .pixels()
        .iter()
        .flat_map(|p| {
            let c = p.demultiply();
            [c.red(), c.green(), c.blue(), c.alpha()]
        })
        .collect();
    let mut png = Vec::new();
    let mut encoder = png::Encoder::new(&mut png, pixmap.width(), pixmap.height());
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(match compression {
        Compression::None => png::Compression::NoCompression,
        Compression::Fastest => png::Compression::Fastest,
        Compression::Fast => png::Compression::Fast,
        Compression::Balanced => png::Compression::Balanced,
        Compression::High => png::Compression::High,
    });
    encoder
        .write_header()
        .and_then(|mut writer| writer.write_image_data(&rgba))
        .map_err(err)?;
    Ok(png)
}

#[napi(string_enum = "lowercase")]
#[derive(Clone, Copy)]
pub enum Compression {
    None,
    Fastest,
    Fast,
    Balanced,
    High,
}

#[napi(object)]
pub struct RenderOptions {
    pub width: Option<f64>,
    pub height: Option<f64>,
    pub compression: Option<Compression>,
}

pub struct Render {
    svg: Vec<u8>,
    width: u32,
    height: u32,
    compression: Compression,
}

impl Task for Render {
    type Output = Vec<u8>;
    type JsValue = Buffer;

    fn compute(&mut self) -> Result<Vec<u8>> {
        let svg = &self.svg;
        let (width, height, compression) = (self.width, self.height, self.compression);
        std::panic::catch_unwind(|| render_png(svg, width, height, compression))
            .unwrap_or_else(|_| Err(err("resvg panicked while rendering")))
    }

    fn resolve(&mut self, _: Env, png: Vec<u8>) -> Result<Buffer> {
        Ok(png.into())
    }
}

fn pixels(name: &str, value: Option<f64>) -> Result<u32> {
    match value {
        None => Ok(MAX_SIZE),
        Some(v) if v >= 1.0 && v <= MAX_SIZE as f64 && v.fract() == 0.0 => Ok(v as u32),
        Some(v) => Err(err(format!(
            "{name} must be a whole number from 1 to {MAX_SIZE}, got {v}"
        ))),
    }
}

#[napi]
pub fn render(svg: Either<String, Buffer>, options: RenderOptions) -> Result<AsyncTask<Render>> {
    if options.width.is_none() && options.height.is_none() {
        return Err(err("width or height is required"));
    }
    let width = pixels("width", options.width)?;
    let height = pixels("height", options.height)?;
    let svg = match svg {
        Either::A(s) => s.into_bytes(),
        Either::B(b) => b.to_vec(),
    };
    Ok(AsyncTask::new(Render {
        svg,
        width,
        height,
        compression: options.compression.unwrap_or(Compression::Fast),
    }))
}
