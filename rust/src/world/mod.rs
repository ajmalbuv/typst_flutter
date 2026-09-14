use std::collections::HashMap;

use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime, Dict, Duration, IntoValue};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt};

use crate::api::typst::{TypstCompileError, VirtualFile};
use crate::package::PackageResolver;

// ── FontManager ─────────────────────────────────────────────────────────────

/// Manages embedded default fonts and dynamically registered user fonts.
pub(crate) struct FontManager {
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
}

impl FontManager {
    pub(crate) fn new() -> Self {
        let mut fonts = Vec::new();

        let bundled = [
            include_bytes!("../../assets/fonts/LibertinusSerif-Regular.otf").as_slice(),
            include_bytes!("../../assets/fonts/NewCMMath-Book.otf").as_slice(),
            include_bytes!("../../assets/fonts/DejaVuSansMono.ttf").as_slice(),
        ];

        for data in bundled {
            fonts.extend(Font::iter(Bytes::new(data.to_vec())));
        }

        Self {
            book: LazyHash::new(FontBook::from_fonts(&fonts)),
            fonts,
        }
    }

    pub(crate) fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        for data in font_data {
            let bytes = Bytes::new(data);
            self.fonts.extend(Font::iter(bytes));
        }
        self.book = LazyHash::new(FontBook::from_fonts(&self.fonts));
    }

    pub(crate) fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    pub(crate) fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    #[cfg(test)]
    pub(crate) fn font_count(&self) -> usize {
        self.fonts.len()
    }
}

// ── VirtualFileSystem ───────────────────────────────────────────────────────

/// In-memory project virtual file system. Normalises paths and caches file bytes.
#[derive(Default)]
pub(crate) struct VirtualFileSystem {
    files: HashMap<String, Bytes>,
}

impl VirtualFileSystem {
    pub(crate) fn new() -> Self {
        Self {
            files: HashMap::new(),
        }
    }

    /// Replaces project files, skipping byte-identical entries to preserve downstream cache.
    /// Returns `(changed_or_added_paths, removed_paths)`.
    pub(crate) fn set_files(
        &mut self,
        virtual_files: Vec<VirtualFile>,
    ) -> (Vec<String>, Vec<String>) {
        let mut new_keys = std::collections::HashSet::new();
        let mut changed_or_added = Vec::new();

        for vf in virtual_files {
            let normalised = vf.path.replace('\\', "/");
            new_keys.insert(normalised.clone());

            let new_bytes = Bytes::new(vf.bytes);
            if self
                .files
                .get(&normalised)
                .is_some_and(|existing| existing.as_slice() == new_bytes.as_slice())
            {
                continue;
            }
            changed_or_added.push(normalised.clone());
            self.files.insert(normalised, new_bytes);
        }

        let mut removed = Vec::new();
        self.files.retain(|k, _| {
            if new_keys.contains(k) {
                true
            } else {
                removed.push(k.clone());
                false
            }
        });

        (changed_or_added, removed)
    }

    pub(crate) fn get(&self, path: &str) -> Option<&Bytes> {
        self.files.get(path)
    }

    #[cfg(test)]
    pub(crate) fn contains(&self, path: &str) -> bool {
        self.files.contains_key(path)
    }

    #[cfg(test)]
    pub(crate) fn len(&self) -> usize {
        self.files.len()
    }

    #[cfg(test)]
    pub(crate) fn is_empty(&self) -> bool {
        self.files.is_empty()
    }

    pub(crate) fn files(&self) -> &HashMap<String, Bytes> {
        &self.files
    }
}

/// Computes the minimal replacement range in `old` and the replacement substring from `new`.
/// Guarantees that applying `old.edit(range, replacement)` produces `new`, and that all
/// slice boundaries are valid UTF-8 character boundaries.
pub(crate) fn compute_edit_range<'a>(old: &str, new: &'a str) -> (std::ops::Range<usize>, &'a str) {
    if old == new {
        return (0..0, "");
    }

    let mut prefix_bytes = old
        .bytes()
        .zip(new.bytes())
        .take_while(|(a, b)| a == b)
        .count();

    while !old.is_char_boundary(prefix_bytes) {
        prefix_bytes -= 1;
    }

    let old_rem = &old[prefix_bytes..];
    let new_rem = &new[prefix_bytes..];

    let mut suffix_bytes = old_rem
        .bytes()
        .rev()
        .zip(new_rem.bytes().rev())
        .take_while(|(a, b)| a == b)
        .count();

    while suffix_bytes > 0
        && (!old_rem.is_char_boundary(old_rem.len() - suffix_bytes)
            || !new_rem.is_char_boundary(new_rem.len() - suffix_bytes))
    {
        suffix_bytes -= 1;
    }

    let old_end = old.len() - suffix_bytes;
    let new_end = new.len() - suffix_bytes;

    (prefix_bytes..old_end, &new[prefix_bytes..new_end])
}

// ── SimpleWorld ─────────────────────────────────────────────────────────────

/// In-memory Typst World coordinator with incremental compilation caching.
pub(crate) struct SimpleWorld {
    pub(crate) library: LazyHash<Library>,
    pub(crate) font_manager: FontManager,
    pub(crate) source: Source,
    pub(crate) vfs: VirtualFileSystem,
    pub(crate) sys_time: Option<i64>,
    pub(crate) inputs: Option<HashMap<String, String>>,
    pub(crate) package_resolver: PackageResolver,
    pub(crate) sources: std::sync::RwLock<HashMap<FileId, Source>>,
}

impl SimpleWorld {
    pub(crate) fn new() -> Self {
        Self {
            library: LazyHash::new(Library::builder().build()),
            font_manager: FontManager::new(),
            source: Source::new(
                FileId::new(RootedPath::new(
                    VirtualRoot::Project,
                    VirtualPath::new("main.typ").unwrap(),
                )),
                "".into(),
            ),
            vfs: VirtualFileSystem::new(),
            sys_time: None,
            inputs: None,
            package_resolver: PackageResolver::new(),
            sources: std::sync::RwLock::new(HashMap::new()),
        }
    }

    pub(crate) fn set_allow_packages(&mut self, allow: bool) {
        self.package_resolver.set_allow_packages(allow);
    }

    pub(crate) fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        self.font_manager.add_fonts(font_data);
    }

    /// Incrementally updates the main source document using `Source::edit`.
    pub(crate) fn set_markup(&mut self, markup: String) {
        if self.source.text() == markup {
            return;
        }
        let (range, replacement) = compute_edit_range(self.source.text(), &markup);
        self.source.edit(range, replacement);
    }

    /// Updates virtual project files and keeps the parsed secondary source cache synchronized.
    pub(crate) fn set_files(&mut self, virtual_files: Vec<VirtualFile>) {
        let (changed, removed) = self.vfs.set_files(virtual_files);
        if !changed.is_empty() || !removed.is_empty() {
            let mut sources_guard = self.sources.write().unwrap();
            for path in removed {
                if let Ok(vpath) = VirtualPath::new(&path) {
                    let id = FileId::new(RootedPath::new(VirtualRoot::Project, vpath));
                    sources_guard.remove(&id);
                }
            }
            for path in changed {
                if let Ok(vpath) = VirtualPath::new(&path) {
                    let id = FileId::new(RootedPath::new(VirtualRoot::Project, vpath));
                    if let Some(bytes) = self.vfs.get(&path) {
                        if let Ok(text) = std::str::from_utf8(bytes) {
                            if let Some(existing_source) = sources_guard.get_mut(&id) {
                                if existing_source.text() != text {
                                    let (range, replacement) =
                                        compute_edit_range(existing_source.text(), text);
                                    existing_source.edit(range, replacement);
                                }
                            } else {
                                sources_guard.insert(id, Source::new(id, text.to_string()));
                            }
                        } else {
                            sources_guard.remove(&id);
                        }
                    }
                }
            }
        }
    }

    pub(crate) fn set_sys_time(&mut self, sys_time: Option<i64>) {
        self.sys_time = sys_time;
    }

    pub(crate) fn set_inputs(&mut self, inputs: Option<HashMap<String, String>>) {
        if self.inputs != inputs {
            self.inputs = inputs.clone();
            let mut dict = Dict::new();
            if let Some(map) = inputs {
                for (k, v) in map {
                    dict.insert(k.into(), v.into_value());
                }
            }
            self.library = LazyHash::new(Library::builder().with_inputs(dict).build());
        }
    }

    pub(crate) fn pre_resolve_packages(&mut self) -> Result<(), TypstCompileError> {
        let source_text = self.source.text().to_string();
        let files = self.vfs.files().clone();
        self.package_resolver
            .pre_resolve_packages(&source_text, &files)
    }
}

impl typst::World for SimpleWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        self.font_manager.book()
    }

    fn main(&self) -> FileId {
        self.source.id()
    }

    fn source(&self, id: FileId) -> Result<Source, FileError> {
        // Fast path: the main file.
        if id == self.source.id() {
            return Ok(self.source.clone());
        }

        // Fast path: check the cached sources.
        {
            let sources_guard = self.sources.read().unwrap();
            if let Some(src) = sources_guard.get(&id) {
                return Ok(src.clone());
            }
        }

        // Cache miss: resolve bytes, parse into Source, and cache it.
        let text = match id.root() {
            VirtualRoot::Project => {
                let vpath = id.vpath();
                let key = vpath.get_without_slash().replace('\\', "/");
                match self.vfs.get(&key) {
                    Some(bytes) => std::str::from_utf8(bytes)
                        .map_err(|_| FileError::InvalidUtf8)?
                        .to_string(),
                    None => return Err(FileError::NotFound(vpath.get_without_slash().into())),
                }
            }
            VirtualRoot::Package(spec) => {
                let bytes = self
                    .package_resolver
                    .resolve_package_file(spec, id.vpath())?;
                std::str::from_utf8(&bytes)
                    .map_err(|_| FileError::InvalidUtf8)?
                    .to_string()
            }
        };

        let new_source = Source::new(id, text);
        let mut sources_guard = self.sources.write().unwrap();
        sources_guard.insert(id, new_source.clone());
        Ok(new_source)
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.font_manager.font(index)
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        match id.root() {
            VirtualRoot::Project => {
                let vpath = id.vpath();
                let key = vpath.get_without_slash().replace('\\', "/");
                self.vfs
                    .get(&key)
                    .cloned()
                    .ok_or_else(|| FileError::NotFound(vpath.get_without_slash().into()))
            }
            VirtualRoot::Package(spec) => {
                self.package_resolver.resolve_package_file(spec, id.vpath())
            }
        }
    }

    fn today(&self, offset: Option<Duration>) -> Option<Datetime> {
        let base_timestamp = self.sys_time.unwrap_or_else(|| {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64
        });

        let offset_secs = offset.map(|d| d.seconds() as i64).unwrap_or(0);
        let final_timestamp = base_timestamp + offset_secs;

        time::OffsetDateTime::from_unix_timestamp(final_timestamp)
            .ok()
            .and_then(|dt| Datetime::from_ymd(dt.year(), dt.month() as u8, dt.day()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use typst::World;
    use typst::syntax::{FileId, RootedPath, VirtualPath, VirtualRoot, package::PackageSpec};

    #[test]
    fn test_world_initialization_bundled_fonts() {
        let world = SimpleWorld::new();
        // Check that bundled fonts are loaded
        assert!(world.font_manager.font_count() >= 3);
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
        assert!(world.vfs.contains("subdir/test.typ"));
        assert_eq!(
            world.vfs.get("subdir/test.typ").unwrap().as_slice(),
            b"= Test"
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
    fn test_vfs_source_and_file() {
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
        let mut world = SimpleWorld::new();
        world.set_sys_time(Some(1609459200)); // 2021-01-01T00:00:00Z
        let today = world.today(None).unwrap();
        assert_eq!(today.year(), Some(2021));
        assert_eq!(today.month(), Some(1));
        assert_eq!(today.day(), Some(1));

        // With offset
        let d1 = Datetime::from_ymd(2021, 1, 2).unwrap();
        let d0 = Datetime::from_ymd(2021, 1, 1).unwrap();
        let offset = (d1 - d0).unwrap();
        let today_offset = world.today(Some(offset)).unwrap();
        assert_eq!(today_offset.day(), Some(2));

        // System time fallback
        let world_default_time = SimpleWorld::new();
        assert!(world_default_time.today(None).is_some());
    }

    #[test]
    fn test_world_methods_and_state() {
        let mut world = SimpleWorld::new();

        let _ = world.library();
        let _ = world.book();
        assert_eq!(world.main(), world.source.id());
        assert!(world.font(0).is_some());
        assert!(world.font(999_999).is_none());

        // set_markup with identical text (hits no-op branch)
        world.set_markup("identical".to_string());
        world.set_markup("identical".to_string());

        // set_files with cleanup
        world.set_files(vec![VirtualFile {
            path: "temp.txt".to_string(),
            bytes: vec![1, 2, 3],
        }]);
        assert_eq!(world.vfs.len(), 1);
        world.set_files(vec![]);
        assert!(world.vfs.is_empty());

        // set_inputs with None
        world.set_inputs(None);

        // add_fonts
        let initial_len = world.font_manager.font_count();
        world.add_fonts(vec![]);
        assert_eq!(world.font_manager.font_count(), initial_len);
    }

    #[test]
    fn test_package_transitive_and_vfs_scan() {
        let mut world = SimpleWorld::new();

        let spec_a = PackageSpec {
            namespace: "preview".into(),
            name: "pkg-a".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };
        let spec_b = PackageSpec {
            namespace: "preview".into(),
            name: "pkg-b".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        let mut files_a = HashMap::new();
        files_a.insert(
            "typst.toml".to_string(),
            Bytes::new(
                b"[package]\nname = \"pkg-a\"\nversion = \"1.0.0\"\nentrypoint = \"lib.typ\""
                    .to_vec(),
            ),
        );
        files_a.insert(
            "lib.typ".to_string(),
            Bytes::new(b"#import \"@preview/pkg-b:1.0.0\": val_b\n#let val_a = val_b".to_vec()),
        );

        let mut files_b = HashMap::new();
        files_b.insert(
            "typst.toml".to_string(),
            Bytes::new(
                b"[package]\nname = \"pkg-b\"\nversion = \"1.0.0\"\nentrypoint = \"lib.typ\""
                    .to_vec(),
            ),
        );
        files_b.insert(
            "lib.typ".to_string(),
            Bytes::new(b"#let val_b = [Transitive Value]".to_vec()),
        );

        {
            let mut cache = world.package_resolver.cache.write().unwrap();
            cache.insert(spec_a.clone(), files_a);
            cache.insert(spec_b.clone(), files_b);
        }

        // Put a .typ file in VFS that also references pkg-a
        world.set_markup(r#"#include "helper.typ""#.to_string());
        world.set_files(vec![VirtualFile {
            path: "helper.typ".to_string(),
            bytes: b"#import \"@preview/pkg-a:1.0.0\": val_a".to_vec(),
        }]);

        let res = world.pre_resolve_packages();
        assert!(res.is_ok());

        // Test world.source() via VirtualRoot::Package
        let pkg_id_lib = FileId::new(RootedPath::new(
            VirtualRoot::Package(spec_b.clone()),
            VirtualPath::new("lib.typ").unwrap(),
        ));
        let src = world.source(pkg_id_lib).unwrap();
        assert_eq!(src.text(), "#let val_b = [Transitive Value]");

        // Test world.source() via VirtualRoot::Package for invalid UTF-8
        let mut files_bad = HashMap::new();
        files_bad.insert("bad.typ".to_string(), Bytes::new(vec![0xFF, 0xFE]));
        world
            .package_resolver
            .cache
            .write()
            .unwrap()
            .insert(spec_a.clone(), files_bad);
        let pkg_id_bad = FileId::new(RootedPath::new(
            VirtualRoot::Package(spec_a),
            VirtualPath::new("bad.typ").unwrap(),
        ));
        assert!(world.source(pkg_id_bad).is_err());

        // Test set_inputs with actual key-values
        let mut map = HashMap::new();
        map.insert("author".to_string(), "Alice".to_string());
        world.set_inputs(Some(map));
        let _ = world.library();
    }

    #[test]
    fn test_compute_edit_range_edge_cases() {
        // Identical
        assert_eq!(compute_edit_range("hello", "hello"), (0..0, ""));
        assert_eq!(compute_edit_range("", ""), (0..0, ""));

        // Insertions
        assert_eq!(compute_edit_range("", "a"), (0..0, "a"));
        assert_eq!(compute_edit_range("hello", "hello world"), (5..5, " world"));
        assert_eq!(compute_edit_range("world", "hello world"), (0..0, "hello "));
        assert_eq!(compute_edit_range("ac", "abc"), (1..1, "b"));

        // Deletions
        assert_eq!(compute_edit_range("a", ""), (0..1, ""));
        assert_eq!(compute_edit_range("hello world", "hello"), (5..11, ""));
        assert_eq!(compute_edit_range("hello world", "world"), (0..6, ""));
        assert_eq!(compute_edit_range("abc", "ac"), (1..2, ""));

        // Replacements
        assert_eq!(compute_edit_range("foo", "bar"), (0..3, "bar"));
        assert_eq!(
            compute_edit_range("The quick brown fox", "The fast brown fox"),
            (4..9, "fast")
        );

        // Multi-byte UTF-8 emoji
        let old = "hello 🦀 world";
        let new = "hello 🦞 world";
        let (range, rep) = compute_edit_range(old, new);
        assert_eq!(rep, "🦞");
        let mut s = old.to_string();
        s.replace_range(range, rep);
        assert_eq!(s, new);

        // UTF-8 multi-byte insertion/deletion
        let old_c = "café";
        let new_c = "cafeteria";
        let (range_c, rep_c) = compute_edit_range(old_c, new_c);
        let mut sc = old_c.to_string();
        sc.replace_range(range_c, rep_c);
        assert_eq!(sc, new_c);
    }

    #[test]
    fn test_incremental_set_markup() {
        let mut world = SimpleWorld::new();
        assert_eq!(world.source.text(), "");

        // Step 1: Initial markup
        world.set_markup("= Hello Typst\nThis is a test.".to_string());
        assert_eq!(world.source.text(), "= Hello Typst\nThis is a test.");

        // Step 2: Typing a character
        world.set_markup("= Hello Typst!\nThis is a test.".to_string());
        assert_eq!(world.source.text(), "= Hello Typst!\nThis is a test.");

        // Step 3: Deleting words
        world.set_markup("= Hello Typst!\nThis is.".to_string());
        assert_eq!(world.source.text(), "= Hello Typst!\nThis is.");

        // Step 4: Identical markup is no-op
        world.set_markup("= Hello Typst!\nThis is.".to_string());
        assert_eq!(world.source.text(), "= Hello Typst!\nThis is.");
    }

    #[test]
    fn test_incremental_secondary_source_caching() {
        let mut world = SimpleWorld::new();
        let file_path = "sub/helper.typ";
        world.set_files(vec![VirtualFile {
            path: file_path.to_string(),
            bytes: b"= Helper Section".to_vec(),
        }]);

        let id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new(file_path).unwrap(),
        ));

        // First read: parsed and cached
        let src1 = world.source(id).unwrap();
        assert_eq!(src1.text(), "= Helper Section");

        // Second read: retrieved from cache
        let src2 = world.source(id).unwrap();
        assert_eq!(src2.text(), "= Helper Section");

        // File updated: edits secondary source
        world.set_files(vec![VirtualFile {
            path: file_path.to_string(),
            bytes: b"= Helper Section Updated".to_vec(),
        }]);
        let src3 = world.source(id).unwrap();
        assert_eq!(src3.text(), "= Helper Section Updated");

        // File removed: removed from cache
        world.set_files(vec![]);
        assert!(world.source(id).is_err());
    }

    #[test]
    fn test_incremental_compilation_roundtrip() {
        use typst_layout::PagedDocument;

        let mut world = SimpleWorld::new();
        world.set_markup("= Title\nFirst paragraph.".to_string());

        let doc1 = typst::compile::<PagedDocument>(&world).output.unwrap();
        assert_eq!(doc1.pages().len(), 1);

        // Incremental keystroke
        world.set_markup("= Title\nFirst paragraph with more text.".to_string());
        let doc2 = typst::compile::<PagedDocument>(&world).output.unwrap();
        assert_eq!(doc2.pages().len(), 1);
    }
}
