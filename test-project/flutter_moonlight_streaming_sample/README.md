
# flutter_moonlight_streaming_sample

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
=======
# SimWheel Moonlight Bridge

Android streaming components that connect SimWheel to Sunshine using the Moonlight GameStream protocol.

This repository contains the Moonlight-based streaming integration used by SimWheel. It is intended to be integrated into the SimWheel Android app; it is not a standalone streaming app and does not include the Sunshine server.

## What’s included

- Moonlight Common C streaming core and its Android JNI support
- Android audio and video rendering interfaces used by the stream
- Kotlin/Java bridge code that connects the streaming core to the Android app
- Native build configuration required by the integration

## Requirements

- Android Studio with the Android SDK and NDK
- CMake
- Flutter SDK to build the SimWheel host app


## Upstream projects

- [Moonlight Android](https://github.com/moonlight-stream/moonlight-android)
- [Moonlight Common C](https://github.com/moonlight-stream/moonlight-common-c)

Moonlight-derived code is licensed under the GNU General Public License, version 3. See the included license and copyright notices for the applicable terms. Third-party dependencies bundled with the streaming core may use different licenses; retain and review their individual notices.

## Scope

This project covers the Android Moonlight streaming integration only. The rest of the SimWheel application is maintained separately.

