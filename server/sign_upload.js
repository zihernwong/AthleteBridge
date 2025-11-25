// Simple Express server to create signed Cloudinary upload parameters
// Usage: set env vars CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET (and optionally CLOUDINARY_CLOUD_NAME)
// Run: node sign_upload.js

const express = require('express');
const crypto = require('crypto');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json());

const PORT = process.env.PORT || 4000;
const CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || '';
const API_KEY = process.env.CLOUDINARY_API_KEY || '';
const API_SECRET = process.env.CLOUDINARY_API_SECRET || '';

if (!API_KEY || !API_SECRET) {
  console.warn('Warning: CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET not set. Server will still start but signing will fail.');
}

// Helper to create Cloudinary signature from params object
function makeSignature(paramsToSign) {
  // Cloudinary expects parameters sorted lexicographically by key when signing
  const sortedKeys = Object.keys(paramsToSign).sort();
  const toSign = sortedKeys.map(k => `${k}=${paramsToSign[k]}`).join('&');
  const signature = crypto.createHash('sha1').update(toSign + API_SECRET).digest('hex');
  return signature;
}

// POST /sign
// body: { folder?: string }
// returns: { signature, timestamp, api_key, cloud_name }
app.post('/sign', (req, res) => {
  const timestamp = Math.floor(Date.now() / 1000);
  const folder = req.body.folder; // optional

  const params: any = { timestamp };
  if (folder) params.folder = folder;

  if (!API_SECRET || !API_KEY) {
    return res.status(500).json({ error: 'Server not configured with Cloudinary API credentials' });
  }

  const signature = makeSignature(params);
  res.json({ signature, timestamp, api_key: API_KEY, cloud_name: CLOUD_NAME });
});

app.get('/', (req, res) => {
  res.send('Cloudinary sign service is running. POST /sign with optional JSON { folder }');
});

app.listen(PORT, () => {
  console.log(`Cloudinary sign server listening on port ${PORT}`);
});
