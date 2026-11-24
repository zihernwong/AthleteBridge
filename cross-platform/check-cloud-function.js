#!/usr/bin/env node
// Checks the push hop between the two apps: onPendingNotificationCreate (functions/src/index.ts) turns each
// pendingNotifications/{uid}/notifications doc into an FCM push, copying only some keys into its data. Both apps'
// push tests assume contract.json "cloudFunction.forwardedKeys" is exactly that list, so this runs the real compiled
// function (lib/index.js) with Firebase stubbed out, hands it a notification carrying every key either app puts in
// a push, and compares what reaches FCM with the contract. Nothing touches a real project.
//
// Usage: node cross-platform/check-cloud-function.js <path to AthleteBridge/functions> [compiled index.js]
// (check.sh compiles src/ into a temporary folder and passes that index.js, so lib/ is left as deployed.)
'use strict'
const fs = require('fs')
const path = require('path')
const Module = require('module')

const here = __dirname
const functionsDir = path.resolve(process.argv[2] || path.join(here, '..', 'AthleteBridge', 'functions'))
const compiled = path.resolve(process.argv[3] || path.join(functionsDir, 'lib', 'index.js'))
const contract = JSON.parse(fs.readFileSync(path.join(here, 'contract.json'), 'utf8'))

// Every key either app writes into a push, from both apps' recordings, plus the contract's own.
const candidates = new Set([...contract.cloudFunction.forwardedKeys])
for (const route of contract.pushRouting.routes) Object.keys(route.data).forEach(k => candidates.add(k))
for (const writer of ['android', 'ios']) {
  const dir = path.join(here, 'fixtures', writer)
  if (!fs.existsSync(dir)) continue
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
    const fixture = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'))
    for (const cp of fixture.checkpoints) {
      for (const [docPath, doc] of Object.entries(cp.changed)) {
        if (doc && docPath.startsWith('pendingNotifications/') && docPath.split('/').length === 4) {
          for (const [k, v] of Object.entries(doc)) if (typeof v === 'string') candidates.add(k)
        }
      }
    }
  }
}

// ── Stubs: firebase-functions captures the handlers, firebase-admin records what would be sent ──
const handlers = {}
function chain(docPath) {
  return new Proxy(function () {}, {
    get(_, prop) {
      if (prop === 'document') return p => chain(p)
      if (['onCreate', 'onWrite', 'onUpdate', 'onDelete', 'onRun', 'onRequest', 'onCall'].includes(prop)) {
        return handler => { handlers[`${String(prop)}:${docPath}`] = handler; return handler }
      }
      return chain(docPath)
    },
    apply() { return chain(docPath) },
  })
}
const store = {}
const sent = []
function docRef(p) {
  return {
    path: p, id: p.split('/').pop(),
    get: async () => ({ exists: p in store, id: p.split('/').pop(), data: () => store[p] }),
    set: async d => { store[p] = d },
    update: async d => { store[p] = { ...(store[p] || {}), ...d } },
    collection: c => collectionRef(`${p}/${c}`),
  }
}
function collectionRef(p) {
  return {
    doc: id => docRef(`${p}/${id || 'auto'}`),
    add: async d => { const r = docRef(`${p}/auto`); await r.set(d); return r },
    where: () => collectionRef(p),
    get: async () => ({ docs: [], size: 0, empty: true }),
  }
}
const firestore = () => ({ collection: collectionRef, doc: docRef, settings: () => {} })
firestore.FieldValue = { serverTimestamp: () => 'SERVER_TIME', arrayRemove: (...a) => a, arrayUnion: (...a) => a, delete: () => 'DELETE', increment: n => n }
firestore.Timestamp = { fromDate: d => d, now: () => new Date() }
const admin = {
  initializeApp: () => {},
  firestore,
  messaging: () => ({ send: async message => { sent.push(message); return 'message-id' } }),
  auth: () => chain(''),
  credential: chain(''),
}
const originalLoad = Module._load
Module._load = function (request, parent, isMain) {
  if (request === 'firebase-admin') return admin
  if (request === 'firebase-functions') return chain('')
  return originalLoad.call(this, request, parent, isMain)
}

async function main() {
  const log = console.log
  console.log = () => {} // the function's own logging
  require(compiled)
  const handler = handlers['onCreate:pendingNotifications/{recipient}/notifications/{notifId}']
  if (!handler) throw new Error(`onPendingNotificationCreate not found in ${compiled}`)

  store['clients/recipient-1'] = { deviceTokens: ['token-1'] }
  const notification = { title: 'Title', body: 'Body', delivered: false }
  for (const key of candidates) if (!(key in notification)) notification[key] = `value-of-${key}`
  await handler({ data: () => notification, ref: { update: async () => {} } }, { params: { recipient: 'recipient-1', notifId: 'n1' } })
  console.log = log
  if (sent.length !== 1) throw new Error(`expected one FCM send, got ${sent.length}`)

  const received = Object.keys(sent[0].data || {})
  const added = new Set(contract.cloudFunction.addedKeys)
  const forwarded = received.filter(k => !added.has(k)).sort()
  const declared = [...contract.cloudFunction.forwardedKeys].sort()
  const dropped = [...candidates].filter(k => !received.includes(k) && !['title', 'body'].includes(k)).sort()

  console.log(`Cloud Function forwards: ${forwarded.join(', ')} (+ ${[...added].join(', ')})`)
  console.log(`Keys the apps put in pushes that never reach the phone: ${dropped.join(', ') || 'none'}`)
  const problems = []
  for (const k of forwarded) if (!declared.includes(k)) problems.push(`forwards "${k}", which contract.json doesn't list`)
  for (const k of declared) if (!forwarded.includes(k)) problems.push(`contract.json says "${k}" is forwarded, but the function drops it`)
  for (const k of added) if (!received.includes(k)) problems.push(`contract.json says the function adds "${k}", but it doesn't`)
  if (problems.length) {
    console.error('Cloud Function and contract disagree:\n  ' + problems.join('\n  '))
    process.exit(1)
  }
  console.log('Cloud Function matches contract.json')
}

main().catch(err => { console.error(err.stack || String(err)); process.exit(1) })
