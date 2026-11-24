# Cross-platform contract tests

The iOS app (`AthleteBridge`) and the Android app (`AthleteBridgeAndroid`) share one Firestore database, and a
user on one routinely deals with someone on the other: an Android client books an iPhone coach, an iPhone stringer
fills an Android player's order. These tests check that each app correctly reads, and acts on, what the *other*
app's real code writes. This folder is identical in both repos.

## What runs

| Piece | Where | Checks |
|---|---|---|
| **Recorded stories** | `AndroidWritesTest` (Android), `IOSWritesTests` (iOS) | Each app runs nine stories (`contract.json` → `stories`) through its real code and records the Firestore documents after every step into `fixtures/<app>/<story>.json`. In normal runs the test fails if the app now writes something different from its recording: the other app hasn't been checked against the new shape yet. |
| **Reading the other app's data** | `ReadsIosFixturesTest` (Android), `ReadsAndroidFixturesTests` (iOS) | Loads the other app's recording at each step and runs this app's real screens' readers on it (booking lists, chat list, club page, events…), then acts on it (accept, confirm, reschedule, cancel, reply, join, sign up, update an order, save a profile) and checks every copy of the data updates. |
| **Self-checks** | `ReadsAndroidFixturesTest` (Android), `ReadsIOSFixturesTests` (iOS) | The same reader tests on the app's own recordings. If these fail, the test (or the app itself) is wrong, not the other app. |
| **Push routing** | both reader suites + `PushRoutingContractTest` / `CrossPlatformContractTests` | Every push either app queues goes through the Cloud Function's rules (only `cloudFunction.forwardedKeys` reach the phone) and must open the screen `pushRouting` agrees on, on both apps. |
| **Shared logic** | `SharedLogicParityTest` / `CrossPlatformContractTests` | Payment links, coach tier and tournament partner matching give the answers in `contract.json` → `vectors` on both apps. |
| **Cloud Function** | `check-cloud-function.js` | Runs the real `onPendingNotificationCreate` (stubbed Firebase, nothing deployed) and checks it forwards exactly the keys `contract.json` lists. |

## Running

```
cross-platform/check.sh            # check everything (both repos side by side; ~10 min)
cross-platform/check.sh --record   # re-record both apps' stories first
```

Each app's suite also runs on its own against the committed recordings:

- Android: `./gradlew :app:testDebugUnitTest --tests 'com.athletebridge.android.crossplatform.*'`
- iOS: `scripts/run-ios-unit-tests.sh -only-testing:AthleteBridgeTests/ReadsAndroidFixturesTests` (and the other classes above)

To re-record one app by hand: `./gradlew :app:testDebugUnitTest -PrecordCrossPlatform --tests '*AndroidWritesTest'`, or
`TEST_RUNNER_CROSS_PLATFORM_RECORD=1 scripts/run-ios-unit-tests.sh -only-testing:AthleteBridgeTests/IOSWritesTests`.
Then copy the new `fixtures/<app>` folder to the other repo (check.sh does this).

## When something fails

- **"Android/iOS now writes different data in the X story"**: you changed what the app writes. If that's intended, run
  `check.sh --record` so the other app is re-checked against the new shape, and commit both repos' fixtures.
- **"<App> reading <other app>'s X story"**: a real incompatibility; the message lists every field and screen
  that disagrees. Fix the app (usually: write both field casings, read with fallbacks).
- **Push failures**: a push type the other app doesn't route, or a key the Cloud Function doesn't forward.

## Fixture format

Plain JSON for strings, booleans, null, integers, maps and arrays, plus one-key tags for the Firestore types JSON
can't tell apart: `{"$double": 45.0}`, `{"$timestamp": "2031-03-12T17:00:00Z"}`, `{"$ref": "coaches/{{coach}}"}`,
`{"$geo": [lat, lng]}`, `{"$bytes": "..."}`. Integer vs double matters: each app's reader casts to one of them.

Ids are placeholders so recordings are stable and readable: `{{coach}}`, `{{client2}}` (the actors),
`{{booking}}`, `{{club}}`… (what the story created), `{{chat}}` (derived from the two uids, as both apps do),
`{{client-email}}`, `{{h:1a2b3c4d}}` (any other generated id, named by a hash of where it first appeared).
Times written while the story ran are `{{now:<step>}}`, so their order survives. Each checkpoint lists only the
documents that changed (`null` = deleted).

## Stories the apps can't fully record

Steps that iOS writes from inside a SwiftUI view, rather than `FirestoreManager`, can't run in unit tests:
accepting a 1:1 booking (`AcceptBookingView`) is missing from the iOS booking recording. Android has no
screen that creates group sessions; its group recording uses `BookingRepository.createGroupBooking`, and
Android's coach preferred-club list (`linkedPlaceIds`) is set directly in its booking setup.
