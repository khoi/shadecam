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
                "NSMicrophoneUsageDescription": "ShadeCam uses the microphone to drive audio-reactive shaders.",
            ]),
            sources: [
                "Sources/**",
                "Resources/Models/DepthAnythingV2SmallF16.mlpackage",
            ],
            resources: [
                .glob(pattern: "Resources/**", excluding: ["Resources/Models/**"]),
            ],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.security.device.audio-input": true,
                "com.apple.security.device.camera": true,
                "com.apple.security.files.user-selected.read-write": true,
            ]),
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "Apple Development",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "9ZLSJ2GN2B",
                "SWIFT_VERSION": "6.0",
            ])
        ),
        .target(
            name: "ShadeCamTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "app.supabit.shadecam.tests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            resources: ["Resources/Presets/**", "Resources/Shader/**"],
            dependencies: [.target(name: "ShadeCam")],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
            ])
        ),
    ]
)
