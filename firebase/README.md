# Firebase

Backend for multiplayer raids (M6). The app works solo without any of this.

The app does **not** use the Firebase iOS SDK (it added ~1.4 s to every launch).
It calls Firebase Auth and Firestore over REST: `Packages/DDKit/Sources/DDSync` (tested against an in-memory fake Firestore in `Tests/DDSyncTests`), used by `DungeonsAndDeadlines/Sync/SyncEngine.swift`.
`GoogleService-Info.plist` is only read for `API_KEY` and `PROJECT_ID`.

## Set up a Firebase project
1. Create a project in the Firebase console and add an iOS app with bundle ID `com.dungeonsanddeadlines.app`.
2. Enable **Authentication → Anonymous** and **Firestore**.
3. Download `GoogleService-Info.plist` into `DungeonsAndDeadlines/Resources/` (it's git-ignored).
4. Deploy the rules: `firebase deploy --only firestore:rules` from this folder.

## Run locally with the emulator
```bash
npm install -g firebase-tools
firebase emulators:start --project demo-dungeons
```
Run the app with the launch argument `-useFirebaseEmulator`. Without a `GoogleService-Info.plist` it uses the demo project `demo-dungeons`.

## Rules tests
```bash
cd rules-tests && npm install && npm test
```

## How the app syncs

- **Sign-in:** anonymous Firebase Auth after launch (never before the first frame). The user ID and refresh token are kept in the Keychain.
- **Upload:** the local outbox, debounced after each change. Attacks are create-only (`currentDocument.exists = false`); a retry of one that already landed counts as done. Writes the rules reject (`PERMISSION_DENIED`) are dropped, everything else is retried.
- **Download:** while the app is in the foreground, the current raid is polled every 5 s. It reads the raid document plus only the members, tasks and attacks changed since the last poll (server timestamps `updatedAt` / `serverCreatedAt`), so a quiet poll costs about 4 reads.
- **Leaving** deletes your member document. You stay in `memberIDs`, because the rules don't allow removing yourself there.
