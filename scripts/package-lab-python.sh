#!/bin/bash
set -euo pipefail
support="$PROJECT_DIR/PythonSupport"
if [[ "$EFFECTIVE_PLATFORM_NAME" == '-iphonesimulator' ]]; then lab_slice=simulator; else lab_slice=device; fi
mkdir -p "$CODESIGNING_FOLDER_PATH/lab-packages" "$CODESIGNING_FOLDER_PATH/lab-python"
rsync -a --delete "$support/shared/" "$CODESIGNING_FOLDER_PATH/lab-packages/"
rsync -a "$support/$lab_slice/" "$CODESIGNING_FOLDER_PATH/lab-packages/"
rsync -a --delete "$PROJECT_DIR/../Sources/VaultApp/Resources/lab-python/" "$CODESIGNING_FOLDER_PATH/lab-python/"
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad Hoc}"
source "$support/Python.xcframework/build/utils.sh"
install_python PythonSupport/Python.xcframework lab-packages

# Wheels also include static libraries for compiling extensions on a desktop.
# They are not used by the signed iOS extensions and are invalid app resources.
find "$CODESIGNING_FOLDER_PATH/lab-packages" "$CODESIGNING_FOLDER_PATH/python" -type f -name '*.a' -delete

# The upstream extension template currently uses APPL. These bundles are
# frameworks; leaving APPL makes App Store tooling identify one as the main app.
for lab_framework in "$CODESIGNING_FOLDER_PATH"/Frameworks/*.framework; do
    lab_info="$lab_framework/Info.plist"
    if [[ -f "$lab_info" ]] && [[ "$(plutil -extract CFBundlePackageType raw "$lab_info")" == APPL ]]; then
        plutil -replace CFBundlePackageType -string FMWK "$lab_info"
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none \
            --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$lab_framework"
    fi
done
