use std::collections::HashMap;

use flutter_rust_bridge::frb;
use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime};
use typst::layout::PagedDocument;
use typst::syntax::{FileId, Source};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt};

// ── Public types exposed through the FRB bridge ─────────────────────────────

/// A virtual file to be made available to the Typst compiler.
///
/// The [path] must match exactly the path used in Typst markup.
/// For example, if the markup contains `#image("logo.png")`, the path
/// must be `"logo.png"`.
pub struct VirtualFile {
    /// The virtual path as referenced in Typst markup.
    pub path: String,
    /// The raw file bytes.
    pub bytes: Vec<u8>,
}

/// Result of a successful PDF compilation.
pub struct TypstResult {
    /// Raw PDF bytes.
    pub bytes: Vec<u8>,
    /// Total number of pages in the compiled document.
    pub page_count: u32,
}

/// Result of rendering a single page.
pub struct RenderResult {
    /// Raw RGBA pixel data (4 bytes per pixel, row-major).
    pub bytes: Vec<u8>,
    /// Width of the rendered image in pixels.
    pub width: u32,
    /// Height of the rendered image in pixels.
    pub height: u32,
}

// ── TypstEngine — Stateful Compiler ─────────────────────────────────────────

#[frb(opaque)]
pub struct TypstEngine {
    world: SimpleWorld,
}

impl TypstEngine {
    /// Creates a new Typst engine with bundled default fonts.
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            world: SimpleWorld::new(),
        }
    }

    /// Adds additional fonts to the engine.
    pub fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        self.world.add_fonts(font_data);
    }

    /// Compile Typst markup to PDF bytes.
    ///
    /// - [markup]  — Typst source text.
    /// - [fonts]   — Raw bytes of font files to make available to the compiler.
    /// - [files]   — Virtual files (images, data files, includes) the markup may
    ///               reference. Keys must match the paths used in markup exactly.
    pub fn compile_pdf(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
    ) -> Result<TypstResult, String> {
        self.world.set_markup(markup);
        self.world.add_files(files);

        let document: PagedDocument = typst::compile(&self.world)
            .output
            .map_err(|errs| format_errors(&errs))?;
        let pdf = typst_pdf::pdf(&document, &typst_pdf::PdfOptions::default())
            .map_err(|e| format!("{e:?}"))?;

        Ok(TypstResult {
            bytes: pdf,
            page_count: document.pages.len() as u32,
        })
    }

    /// Render a single page of a Typst document to raw RGBA pixels.
    ///
    /// - [markup]       — Typst source text.
    /// - [fonts]        — Raw bytes of font files.
    /// - [files]        — Virtual files the markup may reference.
    /// - [page_index]   — Zero-based page index.
    /// - [pixel_per_pt] — Pixels per typographic point (1pt = 1/72 inch).
    ///                    Use 2.0 for a crisp rendering on 2× displays.
    ///
    /// Returns raw RGBA bytes (4 bytes per pixel), plus width and height.
    /// Use [ui.ImageDescriptor.raw] on the Dart side to decode these into
    /// a [ui.Image].
    pub fn render_page(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        page_index: usize,
        pixel_per_pt: f32,
    ) -> Result<RenderResult, String> {
        self.world.set_markup(markup);
        self.world.add_files(files);

        let document: PagedDocument = typst::compile(&self.world)
            .output
            .map_err(|errs| format_errors(&errs))?;

        if page_index >= document.pages.len() {
            return Err(format!(
                "Page index {page_index} out of bounds (document has {} page(s))",
                document.pages.len()
            ));
        }

        let page = &document.pages[page_index];
        let canvas = typst_render::render(page, pixel_per_pt);

        Ok(RenderResult {
            bytes: canvas.data().to_vec(),
            width: canvas.width(),
            height: canvas.height(),
        })
    }
}

// ── SimpleWorld — in-memory Typst World implementation ───────────────────────

struct SimpleWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
    source: Source,
    /// Virtual file system: normalised path string → file bytes.
    files: HashMap<String, Bytes>,
}

impl SimpleWorld {
    fn new() -> Self {
        let mut fonts = Vec::new();

        // Bundled core fonts
        let bundled = [
            include_bytes!("../../assets/fonts/LibertinusSerif-Regular.otf").as_slice(),
            include_bytes!("../../assets/fonts/NewCMMath-Book.otf").as_slice(),
            include_bytes!("../../assets/fonts/DejaVuSansMono.ttf").as_slice(),
        ];

        for data in bundled {
            fonts.extend(Font::iter(Bytes::new(data.to_vec())));
        }

        Self {
            library: LazyHash::new(Library::builder().build()),
            book: LazyHash::new(FontBook::from_fonts(&fonts)),
            fonts,
            source: Source::new(
                FileId::new(None, typst::syntax::VirtualPath::new("main.typ")),
                "".into(),
            ),
            files: HashMap::new(),
        }
    }

    fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        for data in font_data {
            let bytes = Bytes::new(data);
            self.fonts.extend(Font::iter(bytes));
        }
        self.book = LazyHash::new(FontBook::from_fonts(&self.fonts));
    }

    fn set_markup(&mut self, markup: String) {
        self.source = Source::new(self.source.id(), markup);
    }

    fn add_files(&mut self, virtual_files: Vec<VirtualFile>) {
        for vf in virtual_files {
            let normalised = vf.path.replace('\\', "/");
            self.files.insert(normalised, Bytes::new(vf.bytes));
        }
    }
}

impl typst::World for SimpleWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.source.id()
    }

    fn source(&self, _id: FileId) -> Result<Source, FileError> {
        Ok(self.source.clone())
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        // Resolve the virtual path to a normalised forward-slash string and
        // look it up in our in-memory virtual file system.
        let vpath = id.vpath().as_rootless_path();
        let key = vpath.to_string_lossy().replace('\\', "/");

        self.files
            .get(&key)
            .cloned()
            .ok_or_else(|| FileError::NotFound(vpath.into()))
    }

    fn today(&self, _offset: Option<i64>) -> Option<Datetime> {
        // Return None for fully deterministic output.
        None
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn format_errors(errs: &[typst::diag::SourceDiagnostic]) -> String {
    errs.iter()
        .map(|e| format!("[{:?}] {}", e.severity, e.message))
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn get_typst_version() -> String {
    typst::syntax::package::PackageVersion {
        major: 0,
        minor: 14,
        patch: 2,
    }
    .to_string()
}
