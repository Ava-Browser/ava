// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ava",
    // Matches the fork's CMAKE_OSX_DEPLOYMENT_TARGET, so linking its dylib is warning-free.
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "LadybirdEngine", targets: ["LadybirdEngine"]),
        .library(name: "LadybirdUI", targets: ["LadybirdUI"]),
    ],
    targets: [
        // Target 0: the C ABI itself. No Swift, no logic — a module map and header search path.
        .target(
            name: "CLadybirdPort",
            path: "Sources/CLadybirdPort"
        ),

        // Target 1: thin Swift wrappers over the C ABI. Owns trampolines and Unmanaged<>.
        // No AppKit, no SwiftUI — enforced by what it is allowed to import.
        .target(
            name: "LadybirdBridge",
            dependencies: ["CLadybirdPort"],
            path: "Sources/LadybirdBridge"
        ),

        // Target 2: the only target that may touch AppKit/CoreFoundation. Owns the pump and the
        // surface-to-CALayer policy.
        //
        // unsafeFlags is deliberate: this is an application, never consumed as a dependency, and
        // the shim's location is fixed by the fork's build directory. A shipping build replaces
        // both the -L and the rpath with a bundled dylib (Documentation/Architecture.md, gaps).
        .target(
            name: "LadybirdEngine",
            dependencies: ["LadybirdBridge"],
            path: "Sources/LadybirdEngine",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Extern/ladybird/Build/release/lib",
                    "-llagom-port",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "Extern/ladybird/Build/release/lib",
                ]),
            ]
        ),

        // Target 3: SwiftUI chrome. Knows Engine's model, never the C ABI.
        .target(
            name: "LadybirdUI",
            dependencies: ["LadybirdEngine", "LadybirdBridge"],
            path: "Sources/LadybirdUI"
        ),

        // The app itself. Deliberately thin: see Documentation/Architecture.md.
        .executableTarget(
            name: "Ava",
            dependencies: ["LadybirdEngine", "LadybirdUI"],
            path: "Sources/LadybirdMac"
        ),

        .testTarget(name: "LadybirdBridgeTests", dependencies: ["LadybirdBridge"]),
        .testTarget(name: "LadybirdIntegrationTests", dependencies: ["LadybirdEngine", "LadybirdUI"]),
    ]
)
