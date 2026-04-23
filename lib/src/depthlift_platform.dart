import 'dart:typed_data';

import 'depthlift_options.dart';

/// Abstract platform interface for the DepthLift plugin.
///
/// Each target platform provides a concrete implementation that
/// communicates with native rendering infrastructure (OpenGL ES on
/// Android, Metal on iOS).
///
/// The default concrete implementation is [DepthLiftMethodChannel].
abstract class DepthLiftPlatform {
  /// Registers a Flutter external texture and returns its ID.
  ///
  /// [imageBytes] — raw RGBA pixel data of the source image.
  /// [width] / [height] — image dimensions in pixels.
  /// [options] — initial rendering configuration.
  Future<int> createTexture({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required DepthLiftOptions options,
  });

  /// Sends the depth map to the native side for mesh construction.
  ///
  /// [textureId] — the texture returned by [createTexture].
  /// [depthMap] — normalised 16-bit grayscale depth data.
  /// [width] / [height] — depth map dimensions (matches image).
  Future<void> setDepthMap(
    int textureId,
    Uint8List depthMap,
    int width,
    int height,
  );

  /// Updates the gyroscope / pointer tilt offset for the current frame.
  ///
  /// Called every frame when the float animation is active, or on
  /// each sensor / pointer event.
  Future<void> updateTilt(int textureId, double x, double y);

  /// Replaces the rendering options on the native side.
  Future<void> setOptions(int textureId, DepthLiftOptions options);

  /// Captures the current rendered frame as PNG bytes.
  Future<Uint8List> exportFrame(int textureId);

  /// Renders a loop video and returns MP4 bytes.
  Future<Uint8List> exportVideo(
    int textureId, {
    required int durationMs,
    required int fps,
  });

  /// Releases the Flutter external texture and all associated native
  /// resources (GL context, Metal buffers, etc.).
  ///
  /// **Must** be called in the widget's `dispose` — leaking an
  /// `ExternalTexture` is a hard error.
  Future<void> releaseTexture(int textureId);
}
