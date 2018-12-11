// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkKitAlamofire",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "NetworkKitAlamofire",
            targets: ["NetworkKitAlamofire"]),
    ],
    dependencies: [
		.package(url: "https://github.com/buscarini/networkkit.git", from: "0.1.6"),
		.package(url: "https://github.com/Alamofire/Alamofire.git", from: "4.8.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "NetworkKitAlamofire",
            dependencies: [ "NetworkKit", "Alamofire" ]),
        .testTarget(
            name: "NetworkKitAlamofireTests",
            dependencies: ["NetworkKitAlamofire", "NetworkKit", "Alamofire" ]),
    ]
)