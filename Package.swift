// swift-tools-version: 6.0
import PackageDescription

// WikiFS — native macOS SwiftUI wiki with a File Provider filesystem
// projection. Built with SwiftPM (no Xcode IDE, no xcodebuild); ./build.sh
// bundles the executable produced here into build/WikiFS.app and codesigns it.
let package = Package(
    name: "WikiFS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WikiFS",
            path: "Sources/WikiFS"
        ),
        // The File Provider extension binary. build.sh repackages this into a
        // .appex bundle under WikiFS.app/Contents/PlugIns and signs it.
        .executableTarget(
            name: "WikiFSFileProvider",
            path: "Sources/WikiFSFileProvider",
            linkerSettings: [
                .linkedFramework("FileProvider"),
                // Override the Mach-O entry point to _NSExtensionMain (the same
                // entry Xcode gives app extensions). ExtensionFoundation
                // re-invokes the entry point to run the principal class; that
                // entry MUST be NSExtensionMain itself. A Swift main() that
                // calls NSExtensionMain() instead recurses infinitely on
                // re-invocation and SIGSEGVs. See Sources/.../main.swift.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
    ]
)
