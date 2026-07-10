import ProjectDescription

let project = Project(
    name: "ShadeCam",
    targets: [
        .target(
            name: "ShadeCam",
            destinations: [.mac],
            product: .app,
            bundleId: "app.supabit.shadecam",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "NSCameraUsageDescription": "ShadeCam uses the camera to render your live shader preview.",
                "NSMainStoryboardFile": "",
            ]),
            sources: ["Sources/**"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.security.device.camera": true,
            ]),
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "SWIFT_VERSION": "6.0",
            ])
        ),
    ]
)
