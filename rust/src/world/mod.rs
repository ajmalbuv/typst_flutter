use std::collections::HashMap;

use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime, Dict, Duration, IntoValue};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt};

use crate::api::typst::{TypstCompileError, VirtualFile};
use crate::package::PackageResolver;

/// In-memory Typst World implementation.
pub(crate) struct SimpleWorld {
    pub(crate) library: LazyHash<Library>,
    pub(crate) book: LazyHash<FontBook>,
    pub(crate) fonts: Vec<Font>,
    pub(crate) source: Source,
    /// Virtual file system: normalised path string -> file bytes.
    pub(crate) files: HashMap<String, Bytes>,
    pub(crate) sys_time: Option<i64>,
    /// Package resolution subsystem.
    pub(crate) package_resolver: PackageResolver,
}

impl SimpleWorld {
    pub(crate) fn new() -> Self {
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
            package_resolver: PackageResolver::new(),
        }
    }

    pub(crate) fn set_allow_packages(&mut self, allow: bool) {
        self.package_resolver.set_allow_packages(allow);
    }

    pub(crate) fn add_fonts(&mut self, font_data: Vec<Vec<u8>>) {
        for data in font_data {
            let bytes = Bytes::new(data);
            self.fonts.extend(Font::iter(bytes));
        }
        self.book = LazyHash::new(FontBook::from_fonts(&self.fonts));
    }

    pub(crate) fn set_markup(&mut self, markup: String) {
        if self.source.text() != markup {
            self.source = Source::new(self.source.id(), markup);
        }
    }

    /// Replaces the entire virtual file system for the next compilation.
    ///
    /// The VFS is reset on every call so that stale files from a previous
    /// compilation do not bleed into the next one.
    pub(crate) fn set_files(&mut self, virtual_files: Vec<VirtualFile>) {
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

    pub(crate) fn set_sys_time(&mut self, sys_time: Option<i64>) {
        self.sys_time = sys_time;
    }

    pub(crate) fn set_inputs(&mut self, inputs: Option<HashMap<String, String>>) {
        let mut dict = Dict::new();
        if let Some(map) = inputs {
            for (k, v) in map {
                dict.insert(k.into(), v.into_value());
            }
        }
        self.library = LazyHash::new(Library::builder().with_inputs(dict).build());
    }

    pub(crate) fn pre_resolve_packages(&mut self) -> Result<(), TypstCompileError> {
        let source_text = self.source.text().to_string();
        let files = self.files.clone();
        self.package_resolver
            .pre_resolve_packages(&source_text, &files)
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
                let bytes = self
                    .package_resolver
                    .resolve_package_file(spec, id.vpath())?;
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
        assert!(world.fonts.len() >= 3);
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
        assert_eq!(world.files.len(), 1);
        world.set_files(vec![]);
        assert!(world.files.is_empty());

        // set_inputs with None
        world.set_inputs(None);

        // add_fonts
        let initial_len = world.fonts.len();
        world.add_fonts(vec![]);
        assert_eq!(world.fonts.len(), initial_len);
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
}
