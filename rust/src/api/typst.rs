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

#[derive(Debug, Clone)]
pub struct TypstDiagnostic {
    pub severity: String,
    pub message: String,
    pub hints: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct TypstCompileError {
    pub diagnostics: Vec<TypstDiagnostic>,
}

// ── TypstEngine — Stateful Compiler ─────────────────────────────────────────

#[frb(opaque)]
pub struct TypstEngine {
    world: SimpleWorld,
    document: Option<PagedDocument>,
}

impl TypstEngine {
    /// Creates a new Typst engine with bundled default fonts.
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            world: SimpleWorld::new(),
            document: None,
        }
    }

    /// Adds additional fonts to the engine.
    pub fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        self.world.add_fonts(font_data);
    }

    /// Compile a document and keep it in memory for fast rendering.
    ///
    /// Returns the total page count.
    pub fn compile_document(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        sys_time: Option<i64>,
    ) -> Result<u32, TypstCompileError> {
        self.world.set_markup(markup);
        self.world.set_files(files);
        self.world.set_sys_time(sys_time);

        let document: PagedDocument = typst::compile(&self.world)
            .output
            .map_err(|errs| map_errors(&errs))?;

        let count = document.pages.len() as u32;
        self.document = Some(document);
        Ok(count)
    }

    /// Renders a single page of the currently compiled document.
    pub fn render_cached_page(
        &self,
        page_index: usize,
        pixel_per_pt: f32,
    ) -> Result<RenderResult, String> {
        let doc = self.document.as_ref().ok_or("Document not compiled")?;
        if page_index >= doc.pages.len() {
            return Err(format!("Page index out of bounds"));
        }
        let page = &doc.pages[page_index];
        let canvas = typst_render::render(page, pixel_per_pt);
        Ok(RenderResult {
            bytes: canvas.data().to_vec(),
            width: canvas.width(),
            height: canvas.height(),
        })
    }

    /// Renders a single page of the currently compiled document as an SVG string.
    pub fn render_cached_page_as_svg(&self, page_index: usize) -> Result<String, String> {
        let doc = self.document.as_ref().ok_or("Document not compiled")?;
        if page_index >= doc.pages.len() {
            return Err(format!("Page index out of bounds"));
        }
        let page = &doc.pages[page_index];
        Ok(typst_svg::svg(page))
    }

    /// Compile Typst markup to PDF bytes.
    pub fn compile_pdf(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        sys_time: Option<i64>,
    ) -> Result<TypstResult, TypstCompileError> {
        self.compile_document(markup, files, sys_time)?;
        let document = self.document.as_ref().unwrap();

        let pdf = typst_pdf::pdf(document, &typst_pdf::PdfOptions::default()).map_err(|e| {
            TypstCompileError {
                diagnostics: vec![TypstDiagnostic {
                    severity: "error".to_string(),
                    message: format!("{e:?}"),
                    hints: vec![],
                }],
            }
        })?;

        Ok(TypstResult {
            bytes: pdf,
            page_count: document.pages.len() as u32,
        })
    }

    /// Render a single page of a Typst document to raw RGBA pixels.
    pub fn render_page(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        page_index: usize,
        pixel_per_pt: f32,
        sys_time: Option<i64>,
    ) -> Result<RenderResult, TypstCompileError> {
        self.compile_document(markup, files, sys_time)?;
        self.render_cached_page(page_index, pixel_per_pt)
            .map_err(|e| TypstCompileError {
                diagnostics: vec![TypstDiagnostic {
                    severity: "error".to_string(),
                    message: e,
                    hints: vec![],
                }],
            })
    }

    /// Compiles Typst markup to a list of SVG strings (one per page).
    pub fn compile_svg(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        sys_time: Option<i64>,
    ) -> Result<Vec<String>, TypstCompileError> {
        self.compile_document(markup, files, sys_time)?;
        let document = self.document.as_ref().unwrap();

        let mut svgs = Vec::new();
        for page in &document.pages {
            svgs.push(typst_svg::svg(page));
        }

        Ok(svgs)
    }

    /// Renders a single page of a Typst document to PNG bytes.
    pub fn render_page_as_png(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        page_index: usize,
        pixel_per_pt: f32,
        sys_time: Option<i64>,
    ) -> Result<Vec<u8>, TypstCompileError> {
        self.compile_document(markup, files, sys_time)?;
        let document = self.document.as_ref().unwrap();

        if page_index >= document.pages.len() {
            return Err(TypstCompileError {
                diagnostics: vec![TypstDiagnostic {
                    severity: "error".to_string(),
                    message: format!("Page index out of bounds"),
                    hints: vec![],
                }],
            });
        }

        let page = &document.pages[page_index];
        let canvas = typst_render::render(page, pixel_per_pt);

        canvas.encode_png().map_err(|e| TypstCompileError {
            diagnostics: vec![TypstDiagnostic {
                severity: "error".to_string(),
                message: format!("PNG encoding failed: {e}"),
                hints: vec![],
            }],
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
    sys_time: Option<i64>,
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
            sys_time: None,
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

    /// Replaces the entire virtual file system for the next compilation.
    ///
    /// The VFS is reset on every call so that stale files from a previous
    /// compilation do not bleed into the next one. Callers pass the complete
    /// desired file set each time (an empty `virtual_files` means no files).
    fn set_files(&mut self, virtual_files: Vec<VirtualFile>) {
        self.files.clear();
        for vf in virtual_files {
            let normalised = vf.path.replace('\\', "/");
            self.files.insert(normalised, Bytes::new(vf.bytes));
        }
    }

    fn set_sys_time(&mut self, sys_time: Option<i64>) {
        self.sys_time = sys_time;
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

    fn source(&self, id: FileId) -> Result<Source, FileError> {
        // Fast path: the main file.
        if id == self.source.id() {
            return Ok(self.source.clone());
        }

        // Included `.typ` files: look them up in the virtual file system,
        // parse the bytes as UTF-8, and return a fresh Source.
        let vpath = id.vpath().as_rootless_path();
        let key = vpath.to_string_lossy().replace('\\', "/");

        match self.files.get(&key) {
            Some(bytes) => {
                let text = std::str::from_utf8(bytes).map_err(|_| FileError::InvalidUtf8)?;
                Ok(Source::new(id, text.to_string()))
            }
            None => Err(FileError::NotFound(vpath.into())),
        }
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

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        self.sys_time.and_then(|timestamp| {
            // Offset is given in hours by Typst.
            let offset_secs = offset.unwrap_or(0) * 3600;
            let final_timestamp = timestamp + offset_secs;
            time::OffsetDateTime::from_unix_timestamp(final_timestamp)
                .ok()
                .and_then(|dt| Datetime::from_ymd(dt.year(), dt.month() as u8, dt.day()))
        })
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn map_errors(errs: &[typst::diag::SourceDiagnostic]) -> TypstCompileError {
    let diagnostics = errs
        .iter()
        .map(|e| TypstDiagnostic {
            severity: format!("{:?}", e.severity).to_lowercase(),
            message: e.message.to_string(),
            hints: e.hints.iter().map(|h| h.to_string()).collect(),
        })
        .collect();
    TypstCompileError { diagnostics }
}

pub fn get_typst_version() -> String {
    typst::syntax::package::PackageVersion {
        major: 0,
        minor: 14,
        patch: 2,
    }
    .to_string()
}
