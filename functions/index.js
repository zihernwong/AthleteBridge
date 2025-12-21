const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// When a new message is written under chats/{chatId}/messages/{messageId}, send FCM to recipients
exports.onNewChatMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const messageData = snap.data();
    const chatId = context.params.chatId;

    // Determine recipients: read the parent chat document's participantRefs or participants
    const chatRef = db.collection('chats').doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      console.log('Chat doc not found for chatId=', chatId); return null;
    }
    const chatData = chatSnap.data() || {};

    // Sender id
    let senderId = null;
    if (messageData.senderRef && messageData.senderRef.path) {
      senderId = messageData.senderRef.path.split('/').pop();
    } else if (messageData.senderId) {
      senderId = messageData.senderId;
    }

    // Collect recipient UIDs (participants excluding sender)
    let participantRefs = chatData.participantRefs || null;
    let participantUids = [];
    if (participantRefs && Array.isArray(participantRefs)) {
      participantUids = participantRefs.map(ref => {
        if (ref instanceof admin.firestore.DocumentReference) return ref.id;
        // if stored as path string
        if (typeof ref === 'string') return ref.split('/').pop();
        return null;
      }).filter(Boolean);
    } else if (chatData.participants && Array.isArray(chatData.participants)) {
      participantUids = chatData.participants.map(p => (typeof p === 'string') ? p.split('/').pop() : null).filter(Boolean);
    }

    participantUids = participantUids.filter(uid => uid !== senderId);
    if (participantUids.length === 0) {
      console.log('No recipients for message', chatId); return null;
    }

    // Prepare notification payload
    const text = messageData.text || '';
    const title = messageData.title || 'New message';

    // For each recipient, fetch their profile doc (clients/{uid} or coaches/{uid}) to get deviceTokens
    const tokens = [];
    for (const uid of participantUids) {
      // Try clients then coaches
      let doc = await db.collection('clients').doc(uid).get();
      if (!doc.exists) doc = await db.collection('coaches').doc(uid).get();
      if (!doc.exists) continue;
      const data = doc.data() || {};
      const deviceTokens = data.deviceTokens || [];
      if (Array.isArray(deviceTokens)) tokens.push(...deviceTokens);
    }

    if (tokens.length === 0) { console.log('No device tokens for recipients'); return null; }

    const payload = {
      notification: {
        title: title,
        body: text,
      },
      data: {
        chatId: chatId,
        messageId: snap.id
      }
    };

    try {
      const response = await admin.messaging().sendToDevice(tokens, payload);
      console.log('FCM send response', response);
    } catch (err) {
      console.error('Error sending FCM', err);
    }

    return null;
  });
