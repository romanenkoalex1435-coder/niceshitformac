// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DragShift",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DragShift", path: "Sources/DragShift")
    ]
)
