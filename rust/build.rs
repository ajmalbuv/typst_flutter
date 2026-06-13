fn main() {
    // Capture the version of the `typst` dependency from Cargo.toml
    let toml_content = std::fs::read_to_string("Cargo.toml").expect("Failed to read Cargo.toml");
    let typst_version = toml_content
        .lines()
        .find(|line| line.trim().starts_with("typst ="))
        .and_then(|line| line.split('"').nth(1))
        .expect("Could not find typst version in Cargo.toml");

    println!("cargo:rustc-env=TYPST_VERSION={}", typst_version);
}
