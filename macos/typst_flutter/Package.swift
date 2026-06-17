// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "typst_flutter",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "typst-flutter", targets: ["typst_flutter"])
    ],
    targets: [
        .target(
            name: "typst_flutter",
            path: "Sources/typst_flutter",
            publicHeadersPath: "."
        )
    ]
)
