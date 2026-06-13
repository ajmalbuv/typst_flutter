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
#[derive(Debug, Clone)]
pub struct VirtualFile {
    /// The virtual path as referenced in Typst markup.
    pub path: String,
    /// The raw file bytes.
    pub bytes: Vec<u8>,
}

/// Result of rendering a single page.
#[derive(Debug, Clone)]
pub struct RenderResult {
    /// Raw RGBA pixel data (4 bytes per pixel, row-major).
    pub bytes: Vec<u8>,
    /// Width of the rendered image in pixels.
    pub width: u32,
    /// Height of the rendered image in pixels.
    pub height: u32,
}

#[derive(Debug, Clone)]
pub struct PageInfo {
    pub width_pt: f64,
    pub height_pt: f64,
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

// ── CompiledDocument — The Opaque Handle ────────────────────────────────────

#[derive(Debug)]
#[frb(opaque)]
pub struct CompiledDocument {
    pub(crate) inner: PagedDocument,
}

impl CompiledDocument {
    /// Returns the number of pages in the document.
    #[frb(sync)]
    pub fn page_count(&self) -> usize {
        self.inner.pages.len()
    }

    /// Returns the dimensions of a page in points.
    #[frb(sync)]
    pub fn page_info(&self, index: usize) -> Result<PageInfo, String> {
        if index >= self.inner.pages.len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages[index];
        Ok(PageInfo {
            width_pt: page.frame.width().to_pt(),
            height_pt: page.frame.height().to_pt(),
        })
    }

    /// Renders a specific page to raw RGBA pixels.
    pub fn render_page(&self, index: usize, pixel_per_pt: f32) -> Result<RenderResult, String> {
        if index >= self.inner.pages.len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages[index];
        let canvas = typst_render::render(page, pixel_per_pt);
        Ok(RenderResult {
            bytes: canvas.data().to_vec(),
            width: canvas.width(),
            height: canvas.height(),
        })
    }

    /// Exports the document to a PDF byte array.
    pub fn export_pdf(&self) -> Result<Vec<u8>, String> {
        typst_pdf::pdf(&self.inner, &typst_pdf::PdfOptions::default()).map_err(|e| format!("{e:?}"))
    }

    /// Exports a specific page to an SVG string.
    pub fn export_svg(&self, index: usize) -> Result<String, String> {
        if index >= self.inner.pages.len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages[index];
        Ok(typst_svg::svg(page))
    }
}

// ── TypstEngine — Stateless Compiler ────────────────────────────────────────

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

    /// Compile Typst markup into a CompiledDocument handle.
    pub fn compile(
        &mut self,
        markup: String,
        files: Vec<VirtualFile>,
        sys_time: Option<i64>,
    ) -> Result<CompiledDocument, TypstCompileError> {
        self.world.set_markup(markup);
        self.world.set_files(files);
        self.world.set_sys_time(sys_time);

        let document: PagedDocument = typst::compile(&self.world)
            .output
            .map_err(|errs| map_errors(&errs))?;

        Ok(CompiledDocument { inner: document })
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
        let base_timestamp = self.sys_time.unwrap_or_else(|| {
            // Fallback to current system time if none provided
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64
        });

        // Offset is given in hours by Typst.
        let offset_secs = offset.unwrap_or(0) * 3600;
        let final_timestamp = base_timestamp + offset_secs;

        time::OffsetDateTime::from_unix_timestamp(final_timestamp)
            .ok()
            .and_then(|dt| Datetime::from_ymd(dt.year(), dt.month() as u8, dt.day()))
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

#[frb(sync)]
pub fn get_typst_version() -> String {
    env!("TYPST_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_initialization() {
        let engine = TypstEngine::new();
        // Check that bundled fonts are loaded
        assert!(engine.world.fonts.len() >= 3);
    }

    #[test]
    fn test_vfs_normalization() {
        let mut world = SimpleWorld::new();
        let files = vec![VirtualFile {
            path: "subdir\\test.typ".to_string(),
            bytes: b"= Test".to_vec(),
        }];
        world.set_files(files);
        // Backslashes should be normalized to forward slashes
        assert!(world.files.contains_key("subdir/test.typ"));
        assert_eq!(
            world.files.get("subdir/test.typ").unwrap().as_slice(),
            b"= Test"
        );
    }

    #[test]
    fn test_basic_compilation() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let pdf = doc.export_pdf().unwrap();
        assert!(!pdf.is_empty());
        assert_eq!(doc.page_count(), 1);
    }

    #[test]
    fn test_compile_error() {
        let mut engine = TypstEngine::new();
        let result = engine.compile("#invalid_call()".to_string(), vec![], None);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(!err.diagnostics.is_empty());
        assert_eq!(err.diagnostics[0].severity, "error");
    }

    #[test]
    fn test_svg_export() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let svg = doc.export_svg(0).unwrap();
        assert!(svg.contains("<svg"));
    }
}
