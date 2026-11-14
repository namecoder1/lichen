// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lichen",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lichen",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Lichen",
            linkerSettings: [
                // nel bundle Sparkle.framework sta in Contents/Frameworks; in sviluppo accanto all'eseguibile
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        )
    ]
)
