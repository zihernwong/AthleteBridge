# Cloud Functions for AthleteBridge

This folder contains a Cloud Function that sends FCM push notifications when new chat messages are created.

Setup & deploy

1. Install Firebase CLI and log in:

```bash
npm install -g firebase-tools
firebase login
```

2. From this `functions/` folder, install dependencies:

```bash
cd functions
npm install
```

3. Ensure your Firebase project is selected (or run `firebase use --add` to choose a project).

4. Deploy functions:

```bash
firebase deploy --only functions
```

Notes

- The Cloud Function `onNewChatMessage` listens to `chats/{chatId}/messages/{messageId}` and will look up participant documents under `clients/{uid}` and `coaches/{uid}` for `deviceTokens` arrays.
- On iOS you must configure APNs with your Firebase project (APNs auth key or certificate) and include the correct entitlements in your app. See the Firebase docs for APNs setup.
- The function sends to all tokens found in recipients' `deviceTokens`. You must ensure `saveDeviceToken` is called from the app when the FCM token is refreshed.
