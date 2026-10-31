// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lattice",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lattice", targets: ["Lattice"]),
    ],
    targets: [
        .target(
            name: "LatticeKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-suppress-warnings"]),
            ]
        ),
        .executableTarget(
            name: "Lattice",
            dependencies: ["LatticeKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-suppress-warnings"]),
            ]
        ),
        .testTarget(
            name: "LatticeKitTests",
            dependencies: ["LatticeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
