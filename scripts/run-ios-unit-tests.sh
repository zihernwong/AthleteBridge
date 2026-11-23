#!/usr/bin/env bash
# Runs the iOS unit tests (AthleteBridgeTests) against local Firebase Auth + Firestore emulators.
# Under XCTest the app points Firebase at the emulators (AppDelegate.useFirebaseEmulatorsWhenUnitTesting),
# so tests never read or write production data. The emulator enforces AthleteBridge/firestore.rules.
#
# Needs Node (npx) and Java 17+. firebase-tools 14+ requires Java 21, so this pins 13.35.1.
#
# Usage: scripts/run-ios-unit-tests.sh [extra xcodebuild args]
#   e.g. scripts/run-ios-unit-tests.sh -only-testing:AthleteBridgeTests/BookingFlowTests
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-AthleteBridge Unit Tests}"
# A dedicated simulator keeps the tests' sign-ins away from the simulator you use day to day.
if ! xcrun simctl list devices | grep -q "$SIM_NAME ("; then
  xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" >/dev/null
fi

npx -y firebase-tools@13.35.1 emulators:exec --config firebase.emulators.json --only auth,firestore \
  --project athletebridge-63176 \
  "xcodebuild test -project AthleteBridge.xcodeproj -scheme AthleteBridge \
     -destination 'platform=iOS Simulator,name=$SIM_NAME' -only-testing:AthleteBridgeTests \
     -parallel-testing-enabled NO $*"
