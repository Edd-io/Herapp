# Herapp

A Flutter client for Hermes: streaming conversations, agents, scheduled jobs, files,
Git on the server and the remote display. Requires a running Hermes dashboard/API;
`server/` contains the optional push watcher, not the Hermes backend.

## Run the web app

Use Flutter 3.41.2 (Dart 3.11) or a compatible version:

```sh
flutter pub get
flutter run -d chrome --dart-define=HERMES_URL=https://hermes.example.com
```

The server address can also be changed in Settings, along with the Hermes username
and password. Without `HERMES_URL`, the browser uses the app's origin as the server
address. Saved settings override this initial default. Native apps retain an empty
default server address unless `HERMES_URL` is provided.

## Deploy

```sh
flutter build web --release --dart-define=HERMES_URL=https://hermes.example.com
```

Serve the contents of `build/web/` over HTTPS. HTTPS is required for the browser's
encrypted password storage and microphone access; localhost also works for development.
The JavaScript web build is supported. The current text-to-speech plugin reports
additional compatibility warnings for WebAssembly builds.

Hosting Herapp on the same origin as Hermes avoids cross-origin cookie restrictions.
For example, keep Hermes at `https://hermes.example.com/` and serve Herapp under
`https://hermes.example.com/herapp/`:

```sh
flutter build web --release --base-href=/herapp/
```

Copy `build/web/` into the web server's `/herapp/` directory. Serve the static files
there and forward the existing `/api/`, `/auth/` and dashboard routes to Hermes.
The proxy must support WebSocket upgrades for `/api/ws` and `/api/display/ws`.
For a different installation path, set `--base-href` accordingly.

If hosting on a separate origin, configure the Hermes server or reverse proxy to:

- Allow the exact Herapp origin with CORS, including preflight requests, the HTTP
  methods in use, `Content-Type` and `X-Hermes-Session-Token`.
- Send `Access-Control-Allow-Credentials: true`; a wildcard origin is incompatible
  with credentialed requests.
- Issue cookies suitable for that deployment. Cross-site cookies require
  `SameSite=None; Secure` and may still be blocked by browser privacy settings.
- Accept the Herapp origin for the chat and display WebSockets. Use HTTPS/WSS
  throughout when the application is served over HTTPS.

Browser cookies, including HttpOnly sessions, are managed by the browser. The app
obtains one-use WebSocket tickets from Hermes after signing in. Loopback dashboard
token authentication is also supported.

## Platform differences

The web client supports the remote Hermes features, file attachments, image
downloads and the remote display. Speech input/output depends on browser support
and permissions. Preferences and encrypted credentials belong to the browser origin.

WireGuard inside the app, commands and Git on the user's computer, device biometric
locking, Apple integrations and background push notifications remain native-only.
Their settings are hidden in the browser. Use a system VPN if Hermes is on a private
network. Server-side Git and the in-app notifications history remain available.

## Checks

```sh
flutter analyze
flutter test
flutter build web --release
```

Browser integration tests use a loopback Hermes fixture. In one terminal:

```sh
dart run tool/web_test_server.dart
```

In another:

```sh
flutter test --platform chrome test/web_test.dart
```

They exercise real browser cookies and CORS, expired-session recovery, gateway
tickets, streamed events, binary display frames and the chat/settings UI. CI runs
these checks and uploads the compiled `web` artifact.
