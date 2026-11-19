# Firebase

Backend for multiplayer raids (M6). The app works solo without any of this.

The app does **not** use the Firebase iOS SDK (it added ~1.4 s to every launch).
It calls Firebase Auth and Firestore over REST (see `docs/handoff/drafts/M6/FirebaseREST.swift`).
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
