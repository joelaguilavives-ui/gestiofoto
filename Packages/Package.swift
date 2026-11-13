// swift-tools-version: 6.0
//
// Paquetes de GestioFoto. Un solo manifiesto con un target por carpeta
// (Domain, Persistence, Integrations). Reports llega en las fases 2–3.
//
// Dependencias (PDF §2): PostgresNIO. swift-nio-ssl y swift-log ya vienen con
// PostgresNIO; se declaran aquí solo para poder importarlos (TLS y logs).

import PackageDescription

let package = Package(
    name: "GestioFotoKit",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Integrations", targets: ["Integrations"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Domain",
            path: "Domain/Sources"
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            path: "Domain/Tests"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Persistence/Sources"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            path: "Persistence/Tests"
        ),
        .target(
            name: "Integrations",
            dependencies: ["Domain"],
            path: "Integrations/Sources"
        ),
        .testTarget(
            name: "IntegrationsTests",
            dependencies: ["Integrations"],
            path: "Integrations/Tests"
        ),
    ]
)
