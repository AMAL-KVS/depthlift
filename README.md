# DepthLift

[![pub package](https://img.shields.io/pub/v/depthlift.svg)](https://pub.dev/packages/depthlift)

Convert any 2D image into a live, interactive 3D parallax scene with on-device depth estimation. Inspired by iOS depth effects.

## ✨ Features

- **On-device depth estimation** — Depth Anything v2 Small (25 MB, fp16) via TFLite (Android) and Core ML (iOS)
- **Real-time GPU rendering** — OpenGL ES 3.0 on Android, Metal on iOS, targeting 60 fps
- **4 built-in effects** — Parallax, Bokeh, Float (breathing animation), Zoom
- **Gyroscope-driven parallax** — tilt your device to explore the scene
- **Frame & video export** — capture PNG stills or MP4 loops
- **Remote fallback** — optional HTTPS depth API for apps with size budgets
- **Low-power mode** — automatically reduces quality on constrained devices

## 🚀 Quick Start

### Installation

Add `depthlift` to your `pubspec.yaml`:

```yaml
dependencies:
  depthlift: ^0.1.0
```

Then run:

```bash
flutter pub get
```

### Basic Usage

```dart
import 'package:depthlift/depthlift.dart';

final ctrl = DepthLiftController();

DepthLiftView(
  image: const AssetImage('assets/photo.jpg'),
  options: const DepthLiftOptions(
    effect: DepthEffect.parallax,
    depthModel: DepthModel.depthAnythingV2,
    parallaxFactor: 0.45,
    depthScale: 0.65,
    useGyroscope: true,
  ),
  controller: ctrl,
  loadingWidget: const CircularProgressIndicator(),
  onError: (e) => debugPrint('DepthLift error: $e'),
);
```

### Controller

```dart
// Start the floating animation
await ctrl.play();

// Pause
await ctrl.pause();

// Switch effect on the fly
await ctrl.setEffect(DepthEffect.bokeh);

// Export a still frame
final Uint8List png = await ctrl.exportFrame();

// Export a looping video
final Uint8List mp4 = await ctrl.exportVideo(
  duration: const Duration(seconds: 3),
  fps: 30,
);

// Listen to state changes
ctrl.stateStream.listen((state) {
  // DepthLiftState.loading | .ready | .error
});

// Always dispose when done
ctrl.dispose();
```

## ⚙️ DepthLiftOptions

| Field | Type | Default | Description |
|---|---|---|---|
| `effect` | `DepthEffect` | `.parallax` | Active visual effect (parallax, bokeh, float, zoom) |
| `depthModel` | `DepthModel` | `.depthAnythingV2` | Depth estimation backend |
| `depthScale` | `double` | `0.6` | Z-axis displacement magnitude (0.0–1.0) |
| `parallaxFactor` | `double` | `0.4` | Gyro/pointer parallax multiplier (0.0–1.0) |
| `meshResolution` | `double` | `64` | Grid subdivisions per axis (16–256) |
| `focusDepth` | `double` | `0.5` | Bokeh focal plane depth (0.0–1.0) |
| `bokehIntensity` | `double` | `0.5` | Depth-of-field blur strength (0.0–1.0) |
| `floatDuration` | `Duration` | `3s` | One full cycle of the float animation |
| `remoteEndpoint` | `String?` | `null` | HTTPS URL for remote depth API |
| `useGyroscope` | `bool` | `true` | Whether to use device gyroscope |
| `lowPowerMode` | `bool` | `false` | Halves mesh resolution, disables bokeh |

## 🎭 Effects

### Parallax
Gyroscope or pointer-driven 3D parallax — foreground elements shift more than background.

### Bokeh
Simulated depth-of-field blur. Regions far from `focusDepth` receive increasing Gaussian blur.

### Float
Autonomous Lissajous-curve breathing animation — the scene gently drifts without user input.

### Zoom
Ken Burns-style slow push into the focal region.

## 📱 Platform Setup

### Android

**Minimum SDK:** 24 (Android 7.0)

In `android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

### iOS

**Deployment target:** 14.0

In `ios/Podfile`:

```ruby
platform :ios, '14.0'
```

## 🧠 Adding Model Assets

The Depth Anything v2 Small model must be included in your app's assets:

1. Download the model files and place them in your project:
   - Android: `assets/models/depth_anything_v2_small.tflite`
   - iOS: `assets/models/depth_anything_v2_small.mlpackage/`

2. Declare them in your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/
```

3. For iOS, also add the `.mlmodelc` compiled model to your Xcode project's bundle resources.

> **Tip:** If you don't want to bundle the model (saves ~25 MB), use `DepthModel.remote` with a `remoteEndpoint` URL instead.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter (Dart)                                     │
│  ┌───────────────┐  ┌─────────────────────────────┐ │
│  │ DepthLiftView │──│ DepthLiftController         │ │
│  └───────┬───────┘  │  • play / pause             │ │
│          │          │  • setEffect / setOptions    │ │
│          │          │  • exportFrame / exportVideo │ │
│          │          └─────────────────────────────┘ │
│          │                                          │
│  ┌───────▼──────────────────────────────────────┐   │
│  │ MethodChannel  (dev.depthlift/engine)        │   │
│  └───────┬──────────────────────────────────────┘   │
├──────────┼──────────────────────────────────────────┤
│  Native  │                                          │
│  ┌───────▼───────┐  ┌────────────────────────────┐  │
│  │ Plugin Entry  │──│ Depth Engine               │  │
│  │ (Kt / Swift)  │  │ TFLite (Android)           │  │
│  └───────┬───────┘  │ Core ML (iOS)              │  │
│          │          └────────────────────────────┘  │
│  ┌───────▼───────┐  ┌────────────────────────────┐  │
│  │ Renderer      │──│ DepthMesh                  │  │
│  │ GLES / Metal  │  │ vertex / UV / index buffers│  │
│  └───────────────┘  └────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run mesh math tests only
flutter test test/depth_mesh_test.dart
```

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
# depthlift
