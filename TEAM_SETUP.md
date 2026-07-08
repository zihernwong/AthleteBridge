# AthleteBridge iOS — Team Member Setup

How to get the iOS app running in Xcode on your own device.

## Requirements

- **macOS with Xcode 16.4 or newer** (the project's deployment target is iOS 18.5).
- **An iPhone running iOS 18.5+** with a USB cable (or same-network wireless debugging).
- A (free) Apple ID signed into Xcode: Xcode → Settings → Accounts → “+”.
- Repo access to `github.com/zihernwong/AthleteBridge`.

## 1. Clone the repo

```bash
git clone https://github.com/zihernwong/AthleteBridge.git
cd AthleteBridge
git checkout branch     # the active branch is literally named "branch"
```

## 2. Add the private files (sent to you separately — NOT in GitHub)

You will receive **`GoogleService-Info.plist`** from Hern via a private channel
(text/AirDrop/password manager — never commit it).

Place it at exactly:

```
AthleteBridge/AthleteBridge/GoogleService-Info.plist
```

(i.e. inside the inner `AthleteBridge/` source folder, next to `AthleteBridgeApp.swift`.)
The Xcode project uses filesystem-synchronized groups, so the file is picked up
automatically once it's on disk — no need to drag it into Xcode.

Without this file the app **crashes on launch** at `FirebaseApp.configure()`.

That's the only private file needed to build and run. (Other secrets —
`Certificates.p12`, `aps.cer`, `functions/athletebridge-sa.json`, `functions/.env` —
are for App Store distribution, push-certificate management, and Cloud Functions
deployment. You don't need them to run the app.)

## 3. Open and let Xcode resolve packages

```bash
open AthleteBridge.xcodeproj
```

First open, Xcode resolves the Swift Package dependencies automatically
(Firebase iOS SDK, Braintree, Cloudinary). This takes a few minutes.
If it stalls: File → Packages → Resolve Package Versions.

## 4. Set up signing for YOUR device

The project is configured with Automatic signing under Hern's team. To run on
your own device, in Xcode:

1. Select the **AthleteBridge** target → **Signing & Capabilities** tab.
2. Either
   - **(preferred)** accept the invite to Hern's Apple Developer team, then pick
     that team in the Team dropdown and leave everything else alone; or
   - pick your **Personal Team**, and change the Bundle Identifier to something
     unique to you, e.g. `yourname.AthleteBridge`. Personal (free) teams can't
     use the Push Notifications entitlement — if Xcode complains, delete the
     **Push Notifications** capability row (and the aps-environment entry it
     flags). Everything except push notifications will work; **don't commit**
     the bundle-ID/entitlements change.

## 5. Run on your device

1. Plug in your iPhone, unlock it, tap **Trust** on the prompt.
2. Pick your device in Xcode's scheme selector (next to the ▶︎ button) and Run.
3. First install only: on the phone, Settings → General → VPN & Device
   Management → trust your developer certificate, then launch again.
4. If your phone is on an iOS version older than 18.5, lower
   **Minimum Deployments** on the target's General tab to your iOS version
   (don't commit that change).

## 6. Sign in

Use a test account or register a new one in the app — Auth, Firestore, Storage
all point at the shared `athletebridge-63176` Firebase project via the plist
from step 2, so you'll see the same live data as Hern.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Crash immediately on launch | `GoogleService-Info.plist` missing or in the wrong folder (step 2) |
| "Failed to register bundle identifier" | Bundle ID already taken — change it (step 4, personal-team path) |
| "No profiles for …" / push entitlement error | Free account + push capability — remove the Push Notifications capability |
| Package resolution errors | File → Packages → Reset Package Caches, then Resolve |
| Device not listed | Unlock phone, re-trust the computer, enable Developer Mode (Settings → Privacy & Security) |

## Never commit

`GoogleService-Info.plist`, `Certificates.p12`, `aps.cer`, anything under
`functions/` (`athletebridge-sa.json`, `.env`). These are all gitignored —
keep it that way.
