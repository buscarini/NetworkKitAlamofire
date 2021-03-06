// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkKitAlamofire",
	platforms: [
		.macOS(.v10_13), .iOS(.v10),
	],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "NetworkKitAlamofire",
            targets: ["NetworkKitAlamofire"]),
    ],
    dependencies: [
		.package(name: "NetworkKit", url: "https://github.com/buscarini/networkkit.git", from: "0.3.0"),
		.package(name: "Alamofire", url: "https://github.com/Alamofire/Alamofire.git", from: "5.4.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "NetworkKitAlamofire",
            dependencies: [
				"NetworkKit",
				"Alamofire" 
			]),
        .testTarget(
            name: "NetworkKitAlamofireTests",
            dependencies: [
				"NetworkKitAlamofire", 
				"NetworkKit", 
				"Alamofire" 
			]),
    ]
)
