use std::collections::{HashMap, HashSet, VecDeque};
use std::io::Read;
use std::sync::RwLock;

use typst::diag::FileError;
use typst::foundations::Bytes;
use typst::syntax::{VirtualPath, package::PackageSpec};

use crate::api::typst::{TypstCompileError, TypstDiagnostic, TypstSeverity};

/// Domain error type for package downloads, decompression, and cache resolution.
#[derive(thiserror::Error, Debug)]
pub(crate) enum PackageError {
    #[error("package cache lock error: {0}")]
    Lock(String),

    #[error("package resolution is disabled; cannot download {0}")]
    Disabled(PackageSpec),

    #[error("unsupported package namespace '{0}' (only '@preview' is supported)")]
    UnsupportedNamespace(String),

    #[error("failed to download package {spec} from {url}: {source}")]
    Download {
        spec: PackageSpec,
        url: String,
        #[source]
        source: Box<ureq::Error>,
    },

    #[error("failed to read package {spec} body: {source}")]
    ReadBody {
        spec: PackageSpec,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to read tar entries for {spec}: {source}")]
    ReadArchive {
        spec: PackageSpec,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to read tar entry for {spec}: {source}")]
    ReadEntry {
        spec: PackageSpec,
        #[source]
        source: std::io::Error,
    },

    #[error("invalid path in {spec}: {source}")]
    InvalidPath {
        spec: PackageSpec,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to read file {path} from {spec}: {source}")]
    ReadFile {
        path: String,
        spec: PackageSpec,
        #[source]
        source: std::io::Error,
    },
}

impl From<PackageError> for FileError {
    fn from(err: PackageError) -> Self {
        FileError::Other(Some(err.to_string().into()))
    }
}

/// Manages package downloading, unpacking, and in-memory caching.
pub(crate) struct PackageResolver {
    /// Thread-safe in-memory cache of downloaded packages.
    /// Key: PackageSpec (namespace + name + version)
    /// Value: Map of virtual path (e.g. "lib.typ") -> file bytes
    pub(crate) cache: RwLock<HashMap<PackageSpec, HashMap<String, Bytes>>>,
    /// Whether to allow downloading packages from the registry.
    pub(crate) allow_packages: bool,
}

impl PackageResolver {
    pub(crate) fn new() -> Self {
        Self {
            cache: RwLock::new(HashMap::new()),
            allow_packages: true,
        }
    }

    pub(crate) fn set_allow_packages(&mut self, allow: bool) {
        self.allow_packages = allow;
    }

    /// Downloads and caches a Typst package from the official registry.
    /// Ensures a package is downloaded, unpacked, and cached, returning a clone of its virtual files.
    pub(crate) fn ensure_package(
        &self,
        spec: &PackageSpec,
    ) -> Result<HashMap<String, Bytes>, FileError> {
        // Fast path: already cached
        {
            let cache = self
                .cache
                .read()
                .map_err(|e| PackageError::Lock(e.to_string()))?;
            if let Some(files) = cache.get(spec) {
                return Ok(files.clone());
            }
        }

        if !self.allow_packages {
            return Err(PackageError::Disabled(spec.clone()).into());
        }

        if spec.namespace.as_str() != "preview" {
            return Err(PackageError::UnsupportedNamespace(spec.namespace.to_string()).into());
        }

        let url = format!(
            "https://packages.typst.org/{}/{}-{}.tar.gz",
            spec.namespace, spec.name, spec.version
        );

        // Download the archive
        let response = ureq::get(&url).call().map_err(|e| PackageError::Download {
            spec: spec.clone(),
            url: url.clone(),
            source: Box::new(e),
        })?;

        let mut compressed = Vec::new();
        response
            .into_body()
            .as_reader()
            .read_to_end(&mut compressed)
            .map_err(|e| PackageError::ReadBody {
                spec: spec.clone(),
                source: e,
            })?;

        let files = Self::unpack_package_archive(&compressed, spec)?;

        let mut cache = self
            .cache
            .write()
            .map_err(|e| PackageError::Lock(e.to_string()))?;
        cache.insert(spec.clone(), files.clone());
        Ok(files)
    }

    /// Downloads and caches a Typst package from the official registry.
    ///
    /// Fetches https://packages.typst.org/{namespace}/{name}-{version}.tar.gz,
    /// decompresses it, and stores all files in self.cache.
    ///
    /// No-ops if the package is already cached.
    #[cfg(test)]
    pub(crate) fn resolve_package(&self, spec: &PackageSpec) -> Result<(), FileError> {
        self.ensure_package(spec).map(|_| ())
    }

    /// Decompresses and extracts a package tar.gz archive in memory.
    pub(crate) fn unpack_package_archive(
        compressed: &[u8],
        spec: &PackageSpec,
    ) -> Result<HashMap<String, Bytes>, FileError> {
        let decoder = flate2::read::GzDecoder::new(compressed);
        let mut archive = tar::Archive::new(decoder);

        let mut raw_entries: Vec<(String, Vec<u8>)> = Vec::new();
        let mut root_prefix: Option<String> = None;

        for entry in archive.entries().map_err(|e| PackageError::ReadArchive {
            spec: spec.clone(),
            source: e,
        })? {
            let mut entry = entry.map_err(|e| PackageError::ReadEntry {
                spec: spec.clone(),
                source: e,
            })?;

            if entry.header().entry_type().is_dir() {
                continue;
            }

            let path = entry.path().map_err(|e| PackageError::InvalidPath {
                spec: spec.clone(),
                source: e,
            })?;

            let path_str = path.to_string_lossy().replace('\\', "/");
            let path_clean = path_str.trim_start_matches("./").to_string();

            let mut data = Vec::new();
            entry
                .read_to_end(&mut data)
                .map_err(|e| PackageError::ReadFile {
                    path: path_clean.clone(),
                    spec: spec.clone(),
                    source: e,
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

        Ok(files)
    }

    pub(crate) fn resolve_package_file(
        &self,
        spec: &PackageSpec,
        vpath: &VirtualPath,
    ) -> Result<Bytes, FileError> {
        let key = vpath.get_without_slash().replace('\\', "/");

        // 1. Check cache
        {
            let cache = self
                .cache
                .read()
                .map_err(|e| PackageError::Lock(e.to_string()))?;
            if let Some(pkg_files) = cache.get(spec) {
                return pkg_files
                    .get(&key)
                    .cloned()
                    .ok_or_else(|| FileError::NotFound(format!("{spec}/{key}").into()));
            }
        }

        // 2. Not cached: download and extract
        let files = self.ensure_package(spec)?;
        files
            .get(&key)
            .cloned()
            .ok_or_else(|| FileError::NotFound(format!("{spec}/{key}").into()))
    }

    /// Scans the main source (and any included .typ files in the VFS) for
    /// package import patterns and pre-downloads them.
    pub(crate) fn pre_resolve_packages(
        &mut self,
        source_text: &str,
        vfs_files: &HashMap<String, Bytes>,
    ) -> Result<(), TypstCompileError> {
        let mut specs_to_resolve: Vec<PackageSpec> = Vec::new();

        // Scan main source for @namespace/name:version patterns
        self.collect_package_specs(source_text, &mut specs_to_resolve);

        // Also scan any .typ files in the VFS
        for (key, bytes) in vfs_files {
            if key.ends_with(".typ")
                && let Ok(text) = std::str::from_utf8(bytes)
            {
                self.collect_package_specs(text, &mut specs_to_resolve);
            }
        }

        // Resolve each unique package and its transitive deps
        let mut resolved: HashSet<PackageSpec> = HashSet::new();
        let mut queue = VecDeque::from(specs_to_resolve);

        while let Some(spec) = queue.pop_front() {
            if resolved.contains(&spec) {
                continue;
            }

            let pkg_files = self.ensure_package(&spec).map_err(|e| TypstCompileError {
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
            for (path, bytes) in &pkg_files {
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

        Ok(())
    }

    /// Extracts PackageSpec values from @namespace/name:major.minor.patch patterns.
    pub(crate) fn collect_package_specs(&self, text: &str, out: &mut Vec<PackageSpec>) {
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

    pub(crate) fn try_parse_package_spec(
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

#[cfg(test)]
mod tests {
    use super::*;
    use typst::syntax::VirtualPath;

    #[test]
    fn test_collect_package_specs() {
        let resolver = PackageResolver::new();
        let text = r#"
            #import "@preview/tablex:0.0.8": tablex
            #import "@preview/cetz:0.3.0": *
            Some text without imports
            #import "@local/my-pkg:1.2.3": foo
        "#;
        let mut specs = Vec::new();
        resolver.collect_package_specs(text, &mut specs);
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
        let resolver = PackageResolver::new();

        let mut specs = Vec::new();
        resolver.collect_package_specs(r#"#import "@preview/pkg""#, &mut specs);
        assert!(specs.is_empty());

        let mut specs = Vec::new();
        resolver.collect_package_specs(r#"#import "@preview/pkg:1.2""#, &mut specs);
        assert!(specs.is_empty());

        let mut specs = Vec::new();
        resolver.collect_package_specs(r#"@preview/valid_name-2:1.0.0"#, &mut specs);
        assert_eq!(specs.len(), 1);
        assert_eq!(specs[0].name.as_str(), "valid_name-2");

        let mut specs = Vec::new();
        resolver.collect_package_specs(
            r#"@ invalid @/foo:1.0.0 @preview/:1.0.0 @preview/pkg:1.0.0.0 @preview/pkg:a.b.c @preview/pkg:1.b.0 @preview/pkg:1.0.c"#,
            &mut specs,
        );
        assert!(specs.is_empty());
    }

    #[test]
    fn test_package_in_memory_cache_and_resolution() {
        let resolver = PackageResolver::new();

        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "testpkg".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        let mut files = HashMap::new();
        files.insert(
            "typst.toml".to_string(),
            Bytes::new(
                b"[package]\nname = \"testpkg\"\nversion = \"1.0.0\"\nentrypoint = \"lib.typ\""
                    .to_vec(),
            ),
        );
        files.insert(
            "lib.typ".to_string(),
            Bytes::new(b"#let hello() = [Package Hello]".to_vec()),
        );
        files.insert(
            "logo.png".to_string(),
            Bytes::new(b"fake_logo_bytes".to_vec()),
        );
        files.insert("bad.typ".to_string(), Bytes::new(vec![0xFF, 0xFE]));

        resolver.cache.write().unwrap().insert(spec.clone(), files);

        // 1. resolve_package hitting fast cache path
        assert!(resolver.resolve_package(&spec).is_ok());

        // 2. resolve_package_file
        let lib_vpath = VirtualPath::new("lib.typ").unwrap();
        let lib_bytes = resolver.resolve_package_file(&spec, &lib_vpath).unwrap();
        assert_eq!(lib_bytes.as_slice(), b"#let hello() = [Package Hello]");

        let missing_vpath = VirtualPath::new("missing.typ").unwrap();
        assert!(
            resolver
                .resolve_package_file(&spec, &missing_vpath)
                .is_err()
        );
    }

    #[test]
    fn test_package_resolution_errors_and_edge_cases() {
        let mut resolver = PackageResolver::new();

        // 1. Unsupported namespace
        let local_spec = PackageSpec {
            namespace: "local".into(),
            name: "pkg".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };
        assert!(resolver.resolve_package(&local_spec).is_err());
        assert!(
            resolver
                .resolve_package_file(&local_spec, &VirtualPath::new("lib.typ").unwrap())
                .is_err()
        );

        // 2. Disabled packages
        resolver.set_allow_packages(false);
        let preview_spec = PackageSpec {
            namespace: "preview".into(),
            name: "pkg".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };
        assert!(resolver.resolve_package(&preview_spec).is_err());
        assert!(
            resolver
                .resolve_package_file(&preview_spec, &VirtualPath::new("lib.typ").unwrap())
                .is_err()
        );
    }

    #[test]
    fn test_package_download_live_and_compile() {
        let resolver = PackageResolver::new();
        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "cetz".into(),
            version: typst::syntax::package::PackageVersion {
                major: 0,
                minor: 3,
                patch: 4,
            },
        };
        let res = resolver.resolve_package(&spec);
        assert!(res.is_ok(), "Package resolve failed: {:?}", res.err());
        let file_res =
            resolver.resolve_package_file(&spec, &VirtualPath::new("typst.toml").unwrap());
        assert!(file_res.is_ok());
    }

    #[test]
    fn test_package_download_failure_and_on_demand() {
        let mut resolver = PackageResolver::new();

        // 1. Trigger failure in pre_resolve_packages
        let vfs = HashMap::new();
        let result = resolver.pre_resolve_packages(
            r#"#import "@preview/non-existent-pkg-404-xyz:0.0.1": *"#,
            &vfs,
        );
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(
            err.diagnostics[0]
                .message
                .contains("Failed to resolve package")
        );

        // 2. Trigger resolve_package_file on-demand when not cached
        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "cetz".into(),
            version: typst::syntax::package::PackageVersion {
                major: 0,
                minor: 3,
                patch: 4,
            },
        };
        let file_res =
            resolver.resolve_package_file(&spec, &VirtualPath::new("typst.toml").unwrap());
        assert!(file_res.is_ok());
    }

    #[test]
    fn test_unpack_package_archive_edge_cases() {
        use flate2::Compression;
        use flate2::write::GzEncoder;
        use tar::Builder;

        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "synthetic".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        // 1. Invalid compressed data
        assert!(PackageResolver::unpack_package_archive(b"not_gzip", &spec).is_err());

        // 2. Build tar.gz with subdirectory, nested typst.toml, and normal files
        let mut gz = GzEncoder::new(Vec::new(), Compression::default());
        {
            let mut tar = Builder::new(&mut gz);

            // Directory entry (should be skipped)
            let mut dir_header = tar::Header::new_gnu();
            dir_header.set_entry_type(tar::EntryType::Directory);
            dir_header.set_size(0);
            dir_header.set_mode(0o755);
            dir_header.set_cksum();
            tar.append_data(&mut dir_header, "pkg-dir/", &[][..])
                .unwrap();

            // Nested typst.toml
            let toml_data = b"[package]\nname=\"synthetic\"\nversion=\"1.0.0\"";
            let mut toml_header = tar::Header::new_gnu();
            toml_header.set_size(toml_data.len() as u64);
            toml_header.set_mode(0o644);
            toml_header.set_cksum();
            tar.append_data(&mut toml_header, "pkg-dir/typst.toml", &toml_data[..])
                .unwrap();

            // Nested lib.typ
            let lib_data = b"#let f() = []";
            let mut lib_header = tar::Header::new_gnu();
            lib_header.set_size(lib_data.len() as u64);
            lib_header.set_mode(0o644);
            lib_header.set_cksum();
            tar.append_data(&mut lib_header, "pkg-dir/lib.typ", &lib_data[..])
                .unwrap();

            tar.finish().unwrap();
        }
        let gz_bytes = gz.finish().unwrap();

        let files = PackageResolver::unpack_package_archive(&gz_bytes, &spec).unwrap();
        assert!(files.contains_key("typst.toml"));
        assert!(files.contains_key("lib.typ"));

        // 3. Tar archive without typst.toml (triggers fallback prefix)
        let mut gz2 = GzEncoder::new(Vec::new(), Compression::default());
        {
            let mut tar = Builder::new(&mut gz2);
            let data = b"content";
            let mut header = tar::Header::new_gnu();
            header.set_size(data.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "prefix/file.txt", &data[..])
                .unwrap();
            tar.finish().unwrap();
        }
        let gz2_bytes = gz2.finish().unwrap();
        let files2 = PackageResolver::unpack_package_archive(&gz2_bytes, &spec).unwrap();
        assert!(files2.contains_key("file.txt"));
    }

    #[test]
    fn test_package_resolver_lock_poisoning() {
        let resolver = PackageResolver::new();
        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "test".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        // Poison the lock intentionally via panic
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _guard = resolver.cache.write().unwrap();
            panic!("intentional lock poison");
        }));

        assert!(resolver.resolve_package(&spec).is_err());
        assert!(
            resolver
                .resolve_package_file(&spec, &VirtualPath::new("lib.typ").unwrap())
                .is_err()
        );

        let mut mut_resolver = resolver;
        let vfs = HashMap::new();
        assert!(
            mut_resolver
                .pre_resolve_packages(r#"#import "@preview/test:1.0.0": *"#, &vfs)
                .is_err()
        );
    }

    #[test]
    fn test_pre_resolve_packages_duplicate_and_vfs_typ() {
        let mut resolver = PackageResolver::new();
        let mut vfs = HashMap::new();
        vfs.insert(
            "sub.typ".to_string(),
            Bytes::new(b"#import \"@preview/cetz:0.3.4\": *".to_vec()),
        );
        // Duplicate imports in main source and VFS to hit queue dedup branch
        let res = resolver.pre_resolve_packages(
            r#"#import "@preview/cetz:0.3.4": *
               #import "@preview/cetz:0.3.4": *"#,
            &vfs,
        );
        assert!(res.is_ok());
    }

    #[test]
    fn test_unpack_package_archive_corrupted_entries() {
        use flate2::Compression;
        use flate2::write::GzEncoder;
        use std::io::Write;

        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "corrupt".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        // Valid gzip, invalid tar stream -> hits archive entry reading error branch
        let mut gz = GzEncoder::new(Vec::new(), Compression::default());
        gz.write_all(b"invalid tar header data that fails tar parsing")
            .unwrap();
        let gz_bytes = gz.finish().unwrap();
        assert!(PackageResolver::unpack_package_archive(&gz_bytes, &spec).is_err());
    }

    #[test]
    fn test_package_error_display_coverage() {
        let spec = PackageSpec {
            namespace: "preview".into(),
            name: "test".into(),
            version: typst::syntax::package::PackageVersion {
                major: 1,
                minor: 0,
                patch: 0,
            },
        };

        let errs: Vec<PackageError> = vec![
            PackageError::Lock("poisoned".into()),
            PackageError::Disabled(spec.clone()),
            PackageError::UnsupportedNamespace("local".into()),
            PackageError::ReadBody {
                spec: spec.clone(),
                source: std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "eof"),
            },
            PackageError::ReadArchive {
                spec: spec.clone(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, "invalid tar"),
            },
            PackageError::ReadEntry {
                spec: spec.clone(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, "bad entry"),
            },
            PackageError::InvalidPath {
                spec: spec.clone(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, "bad path"),
            },
            PackageError::ReadFile {
                path: "file.typ".into(),
                spec: spec.clone(),
                source: std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "eof"),
            },
        ];

        for err in errs {
            let msg = err.to_string();
            assert!(!msg.is_empty());
            let file_err: typst::diag::FileError = err.into();
            assert!(matches!(file_err, typst::diag::FileError::Other(_)));
        }
    }
}
