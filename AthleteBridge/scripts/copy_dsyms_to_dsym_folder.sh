#!/bin/bash
# Copy embedded frameworks' dSYM bundles into the archive's DWARF dSYM folder so exported archives include third-party dSYMs
# Intended to be run as an Xcode Run Script build phase during Archive (not required for normal builds).
# Usage (Run Script Phase):
#   /bin/bash "${PROJECT_DIR}/scripts/copy_dsyms_to_dsym_folder.sh"

set -euo pipefail
IFS=$'\n\t'

echo "[copy_dsyms] Running copy_dsyms_to_dsym_folder.sh"

# Destination: Xcode sets DWARF_DSYM_FOLDER_PATH during archive
DSYM_DEST="${DWARF_DSYM_FOLDER_PATH:-}" 
if [ -z "$DSYM_DEST" ]; then
  echo "[copy_dsyms] DWARF_DSYM_FOLDER_PATH is not set. Are you running this from an Xcode Archive build phase?"
  exit 0
fi
mkdir -p "$DSYM_DEST"

# Common locations to search for dSYMs
#  - companion .dSYM next to built framework
#  - Packages / CocoaPods / Carthage build folders
SEARCH_PATHS=(
  "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}" 
  "${BUILT_PRODUCTS_DIR}" 
  "${PROJECT_DIR}" 
  "${PROJECT_DIR}/Pods" 
  "${PROJECT_DIR}/Carthage" 
  "${PROJECT_DIR}/SourcePackages" 
  "${HOME}/Library/Developer/Xcode/DerivedData" 
)

echo "[copy_dsyms] Destination dSYM folder: $DSYM_DEST"

copied=0

# Helper to copy a dSYM if present
copy_if_exists() {
  local src="$1"
  if [ -d "$src" ]; then
    echo "[copy_dsyms] Copying dSYM: $src"
    cp -R "$src" "$DSYM_DEST/" || true
    copied=$((copied+1))
  fi
}

# For each framework in the final frameworks folder, look for matching .dSYM candidates
if [ -d "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}" ]; then
  for fw in "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"/*.framework; do
    [ -e "$fw" ] || continue
    name=$(basename "$fw" .framework)
    # common companion locations
    copy_if_exists "${TARGET_BUILD_DIR}/${name}.framework.dSYM"
    copy_if_exists "${BUILT_PRODUCTS_DIR}/${name}.framework.dSYM"
    copy_if_exists "${fw}.dSYM"
    # Check SPM checkout paths (best-effort)
    # Search for folders named <Name>.framework.dSYM under SourcePackages
    if [ -d "${PROJECT_DIR}/SourcePackages" ]; then
      find "${PROJECT_DIR}/SourcePackages" -type d -name "${name}.framework.dSYM" -maxdepth 6 -print0 2>/dev/null | while IFS= read -r -d $'\0' d; do
        copy_if_exists "$d"
      done
    fi
  done
fi

# Additionally, search the pre-defined search paths for any .dSYM matching known 3rd-party libs
for p in "${SEARCH_PATHS[@]}"; do
  if [ -d "$p" ]; then
    # find dSYMs but limit depth to avoid walking entire system
    find "$p" -type d -name "*.dSYM" -maxdepth 6 -print0 2>/dev/null | while IFS= read -r -d $'\0' ds; do
      # Heuristic: copy dSYMs that look like the frameworks reported (Firebase, Google, grpc, absl, openssl)
      case "$ds" in
        *Firebase*|*Google*|*grpc*|*absl*|*openssl*|*GoogleAppMeasurement*|*GoogleAdsOnDeviceConversion*|*FirebaseAnalytics*|*Firestore* )
          copy_if_exists "$ds"
          ;;
        *) ;;
      esac
    done
  fi
done

# Final: if we copied nothing, print guidance and exit gracefully
if [ "$copied" -eq 0 ]; then
  echo "[copy_dsyms] No dSYMs were automatically found/copyied. This can happen if frameworks were prebuilt without dSYMs or are remote (XCFrameworks without dSYM bundles)."
  echo "[copy_dsyms] If you have provider dSYMs (from Vendors) or from DerivedData, you can place them in the project's scripts/dSYMs/ folder and rerun."
else
  echo "[copy_dsyms] Copied $copied dSYM(s) into $DSYM_DEST"
fi

# Create a zip of the dSYMs for manual upload if desired
ZIP_OUTPUT_DIR="${DWARF_DSYM_FOLDER_PATH%/*}"
ZIPNAME="dSYMs-$(date +%Y%m%d%H%M%S).zip"
ZIPPATH="$ZIP_OUTPUT_DIR/$ZIPNAME"

# zip only if there are dSYMs
if [ -n "$(ls -A "$DSYM_DEST" 2>/dev/null)" ]; then
  (cd "$DSYM_DEST" && /usr/bin/zip -r "$ZIPPATH" .) >/dev/null 2>&1 || true
  echo "[copy_dsyms] Created dSYM zip: $ZIPPATH"
  echo "[copy_dsyms] You can upload this zip to App Store Connect (via Xcode Organizer -> Upload dSYMs or via Transporter app)."
fi

echo "[copy_dsyms] Done."
exit 0
