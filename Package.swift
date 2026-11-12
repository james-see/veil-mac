// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Veil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Veil", targets: ["Veil"]),
        .library(name: "VeilCore", targets: ["VeilCore"]),
    ],
    dependencies: [
        // Microsoft's official SPM distribution of ONNX Runtime (Obj-C/Swift bindings).
        // Needed because Rampart's q4 export uses the com.microsoft `MatMulNBits` contrib op.
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.20.0"),
    ],
    targets: [
        // Pure Swift, Foundation-only: heuristics, tokenizer, BIO decoding, twins, cloak/uncloak.
        .target(name: "VeilCore"),
        .executableTarget(
            name: "Veil",
            dependencies: [
                "VeilCore",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ]
        ),
        .testTarget(name: "VeilCoreTests", dependencies: ["VeilCore"]),
    ]
)
