# Medly — Smart Emergency Healthcare Assistant

Medly is a mobile-first emergency healthcare app prototype built with Flutter.

Getting started

1. Install Flutter SDK: https://flutter.dev/docs/get-started/install
2. Create the project locally (recommended):

```bash
flutter create medly
cd medly
```

Or use this repo skeleton as a starting point.

Add recommended packages to `pubspec.yaml`:

- firebase_core
- firebase_auth
- cloud_firestore
- firebase_messaging
- google_maps_flutter
- geolocator
- flutter_local_notifications
- http
- speech_to_text
- flutter_tts
- intl

Firebase setup

- Create a Firebase project and register Android and iOS apps.
- Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) and place them in the platform folders.
- Follow FlutterFire docs to initialize Firebase in `main()`.

Run (Android emulator or attached device):

```bash
flutter pub get
flutter run
```

Next steps

- Configure Firestore schema and authentication
- Implement Smart SOS and AI assistant integrations
