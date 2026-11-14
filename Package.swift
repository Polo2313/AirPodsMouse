// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirPodsMouse",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique pure (testable) : moteur de pointage, gestes, clic automatique, rejeu d'enregistrements
        .target(name: "AirPodsMouseCore"),
        // Vérifications automatiques : swift run AirPodsMouseChecks
        .executableTarget(name: "AirPodsMouseChecks", dependencies: ["AirPodsMouseCore"]),
        // L'appli (SwiftUI + AppKit) ; assemblée en AirPodsMouse.app par scripts/build-app.sh
        .executableTarget(name: "AirPodsMouse", dependencies: ["AirPodsMouseCore"]),
    ],
    swiftLanguageModes: [.v5]
)
