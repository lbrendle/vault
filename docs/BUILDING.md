# Building Vault

## Tools

- Apple silicon Mac, macOS 14 or newer.
- Xcode **26.6 or newer**, including the Metal toolchain. Accept Xcode's first-run setup and install the iOS SDK for device builds.
- Node.js **22 or newer** and npm.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), for example `brew install xcodegen`.
- Python 3.12+ to prepare the embedded iOS Lab dependencies and run the build scripts. Mac Lab uses an installed Python environment; model inference uses native MLX independently of Python.

Dependencies are pinned in `web/package-lock.json`, `native/project.yml`, `native/Package.resolved`, and `native/lab-dependencies.lock.json`. The initial build downloads dependencies; later model inference is local.

```sh
npm ci --prefix web
npm run build --prefix web
python3 scripts/bootstrap-lab.py
xcodegen generate --spec native/project.yml
mkdir -p native/ArchiiVault.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp native/Package.resolved native/ArchiiVault.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
open native/ArchiiVault.xcodeproj
```

Choose **ArchiiVaultMac** for macOS or **ArchiiVault** for iOS/iPadOS. The generated project is not committed. The Swift package builds the document/sync core and CLI; the Xcode targets build apps with the native Metal runtime.

## Mac from the command line

```sh
bash scripts/build-app.sh
open 'dist/Vault.app'
```

This makes a local, ad-hoc-signed app. For Developer ID signing, set `VAULT_SIGNING_IDENTITY` to your own identity when running the script. `VAULT_APP_OUTPUT` and `VAULT_DERIVED_DATA` optionally change output and build-cache locations. A signed app is not automatically notarized. Distributors must submit their build to Apple's notarization service and staple the accepted ticket before claiming notarization.

## iPhone and iPad

For the public beta, see [TestFlight installation](INSTALL_IOS.md). The steps below are for building the source yourself.

Select the **ArchiiVault** target. In Signing & Capabilities, choose **your own team**, enable automatic signing, and use a bundle identifier registered to your team. Connect and trust your device, enable Developer Mode if prompted, select it as the run destination, and run the app.

The project defaults to unsigned builds; for CLI device builds pass `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates`. The increased-memory-limit entitlement depends on provisioning support. If your team does not support it, remove that capability in your own generated project; local model size remains constrained by the app's OS memory allowance. Never commit a provisioning profile or signing key.

```sh
xcodebuild -project native/ArchiiVault.xcodeproj -scheme ArchiiVault \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/ios -jobs 2 CODE_SIGNING_ALLOWED=NO build
```

Use the app's starter-model installer after launching, or import a complete folder from Files. A source build does not include weights. [Model installation](../models/README.md) explains USB/AirDrop and the command-line downloader.

## Checks

```sh
npm test --prefix web
npm run build --prefix web
swift test -j 2
python3 -m unittest discover -s scripts/tests -v
```

Native smoke tests live in `native/Tests/LocalModelDeviceTests.swift`. They use fictional evidence and skip models that are not installed. Run the relevant Xcode test scheme on actual hardware after installing the desired model. They do not read the user's vault. GPU/model success cannot be inferred from a simulator compilation.

`VAULT_MODELS_DIR` optionally points the running Mac app or model tests at a separate model library; each model must be a real subfolder, not a symlink. Keep test fixtures out of source control. The public app coordinates only its own inference sessions and checks current OS memory; it does not inspect or control other applications.

## Release process

Review the full public tree, update version/build numbers, run tests and native builds, and scan the staged tree for secrets. Generate dependency notices whenever lockfiles change. Make a tag and publish checksums alongside assets. Never include private vault contents, development-signed mobile IPAs, local preferences, test device exports, or historical private source commits.

For a Mac Starter edition, copy the checksum-verified 2B folder into `Vault.app/Contents/Resources/Models/` **before signing and notarizing**. The app reads bundled models directly without creating a second weights copy. The larger starter remains available in Settings. Models keep their own LICENSE and NOTICE files.


## Lab dependencies

Before generating the iOS project, run `python3 scripts/bootstrap-lab.py` with Python 3.12 or newer. It verifies `native/lab-dependencies.lock.json` and prepares the ignored `native/PythonSupport` directory. The existing iPhone/iPad target packages and signs the embedded scientific libraries; the Mac target includes the worker and uses an installed Python environment. See [Lab setup](LAB.md). Native CI performs this preparation before building both existing targets.

The app remains **Vault**, with bundle identifier `com.archii.vault` on Mac and `com.archii.vault.ios` on iPhone/iPad. Lab is a setting in those existing app targets and uses the same repository and release process.
