# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-04-23

### Added

- **DepthLiftView** — Main widget that renders any 2D image as a live 3D parallax scene.
- **DepthLiftController** — Programmatic control for playback, effect switching, and export.
- **DepthLiftOptions** — Immutable configuration with `copyWith`, `toMap`, equality, and `lowPowerMode`.
- **4 visual effects** — Parallax, Bokeh (depth-of-field), Float (Lissajous breathing), Zoom (Ken Burns).
- **Depth Anything v2 Small** on-device inference:
  - Android: TFLite via `tflite_flutter`, input `[1, 3, 518, 518]`.
  - iOS: Core ML via `.mlpackage`, same tensor layout.
- **Remote depth API fallback** — POST base64 image to configurable HTTPS endpoint.
- **Depth post-processing** — normalisation, 5×5 boundary median filter, bilinear upsampling.
- **3D mesh construction** — configurable 16–256 grid with foreground 1.5× Z amplification.
- **Real-time rendering**:
  - Android: OpenGL ES 3.0 surface → Flutter `ExternalTexture`.
  - iOS: Metal → `CVPixelBuffer` registered as `FlutterTexture`.
- **Gyroscope tilt** via `sensors_plus` with pointer fallback.
- **Bokeh shader** — 9-tap separable Gaussian blur driven by depth distance from focal plane.
- **Frame export** — `exportFrame()` returns PNG bytes.
- **Video export** — `exportVideo()` placeholder (single-frame for now).
- **Error handling** — `DepthLiftModelException`, `onError` callback, flat-image fallback.
- **Low-power mode** — halves mesh resolution and disables bokeh.
- **Unit tests** — options, enums, controller state stream, mesh vertex math.
- **Widget tests** — loading widget visibility, default construction.
- **Full documentation** — dartdoc on all public APIs, comprehensive README.

### Platform requirements

- Android: `minSdkVersion 24`
- iOS: deployment target `14.0`
- Dart SDK: `>=3.3.0 <4.0.0`
- Flutter SDK: `>=3.19.0`
