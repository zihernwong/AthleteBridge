# Cloudinary Signed Upload Helper (Dev)

This small Express server generates signatures for Cloudinary uploads. Use it only during development or from a trusted backend — do NOT embed your API secret in client apps.

Setup

1. Install dependencies:

```bash
cd server
npm install express body-parser
```

2. Set environment variables (replace with values from your Cloudinary dashboard):

```bash
export CLOUDINARY_API_KEY=your_api_key
export CLOUDINARY_API_SECRET=your_api_secret
export CLOUDINARY_CLOUD_NAME=your_cloud_name
```

3. Run the server:

```bash
node sign_upload.js
```

4. Usage (client):
- POST `/sign` with optional JSON body `{ "folder": "profileImages" }` to receive:
  - signature, timestamp, api_key, cloud_name
- The client includes these values when performing a Cloudinary upload (signed flow).

Security note: do not expose your API secret. Use this server only as a trusted backend.
