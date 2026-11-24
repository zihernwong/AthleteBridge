#!/usr/bin/env bash
# Cross-platform contract check for the AthleteBridge iOS and Android apps (see README.md).
#
#   cross-platform/check.sh            check: each app still writes what it recorded, each app reads and acts
#                                      correctly on the other's recordings, and pushes survive the Cloud Function
#   cross-platform/check.sh --record   first re-record both apps' fixtures from their current code
#
# Run it from either repo; it expects the other next to it (override with IOS_REPO=... ANDROID_REPO=...).
# The shared files (contract.json, README.md, this script, check-cloud-function.js) are copied from the repo you
# run it in to the other one, and each app's fixtures are copied to the other. Needs JDK 17, Xcode and Node.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
if [ -d "$repo/AthleteBridge.xcodeproj" ]; then
  IOS_REPO="${IOS_REPO:-$repo}"
  ANDROID_REPO="${ANDROID_REPO:-$(dirname "$repo")/AthleteBridgeAndroid}"
else
  ANDROID_REPO="${ANDROID_REPO:-$repo}"
  IOS_REPO="${IOS_REPO:-$(dirname "$repo")/AthleteBridge}"
fi
for r in "$IOS_REPO/AthleteBridge.xcodeproj" "$ANDROID_REPO/gradlew"; do
  [ -e "$r" ] || { echo "Can't find $r — set IOS_REPO / ANDROID_REPO"; exit 2; }
done

record=0
[ "${1:-}" = "--record" ] && record=1
logs="$(mktemp -d)"
results=()
failed=0

step() { echo; echo "── $1"; }
pass() { results+=("PASS  $1"); }
fail() { results+=("FAIL  $1 (log: $2)"); failed=1; }

sync_shared() {
  local other
  if [ "$repo" = "$IOS_REPO" ]; then other="$ANDROID_REPO"; else other="$IOS_REPO"; fi
  mkdir -p "$other/cross-platform/fixtures"
  for f in contract.json README.md check.sh check-cloud-function.js; do
    [ -f "$here/$f" ] && cp "$here/$f" "$other/cross-platform/$f"
  done
}

sync_fixtures() {
  rm -rf "$IOS_REPO/cross-platform/fixtures/android" "$ANDROID_REPO/cross-platform/fixtures/ios"
  [ -d "$ANDROID_REPO/cross-platform/fixtures/android" ] && cp -R "$ANDROID_REPO/cross-platform/fixtures/android" "$IOS_REPO/cross-platform/fixtures/"
  [ -d "$IOS_REPO/cross-platform/fixtures/ios" ] && cp -R "$IOS_REPO/cross-platform/fixtures/ios" "$ANDROID_REPO/cross-platform/fixtures/"
}

android_tests() { # $1 = gradle --tests filter, $2.. = extra args
  local filter="$1"; shift
  (cd "$ANDROID_REPO" && ./gradlew :app:testDebugUnitTest --tests "$filter" "$@")
}

ios_tests() { # extra xcodebuild args
  (cd "$IOS_REPO" && scripts/run-ios-unit-tests.sh "$@")
}

sync_shared

if [ $record = 1 ]; then
  step "Recording Android's stories"
  if android_tests 'com.athletebridge.android.crossplatform.AndroidWritesTest' -PrecordCrossPlatform > "$logs/android-record.log" 2>&1; then
    pass "Android recorded"; else fail "Android recording" "$logs/android-record.log"; fi
  step "Recording iOS's stories"
  if TEST_RUNNER_CROSS_PLATFORM_RECORD=1 ios_tests -only-testing:AthleteBridgeTests/IOSWritesTests > "$logs/ios-record.log" 2>&1; then
    pass "iOS recorded"; else fail "iOS recording" "$logs/ios-record.log"; fi
fi

sync_fixtures

step "Android: its recordings, reading iOS's, push routing, shared logic"
if android_tests 'com.athletebridge.android.crossplatform.*' > "$logs/android.log" 2>&1; then
  pass "Android cross-platform tests"; else fail "Android cross-platform tests" "$logs/android.log"; fi

step "iOS: its recordings, reading Android's, push routing, shared logic"
if ios_tests -only-testing:AthleteBridgeTests/IOSWritesTests -only-testing:AthleteBridgeTests/ReadsAndroidFixturesTests \
     -only-testing:AthleteBridgeTests/ReadsIOSFixturesTests -only-testing:AthleteBridgeTests/CrossPlatformContractTests > "$logs/ios.log" 2>&1; then
  pass "iOS cross-platform tests"; else fail "iOS cross-platform tests" "$logs/ios.log"; fi

step "Cloud Function push forwarding"
functions="$IOS_REPO/AthleteBridge/functions"
compiled="$functions/lib/index.js"
# Check the current source, not just what was last built: compile src/ into a scratch folder
if (cd "$functions" && node_modules/.bin/tsc -p tsconfig.json --outDir "$logs/functions-lib") > "$logs/functions.log" 2>&1; then
  compiled="$logs/functions-lib/index.js"
fi
if node "$here/check-cloud-function.js" "$functions" "$compiled" >> "$logs/functions.log" 2>&1; then
  pass "Cloud Function forwards what contract.json says"; else fail "Cloud Function forwarding" "$logs/functions.log"; fi
grep -E "^(Cloud Function forwards|Keys the apps)" "$logs/functions.log" || true

echo
echo "── Summary"
printf '%s\n' "${results[@]}"
if [ $failed = 1 ]; then
  echo
  echo "Failing tests (each lists every incompatibility it found):"
  for xml in "$ANDROID_REPO"/app/build/test-results/testDebugUnitTest/TEST-com.athletebridge.android.crossplatform.*.xml; do
    [ -f "$xml" ] || continue
    python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
for tc in ET.parse(sys.argv[1]).getroot().iter('testcase'):
    if tc.find('failure') is not None or tc.find('error') is not None:
        print('  Android  ' + tc.get('classname').split('.')[-1] + ' :: ' + tc.get('name'))
PY
  done
  [ -f "$logs/ios.log" ] && grep -E "Test Case .*failed" "$logs/ios.log" | sed -E 's/.*\[AthleteBridgeTests\.([A-Za-z]+) ([A-Za-z]+)\].*/  iOS      \1 :: \2/' | sort -u
  echo
  echo "Details: Android $ANDROID_REPO/app/build/reports/tests/testDebugUnitTest/index.html"
  echo "         iOS     $logs/ios.log (search for 'error: -[')"
  echo "See cross-platform/README.md for what each kind of failure means."
fi
exit $failed
