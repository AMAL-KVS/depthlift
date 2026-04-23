import 'package:flutter/services.dart';

import 'depthlift_options.dart';
import 'depthlift_platform.dart';

/// Exception thrown when a required ML model asset is missing.
class DepthLiftModelException implements Exception {
  /// Human-readable description of the problem.
  final String message;

  /// Creates a [DepthLiftModelException].
  const DepthLiftModelException(this.message);

  @override
  String toString() => 'DepthLiftModelException: $message';
}

/// Concrete [DepthLiftPlatform] implementation backed by a
/// [MethodChannel].
///
/// All method names are mirrored exactly in the native Kotlin and Swift
/// plugin classes so that the channel contract stays consistent.
class DepthLiftMethodChannel extends DepthLiftPlatform {
  /// The method channel used to interact with the native platform.
  static const MethodChannel _channel = MethodChannel('dev.depthlift/engine');

  @override
  Future<int> createTexture({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required DepthLiftOptions options,
  }) async {
    try {
      final result = await _channel.invokeMethod<int>(
        'createTexture',
        <String, dynamic>{
          'imageBytes': imageBytes,
          'width': width,
          'height': height,
          ...options.toMap(),
        },
      );
      if (result == null) {
        throw const DepthLiftModelException(
          'Native createTexture returned null — the texture could not be '
          'registered. Check logcat / Xcode console for details.',
        );
      }
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'MODEL_NOT_FOUND') {
        throw DepthLiftModelException(
          'Depth model asset not found. Make sure you have added the model '
          'file to your pubspec.yaml under flutter > assets:\n'
          '  flutter:\n'
          '    assets:\n'
          '      - packages/depthlift/assets/models/\n\n'
          'Platform message: ${e.message}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> setDepthMap(
    int textureId,
    Uint8List depthMap,
    int width,
    int height,
  ) async {
    try {
      await _channel.invokeMethod<void>(
        'setDepthMap',
        <String, dynamic>{
          'textureId': textureId,
          'depthMap': depthMap,
          'width': width,
          'height': height,
        },
      );
    } on PlatformException catch (e) {
      throw DepthLiftModelException(
        'Failed to upload depth map: ${e.message}',
      );
    }
  }

  @override
  Future<void> updateTilt(int textureId, double x, double y) async {
    try {
      await _channel.invokeMethod<void>(
        'updateTilt',
        <String, dynamic>{
          'textureId': textureId,
          'x': x,
          'y': y,
        },
      );
    } on PlatformException {
      // Tilt updates are best-effort — dropping a frame is acceptable.
    }
  }

  @override
  Future<void> setOptions(int textureId, DepthLiftOptions options) async {
    try {
      await _channel.invokeMethod<void>(
        'setOptions',
        <String, dynamic>{
          'textureId': textureId,
          ...options.toMap(),
        },
      );
    } on PlatformException catch (e) {
      throw DepthLiftModelException(
        'Failed to update options: ${e.message}',
      );
    }
  }

  @override
  Future<Uint8List> exportFrame(int textureId) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'exportFrame',
        <String, dynamic>{'textureId': textureId},
      );
      return result ?? Uint8List(0);
    } on PlatformException catch (e) {
      throw DepthLiftModelException(
        'Failed to export frame: ${e.message}',
      );
    }
  }

  @override
  Future<Uint8List> exportVideo(
    int textureId, {
    required int durationMs,
    required int fps,
  }) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'exportVideo',
        <String, dynamic>{
          'textureId': textureId,
          'durationMs': durationMs,
          'fps': fps,
        },
      );
      return result ?? Uint8List(0);
    } on PlatformException catch (e) {
      throw DepthLiftModelException(
        'Failed to export video: ${e.message}',
      );
    }
  }

  @override
  Future<void> releaseTexture(int textureId) async {
    try {
      await _channel.invokeMethod<void>(
        'releaseTexture',
        <String, dynamic>{'textureId': textureId},
      );
    } on PlatformException {
      // Release is best-effort during teardown.
    }
  }
}
