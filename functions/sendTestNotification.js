// sendTestNotification.js
// Usage:
//   node sendTestNotification.js <FCM_TOKEN> [--serviceAccount ./path/to/serviceAccount.json]
// If a serviceAccount path is provided (or a file named ./serviceAccountKey.json exists in this folder),
// the script will initialize the Admin SDK with that credential; otherwise it uses Application Default Credentials.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error('Usage: node sendTestNotification.js <FCM_TOKEN> [--serviceAccount ./serviceAccount.json]');
    process.exit(2);
  }

  const token = args[0];
  let saPath = null;
  for (let i = 1; i < args.length; i++) {
    if (args[i] === '--serviceAccount' && args[i+1]) { saPath = args[i+1]; i++; }
  }

  // If a service account file is present in functions/, prefer it
  const fallbackPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!saPath && fs.existsSync(fallbackPath)) saPath = fallbackPath;

  if (saPath) {
    console.log('Initializing admin SDK with service account:', saPath);
    const sa = require(saPath);
    admin.initializeApp({ credential: admin.credential.cert(sa) });
  } else {
    console.log('Initializing admin SDK with default credentials (ADC). Make sure GOOGLE_APPLICATION_CREDENTIALS is set or you are running in a GCP environment).');
    admin.initializeApp();
  }

  // Build a Message object compatible with admin.messaging().send()
  const message = {
    token: token,
    notification: {
      title: 'Test Notification',
      body: 'This is a test push sent from sendTestNotification.js'
    },
    apns: {
      headers: {
        'apns-priority': '10'
      },
      payload: {
        aps: {
          alert: {
            title: 'Test Notification',
            body: 'This is a test push sent from sendTestNotification.js'
          },
          sound: 'default',
          badge: 1
        }
      }
    },
    data: {
      test: '1',
      timestamp: String(Date.now())
    }
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('send() response messageId:', response);
  } catch (err) {
    console.error('send() error:', err);
    if (err && err.code) console.error('error code:', err.code);
  }
}

main();
