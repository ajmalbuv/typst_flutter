use std::collections::HashMap;
use std::io::Read;
use std::sync::RwLock;

use flutter_rust_bridge::frb;
use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime, Dict, Duration, IntoValue};
use typst::syntax::{
    DiagSpan, DiagSpanKind, FileId, RootedPath, Source, VirtualPath, VirtualRoot,
    package::PackageSpec,
};
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
        inputs: Option<HashMap<String, String>>,
        allow_packages: bool,
    ) -> Result<CompiledDocument, TypstCompileError> {
        self.world.set_markup(markup);
        self.world.set_files(files);
        self.world.set_sys_time(sys_time);
        self.world.set_inputs(inputs);
        self.world.set_allow_packages(allow_packages);

        // Pre-resolve any packages referenced in the source / files.
        if allow_packages {
            self.world.pre_resolve_packages()?;
        }

        let warned = typst::compile::<PagedDocument>(&self.world);

        // Evict cache entries that haven't been used in the last 10 compilations
        // to prevent unbounded memory growth during live editing.
        comemo::evict(10);

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

    pub fn query(
        &mut self,
        document: &CompiledDocument,
        selector: String,
    ) -> Result<String, String> {
        use comemo::Track;
        use typst::World;
        use typst::engine::Sink;
        use typst::foundations::{Context, IntoValue, LocatableSelector, Scope};
        use typst::introspection::{EmptyIntrospector, Introspector};
        use typst::routines::SpanMode;
        use typst::syntax::{Span, SyntaxMode};
        use typst_eval::eval_string;

        let sel_value = eval_string(
            (&self.world as &dyn World).track(),
            self.world.library(),
            Sink::new().track_mut(),
            EmptyIntrospector.track(),
            Context::none().track(),
            &selector,
            SpanMode::Uniform(Span::detached()),
            SyntaxMode::Code,
            Scope::default(),
        )
        .map_err(|errors| {
            let mut message = String::from("failed to evaluate selector");
            for (i, error) in errors.into_iter().enumerate() {
                message.push_str(if i == 0 { ": " } else { ", " });
                message.push_str(&error.message);
            }
            message
        })?;

        let locatable = sel_value
            .cast::<LocatableSelector>()
            .map_err(|e| format!("Invalid selector: {:?}", e))?;

        let elements = document
            .inner
            .introspector()
            .query(&locatable.0)
            .into_iter()
            .collect::<Vec<_>>();

        let array: typst::foundations::Array =
            elements.into_iter().map(IntoValue::into_value).collect();
        serde_json::to_string(&array).map_err(|e| format!("JSON error: {}", e))
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
    /// Thread-safe in-memory cache of downloaded packages.
    /// Key: PackageSpec (namespace + name + version)
    /// Value: Map of virtual path (e.g. "lib.typ") → file bytes
    package_cache: RwLock<HashMap<PackageSpec, HashMap<String, Bytes>>>,
    /// Whether to allow downloading packages from the registry.
    allow_packages: bool,
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
            package_cache: RwLock::new(HashMap::new()),
            allow_packages: true,
        }
    }

    fn set_allow_packages(&mut self, allow: bool) {
        self.allow_packages = allow;
    }

    fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        for data in font_data {
            let bytes = Bytes::new(data);
            self.fonts.extend(Font::iter(bytes));
        }
        self.book = LazyHash::new(FontBook::from_fonts(&self.fonts));
    }

    fn set_markup(&mut self, markup: String) {
        if self.source.text() != markup {
            self.source = Source::new(self.source.id(), markup);
        }
    }

    /// Replaces the entire virtual file system for the next compilation.
    ///
    /// The VFS is reset on every call so that stale files from a previous
    /// compilation do not bleed into the next one. Callers pass the complete
    /// desired file set each time (an empty `virtual_files` means no files).
    fn set_files(&mut self, virtual_files: Vec<VirtualFile>) {
        let mut new_keys = std::collections::HashSet::new();
        for vf in virtual_files {
            let normalised = vf.path.replace('\\', "/");
            new_keys.insert(normalised.clone());

            let new_bytes = Bytes::new(vf.bytes);
            if self
                .files
                .get(&normalised)
                .is_some_and(|existing| existing.as_slice() == new_bytes.as_slice())
            {
                continue; // Skip if bytes are identical to preserve cache
            }
            self.files.insert(normalised, new_bytes);
        }
        self.files.retain(|k, _| new_keys.contains(k));
    }

    fn set_sys_time(&mut self, sys_time: Option<i64>) {
        self.sys_time = sys_time;
    }

    fn set_inputs(&mut self, inputs: Option<HashMap<String, String>>) {
        let mut dict = Dict::new();
        if let Some(map) = inputs {
            for (k, v) in map {
                dict.insert(k.into(), v.into_value());
            }
        }
        self.library = LazyHash::new(Library::builder().with_inputs(dict).build());
    }

    /// Downloads and caches a Typst package from the official registry.
    ///
    /// Fetches `https://packages.typst.org/{namespace}/{name}-{version}.tar.gz`,
    /// decompresses it, and stores all files in `self.package_cache`.
    ///
    /// No-ops if the package is already cached.
    fn resolve_package(&self, spec: &PackageSpec) -> Result<(), FileError> {
        // Fast path: already cached
        {
            let cache = self.package_cache.read().map_err(|e| {
                FileError::Other(Some(format!("package cache lock error: {e}").into()))
            })?;
            if cache.contains_key(spec) {
                return Ok(());
            }
        }

        if !self.allow_packages {
            return Err(FileError::Other(Some(
                format!("package resolution is disabled; cannot download {spec}").into(),
            )));
        }

        if spec.namespace.as_str() != "preview" {
            return Err(FileError::Other(Some(
                format!(
                    "unsupported package namespace '{}' (only '@preview' is supported)",
                    spec.namespace
                )
                .into(),
            )));
        }

        let url = format!(
            "https://packages.typst.org/{}/{}-{}.tar.gz",
            spec.namespace, spec.name, spec.version
        );

        // Download the archive
        let response = ureq::get(&url).call().map_err(|e| {
            FileError::Other(Some(
                format!("failed to download package {spec} from {url}: {e}").into(),
            ))
        })?;

        let mut compressed = Vec::new();
        response
            .into_body()
            .as_reader()
            .read_to_end(&mut compressed)
            .map_err(|e| {
                FileError::Other(Some(
                    format!("failed to read package {spec} body: {e}").into(),
                ))
            })?;

        // Decompress gzip and extract tar
        let decoder = flate2::read::GzDecoder::new(&compressed[..]);
        let mut archive = tar::Archive::new(decoder);

        let mut raw_entries: Vec<(String, Vec<u8>)> = Vec::new();
        let mut root_prefix: Option<String> = None;

        for entry in archive.entries().map_err(|e| {
            FileError::Other(Some(
                format!("failed to read tar entries for {spec}: {e}").into(),
            ))
        })? {
            let mut entry = entry.map_err(|e| {
                FileError::Other(Some(
                    format!("failed to read tar entry for {spec}: {e}").into(),
                ))
            })?;

            if entry.header().entry_type().is_dir() {
                continue;
            }

            let path = entry.path().map_err(|e| {
                FileError::Other(Some(format!("invalid path in {spec}: {e}").into()))
            })?;

            let path_str = path.to_string_lossy().replace('\\', "/");
            let path_clean = path_str.trim_start_matches("./").to_string();

            let mut data = Vec::new();
            entry.read_to_end(&mut data).map_err(|e| {
                FileError::Other(Some(
                    format!("failed to read file {path_clean} from {spec}: {e}").into(),
                ))
            })?;

            if path_clean == "typst.toml" {
                root_prefix = Some(String::new());
            } else if path_clean.ends_with("/typst.toml") {
                let prefix_len = path_clean.len() - "typst.toml".len();
                root_prefix = Some(path_clean[..prefix_len].to_string());
            }

            raw_entries.push((path_clean, data));
        }

        let prefix = root_prefix.unwrap_or_else(|| {
            if let Some((first_path, _)) = raw_entries.first()
                && let Some(idx) = first_path.find('/')
            {
                return first_path[..=idx].to_string();
            }
            String::new()
        });

        let mut files = HashMap::new();
        for (path, data) in raw_entries {
            let normalized = if !prefix.is_empty() && path.starts_with(&prefix) {
                path[prefix.len()..].trim_start_matches('/').to_string()
            } else {
                path.trim_start_matches('/').to_string()
            };

            if !normalized.is_empty() {
                files.insert(normalized, Bytes::new(data));
            }
        }

        let mut cache = self
            .package_cache
            .write()
            .map_err(|e| FileError::Other(Some(format!("package cache lock error: {e}").into())))?;
        cache.insert(spec.clone(), files);
        Ok(())
    }

    fn resolve_package_file(
        &self,
        spec: &PackageSpec,
        vpath: &VirtualPath,
    ) -> Result<Bytes, FileError> {
        let key = vpath.get_without_slash().replace('\\', "/");

        // 1. Check cache
        {
            let cache = self.package_cache.read().map_err(|e| {
                FileError::Other(Some(format!("package cache lock error: {e}").into()))
            })?;
            if let Some(pkg_files) = cache.get(spec) {
                return pkg_files
                    .get(&key)
                    .cloned()
                    .ok_or_else(|| FileError::NotFound(format!("{spec}/{key}").into()));
            }
        }

        // 2. Not cached: try on-demand download if allowed
        if !self.allow_packages {
            return Err(FileError::Other(Some(
                format!("package resolution is disabled; cannot download {spec}").into(),
            )));
        }

        self.resolve_package(spec)?;

        // 3. Read from cache after download
        let cache = self
            .package_cache
            .read()
            .map_err(|e| FileError::Other(Some(format!("package cache lock error: {e}").into())))?;
        let pkg_files = cache.get(spec).ok_or_else(|| {
            FileError::Other(Some(
                format!("package {spec} not found in cache after download").into(),
            ))
        })?;

        pkg_files
            .get(&key)
            .cloned()
            .ok_or_else(|| FileError::NotFound(format!("{spec}/{key}").into()))
    }

    /// Scans the main source (and any included .typ files in the VFS) for
    /// package import patterns and pre-downloads them.
    fn pre_resolve_packages(&mut self) -> Result<(), TypstCompileError> {
        let mut specs_to_resolve: Vec<PackageSpec> = Vec::new();

        // Scan main source for @namespace/name:version patterns
        self.collect_package_specs(self.source.text(), &mut specs_to_resolve);

        // Also scan any .typ files in the VFS
        for (key, bytes) in &self.files {
            if key.ends_with(".typ")
                && let Ok(text) = std::str::from_utf8(bytes)
            {
                self.collect_package_specs(text, &mut specs_to_resolve);
            }
        }

        // Resolve each unique package and its transitive deps
        let mut resolved: std::collections::HashSet<PackageSpec> = std::collections::HashSet::new();
        let mut queue = std::collections::VecDeque::from(specs_to_resolve);

        while let Some(spec) = queue.pop_front() {
            if resolved.contains(&spec) {
                continue;
            }

            self.resolve_package(&spec).map_err(|e| TypstCompileError {
                diagnostics: vec![TypstDiagnostic {
                    severity: TypstSeverity::Error,
                    message: format!("Failed to resolve package {spec}: {e}"),
                    hints: vec![],
                    span_start: None,
                    span_end: None,
                }],
            })?;

            resolved.insert(spec.clone());

            // Scan newly downloaded package files for transitive deps
            let cache = self.package_cache.read().map_err(|e| TypstCompileError {
                diagnostics: vec![TypstDiagnostic {
                    severity: TypstSeverity::Error,
                    message: format!("Lock error reading package cache: {e}"),
                    hints: vec![],
                    span_start: None,
                    span_end: None,
                }],
            })?;

            if let Some(pkg_files) = cache.get(&spec) {
                for (path, bytes) in pkg_files {
                    if path.ends_with(".typ")
                        && let Ok(text) = std::str::from_utf8(bytes)
                    {
                        let mut transitive = Vec::new();
                        self.collect_package_specs(text, &mut transitive);
                        for ts in transitive {
                            if !resolved.contains(&ts) {
                                queue.push_back(ts);
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// Extracts PackageSpec values from `@namespace/name:major.minor.patch` patterns.
    fn collect_package_specs(&self, text: &str, out: &mut Vec<PackageSpec>) {
        let mut chars = text.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch != '@' {
                continue;
            }
            if let Some(spec) = Self::try_parse_package_spec(&mut chars) {
                out.push(spec);
            }
        }
    }

    fn try_parse_package_spec(
        chars: &mut std::iter::Peekable<std::str::Chars<'_>>,
    ) -> Option<PackageSpec> {
        // Parse namespace (alphanumeric + hyphens)
        let mut namespace = String::new();
        while let Some(&ch) = chars.peek() {
            if ch.is_alphanumeric() || ch == '-' {
                namespace.push(ch);
                chars.next();
            } else {
                break;
            }
        }
        if namespace.is_empty() || chars.next() != Some('/') {
            return None;
        }

        // Parse name (alphanumeric + hyphens + underscores)
        let mut name = String::new();
        while let Some(&ch) = chars.peek() {
            if ch.is_alphanumeric() || ch == '-' || ch == '_' {
                name.push(ch);
                chars.next();
            } else {
                break;
            }
        }
        if name.is_empty() || chars.next() != Some(':') {
            return None;
        }

        // Parse version (major.minor.patch)
        let mut version_str = String::new();
        while let Some(&ch) = chars.peek() {
            if ch.is_ascii_digit() || ch == '.' {
                version_str.push(ch);
                chars.next();
            } else {
                break;
            }
        }

        let parts: Vec<&str> = version_str.split('.').collect();
        if parts.len() != 3 {
            return None;
        }

        let major = parts[0].parse().ok()?;
        let minor = parts[1].parse().ok()?;
        let patch = parts[2].parse().ok()?;

        Some(PackageSpec {
            namespace: namespace.into(),
            name: name.into(),
            version: typst::syntax::package::PackageVersion {
                major,
                minor,
                patch,
            },
        })
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

        match id.root() {
            VirtualRoot::Project => {
                let vpath = id.vpath();
                let key = vpath.get_without_slash().replace('\\', "/");
                match self.files.get(&key) {
                    Some(bytes) => {
                        let text =
                            std::str::from_utf8(bytes).map_err(|_| FileError::InvalidUtf8)?;
                        Ok(Source::new(id, text.to_string()))
                    }
                    None => Err(FileError::NotFound(vpath.get_without_slash().into())),
                }
            }
            VirtualRoot::Package(spec) => {
                let bytes = self.resolve_package_file(spec, id.vpath())?;
                let text = std::str::from_utf8(&bytes).map_err(|_| FileError::InvalidUtf8)?;
                Ok(Source::new(id, text.to_string()))
            }
        }
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        match id.root() {
            VirtualRoot::Project => {
                let vpath = id.vpath();
                let key = vpath.get_without_slash().replace('\\', "/");
                self.files
                    .get(&key)
                    .cloned()
                    .ok_or_else(|| FileError::NotFound(vpath.get_without_slash().into()))
            }
            VirtualRoot::Package(spec) => self.resolve_package_file(spec, id.vpath()),
        }
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
        let doc = engine
            .compile("= Hello".to_string(), vec![], None, None, true)
            .unwrap();
        let pdf = doc.export_pdf().unwrap();
        assert!(!pdf.is_empty());
        assert_eq!(doc.page_count(), 1);
    }

    #[test]
    fn test_compile_error() {
        let mut engine = TypstEngine::new();
        let result = engine.compile("#invalid_call()".to_string(), vec![], None, None, true);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(!err.diagnostics.is_empty());
        assert_eq!(err.diagnostics[0].severity, TypstSeverity::Error);
    }

    #[test]
    fn test_svg_export() {
        let mut engine = TypstEngine::new();
        let doc = engine
            .compile("= Hello".to_string(), vec![], None, None, true)
            .unwrap();
        let svg = doc.export_svg(0).unwrap();
        assert!(svg.contains("<svg"));
    }

    #[test]
    fn test_page_info() {
        let mut engine = TypstEngine::new();
        let doc = engine
            .compile("= Hello".to_string(), vec![], None, None, true)
            .unwrap();
        let info = doc.page_info(0).unwrap();
        assert!(info.width_pt > 0.0);
        assert!(info.height_pt > 0.0);

        let err = doc.page_info(1);
        assert!(err.is_err());
    }

    #[test]
    fn test_render_page() {
        let mut engine = TypstEngine::new();
        let doc = engine
            .compile("= Hello".to_string(), vec![], None, None, true)
            .unwrap();
        let render = doc.render_page(0, 2.0).unwrap();
        assert!(render.width > 0);
        assert!(render.height > 0);
        assert!(!render.bytes.is_empty());

        let err = doc.render_page(1, 2.0);
        assert!(err.is_err());
    }

    #[test]
    fn test_query() {
        let mut engine = TypstEngine::new();
        let doc = engine
            .compile(
                "= Heading 1\n<my-label>".to_string(),
                vec![],
                None,
                None,
                true,
            )
            .unwrap();
        let json = engine.query(&doc, "<my-label>".to_string()).unwrap();
        assert!(json.contains("Heading 1"));
    }

    #[test]
    fn test_export_svg_out_of_bounds() {
        let mut engine = TypstEngine::new();
        let doc = engine
            .compile("= Hello".to_string(), vec![], None, None, true)
            .unwrap();
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
    fn test_collect_package_specs() {
        let world = SimpleWorld::new();
        let text = r#"
            #import "@preview/tablex:0.0.8": tablex
            #import "@preview/cetz:0.3.0": *
            Some text without imports
            #import "@local/my-pkg:1.2.3": foo
        "#;
        let mut specs = Vec::new();
        world.collect_package_specs(text, &mut specs);
        assert_eq!(specs.len(), 3);
        assert_eq!(specs[0].namespace.as_str(), "preview");
        assert_eq!(specs[0].name.as_str(), "tablex");
        assert_eq!(specs[0].version.major, 0);
        assert_eq!(specs[0].version.minor, 0);
        assert_eq!(specs[0].version.patch, 8);
        assert_eq!(specs[1].name.as_str(), "cetz");
        assert_eq!(specs[2].namespace.as_str(), "local");
    }

    #[test]
    fn test_package_spec_parsing_edge_cases() {
        let world = SimpleWorld::new();

        // Invalid: no version
        let mut specs = Vec::new();
        world.collect_package_specs(r#"#import "@preview/pkg""#, &mut specs);
        assert!(specs.is_empty());

        // Invalid: partial version
        let mut specs = Vec::new();
        world.collect_package_specs(r#"#import "@preview/pkg:1.2""#, &mut specs);
        assert!(specs.is_empty());

        // Valid: in string context
        let mut specs = Vec::new();
        world.collect_package_specs(r#"@preview/valid_name-2:1.0.0"#, &mut specs);
        assert_eq!(specs.len(), 1);
        assert_eq!(specs[0].name.as_str(), "valid_name-2");
    }

    #[test]
    fn test_compile_disallow_packages() {
        let mut engine = TypstEngine::new();
        let result = engine.compile(
            r#"#import "@preview/tablex:0.0.8": *"#.to_string(),
            vec![],
            None,
            None,
            false, // allow_packages = false
        );
        assert!(result.is_err());
    }

    #[test]
    #[ignore] // Run with: cargo test -- --ignored
    fn test_package_download_and_compile() {
        let mut engine = TypstEngine::new();
        let result = engine.compile(
            r#"#import "@preview/cetz:0.3.4": canvas, draw
#canvas({
  draw.line((0, 0), (1, 1))
})"#
            .to_string(),
            vec![],
            None,
            None,
            true,
        );
        assert!(
            result.is_ok(),
            "Failed to compile with package: {:?}",
            result.err()
        );
        let doc = result.unwrap();
        assert_eq!(doc.page_count(), 1);
    }

    #[test]
    fn test_coverage_extra() {
        use typst::World;
        let mut engine = TypstEngine::new();

        let font_data = include_bytes!("../../assets/fonts/DejaVuSansMono.ttf").to_vec();
        engine.add_fonts(vec![font_data]);

        let world = SimpleWorld::new();
        let today = world.today(None);
        assert!(today.is_some());

        // Test Detached span via syntax error or manual
        let markup = "#set text(font: \"__NonExistent__\")\n= Test\n#assert(1 == 1)".to_string();
        let doc = engine.compile(markup, vec![], None, None, true).unwrap();
        let _warnings = doc.warnings();

        // 1. Cover query evaluate selector error (lines 245-251)
        let query_err = engine.query(&doc, "<invalid> syntax".to_string());
        assert!(query_err.is_err());

        // 2. Cover DiagSpanKind::Range or Detached
        // We can just construct a SourceDiagnostic and map it directly
        use typst::diag::SourceDiagnostic;
        use typst::syntax::Span;
        let diag = SourceDiagnostic::error(Span::detached(), "Detached error");
        let mapped = map_diagnostic(&diag, &world);
        assert!(mapped.span_start.is_none());

        // 3. Cover set_inputs loop
        let mut inputs = HashMap::new();
        inputs.insert("test_key".to_string(), "test_val".to_string());
        let _ = engine.compile(
            "#sys.inputs.test_key".to_string(),
            vec![],
            None,
            Some(inputs),
            true,
        );
    }

    #[test]
    fn test_vfs_identical_cache_continue() {
        let mut world = SimpleWorld::new();
        let files = vec![VirtualFile {
            path: "test.png".to_string(),
            bytes: b"fake_png_data".to_vec(),
        }];
        world.set_files(files.clone());
        world.set_files(files); // This should hit the 'continue'
    }

    #[test]
    fn test_diag_span_range() {
        use typst::syntax::{DiagSpan, FileId, RootedPath, VirtualPath, VirtualRoot};
        let world = SimpleWorld::new();
        let id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("main.typ").unwrap(),
        ));
        let diag_span = DiagSpan::from_range(id, 0..1);
        let res = resolve_span(diag_span, &world);
        assert!(res.is_some());
    }
}
