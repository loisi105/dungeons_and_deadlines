// Security rules tests. Run from firebase/rules-tests:  npm install && npm test
// (needs the Firebase CLI: npm install -g firebase-tools)
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, arrayUnion } from 'firebase/firestore';

let env;
const RAID = 'raid-1';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-dungeons',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `raids/${RAID}`), {
      name: 'Thesis', bossName: 'Dragon', ownerId: 'alice', status: 'active',
      memberIDs: ['alice', 'bob'], lockedMaxHP: 1000,
    });
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const attack = (memberId, damage = 150) => ({ memberId, kind: 'task', damage, localDay: '2026-11-19' });

test('non-members cannot read a raid', async () => {
  await assertFails(getDoc(doc(db('eve'), `raids/${RAID}`)));
  await assertSucceeds(getDoc(doc(db('bob'), `raids/${RAID}`)));
});

test('members can only attack as themselves', async () => {
  await assertSucceeds(setDoc(doc(db('bob'), `raids/${RAID}/attacks/a1`), attack('bob')));
  await assertFails(setDoc(doc(db('bob'), `raids/${RAID}/attacks/a2`), attack('alice')));
});

test('attacks are add-only', async () => {
  await assertSucceeds(setDoc(doc(db('bob'), `raids/${RAID}/attacks/a1`), attack('bob')));
  await assertFails(updateDoc(doc(db('bob'), `raids/${RAID}/attacks/a1`), { damage: 400 }));
  await assertFails(deleteDoc(doc(db('bob'), `raids/${RAID}/attacks/a1`)));
});

test('attack damage is bounded', async () => {
  await assertFails(setDoc(doc(db('bob'), `raids/${RAID}/attacks/big`), attack('bob', 5000)));
  await assertFails(setDoc(doc(db('bob'), `raids/${RAID}/attacks/zero`), attack('bob', 0)));
});

test('a 6th member cannot join', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `raids/${RAID}`), { memberIDs: ['alice', 'bob', 'c', 'd', 'e'] });
  });
  await assertFails(updateDoc(doc(db('frank'), `raids/${RAID}`), { memberIDs: arrayUnion('frank') }));
});

test('joining adds only yourself', async () => {
  await assertSucceeds(updateDoc(doc(db('carol'), `raids/${RAID}`), { memberIDs: arrayUnion('carol') }));
  await assertFails(updateDoc(doc(db('dave'), `raids/${RAID}`), { memberIDs: arrayUnion('dave', 'mallory') }));
});

test('only the leader edits the raid; members may only settle the outcome', async () => {
  await assertFails(updateDoc(doc(db('bob'), `raids/${RAID}`), { name: 'Hacked' }));
  await assertSucceeds(updateDoc(doc(db('alice'), `raids/${RAID}`), { name: 'Thesis v2' }));
  await assertSucceeds(updateDoc(doc(db('bob'), `raids/${RAID}`), { status: 'won' }));
});

test('no attacks after the fight ended', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `raids/${RAID}`), { status: 'won' });
  });
  await assertFails(setDoc(doc(db('bob'), `raids/${RAID}/attacks/late`), attack('bob')));
});

test('creating a raid: owner must be the only member', async () => {
  const raid = { name: 'R', bossName: 'B', ownerId: 'zoe', status: 'planning', memberIDs: ['zoe'] };
  await assertSucceeds(setDoc(doc(db('zoe'), 'raids/new'), raid));
  await assertFails(setDoc(doc(db('zoe'), 'raids/new2'), { ...raid, memberIDs: ['zoe', 'x'] }));
});
