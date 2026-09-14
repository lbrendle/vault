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
