# safeAI

Android app (Flutter) that checks links before they open. Registers as a browser, checks every link with Google Safe Browsing v5 plus on-device rules, then opens safe links in the real browser.

## Build

```
flutter pub get
cp secrets.example.json secrets.json   # put the Safe Browsing API key in it (git-ignored)
flutter test
flutter build appbundle --release --dart-define-from-file=secrets.json
```

Release signing reads `android/key.properties` (git-ignored; keystore lives outside the repo). Without it the release build falls back to the debug key.

- Application id: `id.safeai.app`
- Privacy policy: `docs/privacy/index.html` (GitHub Pages: https://zersya.github.io/safeai/privacy/)
- Store assets and listing text: `store/`
- Note: `hashes:search` v5 only answers in protobuf; decoded in `lib/checking/safe_browsing_proto.dart`.
