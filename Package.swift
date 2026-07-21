// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RealTodo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RealTodo", targets: ["RealTodo"]),
        .executable(name: "real_todo", targets: ["RealTodoCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "RealTodo",
            dependencies: ["RealTodoKit"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "RealTodoCLI",
            dependencies: [
                "RealTodoKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CLI"
        ),
        .target(
            name: "RealTodoKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/RealTodoKit"
        ),
    ]
)
