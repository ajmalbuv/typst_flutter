use std::collections::HashMap;

use flutter_rust_bridge::frb;
use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime, Duration};
use typst::syntax::{DiagSpan, DiagSpanKind, FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_layout::PagedDocument;
use typst_utils::Scalar;

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

/// Severity level of a [TypstDiagnostic].
///
/// Mirrors `typst::diag::Severity` but is exposed through the FRB bridge
/// as a plain enum so Dart callers get a typed value rather than a raw string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TypstSeverity {
    /// A hard error that prevents compilation from succeeding.
    Error,
    /// A warning that does not prevent compilation.
    Warning,
}

/// A source location within a Typst document.
///
/// Lines and columns are **1-based** to match editor conventions.
/// Both fields are `None` when the diagnostic originates from a synthetic
/// span (e.g. built-in library code) that has no user-visible file location.
#[derive(Debug, Clone)]
pub struct TypstSourceLocation {
    /// 1-based line number in the source file.
    pub line: u32,
    /// 1-based column number (Unicode scalar value offset) in the source file.
    pub column: u32,
}

/// A single compiler diagnostic (error or warning).
#[derive(Debug, Clone)]
pub struct TypstDiagnostic {
    /// Severity of the diagnostic.
    pub severity: TypstSeverity,
    /// Human-readable error message.
    pub message: String,
    /// Optional additional hints to help fix the error.
    pub hints: Vec<String>,
    /// Start position of the offending source range, if available.
    pub span_start: Option<TypstSourceLocation>,
    /// End position of the offending source range, if available.
    pub span_end: Option<TypstSourceLocation>,
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
    pub(crate) warnings: Vec<TypstDiagnostic>,
}

impl CompiledDocument {
    /// Returns the number of pages in the document.
    #[frb(sync)]
    pub fn page_count(&self) -> usize {
        self.inner.pages().len()
    }

    /// Returns any compiler warnings emitted during compilation.
    ///
    /// These are non-fatal diagnostics (e.g. deprecated syntax, ambiguous
    /// layout) that did not prevent compilation but may indicate issues.
    #[frb(sync)]
    pub fn warnings(&self) -> Vec<TypstDiagnostic> {
        self.warnings.clone()
    }

    /// Returns the dimensions of a page in points.
    #[frb(sync)]
    pub fn page_info(&self, index: usize) -> Result<PageInfo, String> {
        if index >= self.inner.pages().len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages()[index];
        Ok(PageInfo {
            width_pt: page.frame.width().to_pt(),
            height_pt: page.frame.height().to_pt(),
        })
    }

    /// Renders a specific page to raw RGBA pixels.
    pub fn render_page(&self, index: usize, pixel_per_pt: f32) -> Result<RenderResult, String> {
        if index >= self.inner.pages().len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages()[index];
        let canvas = typst_render::render(
            page,
            &typst_render::RenderOptions {
                pixel_per_pt: Scalar::new(pixel_per_pt as f64),
                ..Default::default()
            },
        );
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
        if index >= self.inner.pages().len() {
            return Err("Page index out of bounds".into());
        }
        let page = &self.inner.pages()[index];
        Ok(typst_svg::svg(page, &typst_svg::SvgOptions::default()))
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

        let warned = typst::compile::<PagedDocument>(&self.world);

        let warnings: Vec<TypstDiagnostic> = warned
            .warnings
            .iter()
            .map(|w| map_diagnostic(w, &self.world))
            .collect();

        let document: PagedDocument = warned
            .output
            .map_err(|errs| map_errors(&errs, &self.world))?;

        Ok(CompiledDocument {
            inner: document,
            warnings,
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
                FileId::new(RootedPath::new(
                    VirtualRoot::Project,
                    VirtualPath::new("main.typ").unwrap(),
                )),
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
        let vpath = id.vpath();
        let key = vpath.get_without_slash().replace('\\', "/");

        match self.files.get(&key) {
            Some(bytes) => {
                let text = std::str::from_utf8(bytes).map_err(|_| FileError::InvalidUtf8)?;
                Ok(Source::new(id, text.to_string()))
            }
            None => Err(FileError::NotFound(vpath.get_without_slash().into())),
        }
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        // Resolve the virtual path to a normalised forward-slash string and
        // look it up in our in-memory virtual file system.
        let vpath = id.vpath();
        let key = vpath.get_without_slash().replace('\\', "/");

        self.files
            .get(&key)
            .cloned()
            .ok_or_else(|| FileError::NotFound(vpath.get_without_slash().into()))
    }

    fn today(&self, offset: Option<Duration>) -> Option<Datetime> {
        let base_timestamp = self.sys_time.unwrap_or_else(|| {
            // Fallback to current system time if none provided
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64
        });

        // Offset is given as a Duration by Typst.
        let offset_secs = offset.map(|d| d.seconds() as i64).unwrap_or(0);
        let final_timestamp = base_timestamp + offset_secs;

        time::OffsetDateTime::from_unix_timestamp(final_timestamp)
            .ok()
            .and_then(|dt| Datetime::from_ymd(dt.year(), dt.month() as u8, dt.day()))
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Resolves a [DiagSpan] against [world] to a 1-based (line, column) pair.
///
/// Returns `None` if the span is detached (no file id) or the source cannot
/// be retrieved — this is expected for diagnostics generated from built-in
/// Typst library code.
fn resolve_span(
    diag_span: DiagSpan,
    world: &SimpleWorld,
) -> Option<(TypstSourceLocation, TypstSourceLocation)> {
    let (id, range) = match diag_span.get() {
        DiagSpanKind::Number { id, num, sub_range } => {
            (id, world.source(id).ok()?.range(num, sub_range)?)
        }
        DiagSpanKind::Range { id, range } => (id, range),
        DiagSpanKind::Detached => return None,
    };

    let source = world.source(id).ok()?;
    let lines = source.lines();

    let (start_line, start_col) = lines.byte_to_line_column(range.start)?;
    let end_byte = range.end.saturating_sub(1);
    let (end_line, end_col) = lines
        .byte_to_line_column(end_byte)
        .unwrap_or((start_line, start_col));

    Some((
        TypstSourceLocation {
            line: (start_line + 1) as u32,
            column: (start_col + 1) as u32,
        },
        TypstSourceLocation {
            line: (end_line + 1) as u32,
            column: (end_col + 1) as u32,
        },
    ))
}

/// Maps a single Typst [SourceDiagnostic] into our FRB-bridged [TypstDiagnostic].
///
/// Used for both compile errors and compile warnings.
fn map_diagnostic(e: &typst::diag::SourceDiagnostic, world: &SimpleWorld) -> TypstDiagnostic {
    let severity = match e.severity {
        typst::diag::Severity::Error => TypstSeverity::Error,
        typst::diag::Severity::Warning => TypstSeverity::Warning,
    };
    let (span_start, span_end) = resolve_span(e.span, world)
        .map(|(s, e)| (Some(s), Some(e)))
        .unwrap_or((None, None));
    TypstDiagnostic {
        severity,
        message: e.message.to_string(),
        hints: e.hints.iter().map(|h| h.v.to_string()).collect(),
        span_start,
        span_end,
    }
}

fn map_errors(errs: &[typst::diag::SourceDiagnostic], world: &SimpleWorld) -> TypstCompileError {
    TypstCompileError {
        diagnostics: errs.iter().map(|e| map_diagnostic(e, world)).collect(),
    }
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
        assert_eq!(err.diagnostics[0].severity, TypstSeverity::Error);
    }

    #[test]
    fn test_svg_export() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let svg = doc.export_svg(0).unwrap();
        assert!(svg.contains("<svg"));
    }

    #[test]
    fn test_page_info() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let info = doc.page_info(0).unwrap();
        assert!(info.width_pt > 0.0);
        assert!(info.height_pt > 0.0);

        let err = doc.page_info(1);
        assert!(err.is_err());
    }

    #[test]
    fn test_render_page() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let render = doc.render_page(0, 2.0).unwrap();
        assert!(render.width > 0);
        assert!(render.height > 0);
        assert!(!render.bytes.is_empty());

        let err = doc.render_page(1, 2.0);
        assert!(err.is_err());
    }

    #[test]
    fn test_export_svg_out_of_bounds() {
        let mut engine = TypstEngine::new();
        let doc = engine.compile("= Hello".to_string(), vec![], None).unwrap();
        let err = doc.export_svg(1);
        assert!(err.is_err());
    }

    #[test]
    fn test_add_fonts() {
        let mut engine = TypstEngine::new();
        let initial_len = engine.world.fonts.len();
        engine.add_fonts(vec![]);
        assert_eq!(engine.world.fonts.len(), initial_len);
    }

    #[test]
    fn test_vfs_source_and_file() {
        use typst::World;
        let mut world = SimpleWorld::new();
        let files = vec![
            VirtualFile {
                path: "test.png".to_string(),
                bytes: b"fake_png_data".to_vec(),
            },
            VirtualFile {
                path: "inc.typ".to_string(),
                bytes: b"Hello".to_vec(),
            },
            VirtualFile {
                path: "bad_utf8.typ".to_string(),
                bytes: vec![0xFF, 0xFE, 0xFD],
            },
        ];
        world.set_files(files);

        let inc_id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("inc.typ").unwrap(),
        ));
        let png_id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("test.png").unwrap(),
        ));
        let bad_utf8_id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("bad_utf8.typ").unwrap(),
        ));
        let missing_id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("missing.typ").unwrap(),
        ));

        // test source()
        let source_inc = world.source(inc_id).unwrap();
        assert_eq!(source_inc.text(), "Hello");

        assert!(world.source(missing_id).is_err());
        assert!(world.source(bad_utf8_id).is_err());

        // test file()
        let file_png = world.file(png_id).unwrap();
        assert_eq!(file_png.as_slice(), b"fake_png_data");

        assert!(world.file(missing_id).is_err());
    }

    #[test]
    fn test_sys_time() {
        use typst::World;
        let mut world = SimpleWorld::new();
        world.set_sys_time(Some(1609459200)); // 2021-01-01T00:00:00Z
        let today = world.today(None).unwrap();
        assert_eq!(today.year(), Some(2021));
        assert_eq!(today.month(), Some(1));
        assert_eq!(today.day(), Some(1));
    }

    #[test]
    fn test_coverage_extra() {
        use typst::World;
        let mut engine = TypstEngine::new();

        // 1. Cover add_fonts loop (lines 259-261)
        // Re-add one of the bundled fonts to ensure we hit the loop with "valid" data
        let font_data = include_bytes!("../../assets/fonts/DejaVuSansMono.ttf").to_vec();
        engine.add_fonts(vec![font_data]);

        // 2. Cover today() fallback (lines 339-342)
        let world = SimpleWorld::new();
        let today = world.today(None);
        assert!(today.is_some());

        // 3. Cover warnings and potentially detached/range spans (lines 371-372, 401)
        // #set text(font: ...) usually triggers a warning if the font is missing.
        let markup = "#set text(font: \"__NonExistent__\")\n= Test\n#assert(1 == 1)".to_string();
        let doc = engine.compile(markup, vec![], None).unwrap();

        let _warnings = doc.warnings();
        // If Typst emits a warning for missing font, it will hit line 401.

        // Try to trigger a Range span by creating an error that spans multiple characters
        let result = engine.compile("#let x = 1; #let x = 2".to_string(), vec![], None);
        if let Err(err) = result {
            // This redefinition error usually has a Range span.
            for diag in err.diagnostics {
                let _ = diag.span_start;
                let _ = diag.span_end;
            }
        }
    }
}
