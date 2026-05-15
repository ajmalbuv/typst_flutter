# Release Process for typst_flutter

This document outlines the steps to publish a new version of the `typst_flutter` package. The process is almost fully automated by the CI/CD pipeline in `.github/workflows/release.yml`.

## Automated Release

The release is triggered by pushing a new tag to the `main` branch that follows the pattern `v*.*.*` (e.g., `v0.1.0`, `v1.2.3`).

### 1. Update Version Numbers

Before tagging, ensure the version number in `pubspec.yaml` is updated to the new version.

```yaml
# pubspec.yaml
version: 0.1.0 # <-- Update this
```

### 2. Create and Push a Git Tag

Once the `main` branch is ready for release and the version is bumped:

```bash
# Example for version 0.1.0
git tag v0.1.0
git push origin v0.1.0
```

### 3. CI Pipeline Execution

Pushing the tag will automatically trigger the `release.yml` workflow on GitHub Actions. This workflow will:

1.  **Run 8 parallel build jobs:** It cross-compiles the Rust `typst_flutter` library for all supported platforms and architectures (Linux x64/arm64, macOS universal, Windows x64, Android ABIs, iOS xcframework).

2.  **Create a GitHub Release:** A new draft release will be created on GitHub, titled after the tag (e.g., "Release v0.1.0").

3.  **Attach Binaries:** The compiled library from each build job is compressed (`.tar.gz` or `.zip`) and attached to the GitHub Release as a binary artifact.

4.  **Generate Checksums:** A `SHA256SUMS.txt` file is generated containing the checksums for all binary artifacts. This file is also attached to the release.

5.  **Publish to pub.dev:** After all artifacts are successfully uploaded, the workflow publishes the Dart package (which only contains source code) to pub.dev using trusted OIDC authentication.

### 4. Finalize the Release

The GitHub Release is created as a draft. You will need to manually review it, add release notes describing the changes, and then publish it.

## Manual Fallback (If CI Fails)

If any part of the CI pipeline fails, you may need to perform some steps manually.

1.  **Build Binaries Locally:** Use the cross-compilation tools (e.g., `cross`) to build the artifacts for each target. The specific targets are listed in `GEMINI.md`.
2.  **Manually Create GitHub Release:** Go to the "Releases" page in the GitHub repository and create a new release from the tag.
3.  **Upload Artifacts:** Manually upload the compiled binaries and the checksum file.
4.  **Publish to pub.dev:** Run `dart pub publish` from the root of the repository. You will need to have `pub.dev` credentials configured locally.

**Note:** The automated process is strongly preferred to ensure consistency and avoid errors. The manual process is a last resort.
