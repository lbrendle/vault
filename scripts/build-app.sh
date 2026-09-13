#!/bin/bash
set -euo pipefail
VAULT_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$VAULT_PROJECT"
if [ "${VAULT_SKIP_WEB_BUILD:-0}" != 1 ]; then npm ci --prefix web; npm run build --prefix web; fi
xcodegen generate --spec native/project.yml
mkdir -p native/ArchiiVault.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp native/Package.resolved native/ArchiiVault.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
VAULT_DERIVED="${VAULT_DERIVED_DATA:-$VAULT_PROJECT/.build/native}"
xcodebuild -project native/ArchiiVault.xcodeproj -scheme ArchiiVaultMac \
 -configuration Release -destination 'platform=macOS,arch=arm64' \
 -derivedDataPath "$VAULT_DERIVED" -jobs "${VAULT_BUILD_JOBS:-2}" \
 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
VAULT_APP="${VAULT_APP_OUTPUT:-$VAULT_PROJECT/dist/Archii Vault.app}"
mkdir -p "$(dirname "$VAULT_APP")"
# ditto updates in place; stage a fresh bundle so stale resources cannot survive.
VAULT_STAGE="$(mktemp -d "$(dirname "$VAULT_APP")/.vault-build.XXXXXX")"
trap 'rm -rf "$VAULT_STAGE"' EXIT
ditto "$VAULT_DERIVED/Build/Products/Release/Archii Vault.app" "$VAULT_STAGE/Archii Vault.app"
if [ -n "${VAULT_BUNDLE_ID:-}" ]; then
 /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $VAULT_BUNDLE_ID" "$VAULT_STAGE/Archii Vault.app/Contents/Info.plist"
fi
codesign --force --deep --options runtime --timestamp --sign "${VAULT_SIGNING_IDENTITY:--}" "$VAULT_STAGE/Archii Vault.app"
if [ -e "$VAULT_APP" ]; then mv "$VAULT_APP" "$VAULT_STAGE/previous.app"; fi
mv "$VAULT_STAGE/Archii Vault.app" "$VAULT_APP"
printf '%s\n' "$VAULT_APP"
