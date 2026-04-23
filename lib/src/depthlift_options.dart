import 'package:flutter/foundation.dart';

import 'depth_effect.dart';
import 'depth_model.dart';

/// Immutable configuration for a [DepthLiftView].
///
/// All fields have sensible defaults so you can construct with
/// `const DepthLiftOptions()` and override only what you need.
///
/// ```dart
/// const options = DepthLiftOptions(
///   effect: DepthEffect.parallax,
///   depthScale: 0.65,
///   parallaxFactor: 0.45,
/// );
/// ```
@immutable
class DepthLiftOptions {
  /// The visual effect applied to the 3D scene.
  ///
  /// Defaults to [DepthEffect.parallax].
  final DepthEffect effect;

  /// Which depth estimation model to use.
  ///
  /// Defaults to [DepthModel.depthAnythingV2].
  final DepthModel depthModel;

  /// Controls the magnitude of Z-axis displacement.
  ///
  /// Range: 0.0–1.0. Default: 0.6.
  final double depthScale;

  /// Multiplier for gyroscope / pointer-driven parallax movement.
  ///
  /// Range: 0.0–1.0. Default: 0.4.
  final double parallaxFactor;

  /// Number of subdivisions along each axis for the displacement mesh.
  ///
  /// Higher values give smoother depth but cost more triangles.
  /// Range: 16–256. Default: 64.
  final double meshResolution;

  /// Depth value (0.0 = near, 1.0 = far) at which the bokeh focal plane
  /// is placed. Only relevant when [effect] is [DepthEffect.bokeh].
  ///
  /// Default: 0.5.
  final double focusDepth;

  /// Strength of the depth-of-field blur.
  ///
  /// Range: 0.0–1.0. Default: 0.5.
  final double bokehIntensity;

  /// Duration of one full cycle of the floating / breathing animation.
  ///
  /// Default: 3 seconds.
  final Duration floatDuration;

  /// HTTPS endpoint for the remote depth-estimation API.
  ///
  /// Only used when [depthModel] is [DepthModel.remote].
  final String? remoteEndpoint;

  /// Whether to read device gyroscope data for parallax tilt.
  ///
  /// Set to `false` to rely solely on pointer/touch input.
  /// Default: `true`.
  final bool useGyroscope;

  /// When `true`, mesh resolution is halved and bokeh is disabled to
  /// reduce GPU load on battery-constrained devices.
  ///
  /// Default: `false`.
  final bool lowPowerMode;

  /// Creates an immutable set of options for [DepthLiftView].
  ///
  /// Every parameter is optional and has a sensible default.
  const DepthLiftOptions({
    this.effect = DepthEffect.parallax,
    this.depthModel = DepthModel.depthAnythingV2,
    this.depthScale = 0.6,
    this.parallaxFactor = 0.4,
    this.meshResolution = 64,
    this.focusDepth = 0.5,
    this.bokehIntensity = 0.5,
    this.floatDuration = const Duration(seconds: 3),
    this.remoteEndpoint,
    this.useGyroscope = true,
    this.lowPowerMode = false,
  })  : assert(depthScale >= 0.0 && depthScale <= 1.0),
        assert(parallaxFactor >= 0.0 && parallaxFactor <= 1.0),
        assert(meshResolution >= 16 && meshResolution <= 256),
        assert(focusDepth >= 0.0 && focusDepth <= 1.0),
        assert(bokehIntensity >= 0.0 && bokehIntensity <= 1.0);

  /// Returns a copy of this [DepthLiftOptions] with the given fields
  /// replaced by new values.
  DepthLiftOptions copyWith({
    DepthEffect? effect,
    DepthModel? depthModel,
    double? depthScale,
    double? parallaxFactor,
    double? meshResolution,
    double? focusDepth,
    double? bokehIntensity,
    Duration? floatDuration,
    String? remoteEndpoint,
    bool? useGyroscope,
    bool? lowPowerMode,
  }) {
    return DepthLiftOptions(
      effect: effect ?? this.effect,
      depthModel: depthModel ?? this.depthModel,
      depthScale: depthScale ?? this.depthScale,
      parallaxFactor: parallaxFactor ?? this.parallaxFactor,
      meshResolution: meshResolution ?? this.meshResolution,
      focusDepth: focusDepth ?? this.focusDepth,
      bokehIntensity: bokehIntensity ?? this.bokehIntensity,
      floatDuration: floatDuration ?? this.floatDuration,
      remoteEndpoint: remoteEndpoint ?? this.remoteEndpoint,
      useGyroscope: useGyroscope ?? this.useGyroscope,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
    );
  }

  /// Serialises this options object to a map suitable for sending over
  /// a [MethodChannel].
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'effect': effect.name,
      'depthModel': depthModel.name,
      'depthScale': depthScale,
      'parallaxFactor': parallaxFactor,
      'meshResolution': lowPowerMode ? (meshResolution / 2).clamp(16, 256) : meshResolution,
      'focusDepth': focusDepth,
      'bokehIntensity': (lowPowerMode) ? 0.0 : bokehIntensity,
      'floatDurationMs': floatDuration.inMilliseconds,
      'remoteEndpoint': remoteEndpoint,
      'useGyroscope': useGyroscope,
      'lowPowerMode': lowPowerMode,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DepthLiftOptions &&
        other.effect == effect &&
        other.depthModel == depthModel &&
        other.depthScale == depthScale &&
        other.parallaxFactor == parallaxFactor &&
        other.meshResolution == meshResolution &&
        other.focusDepth == focusDepth &&
        other.bokehIntensity == bokehIntensity &&
        other.floatDuration == floatDuration &&
        other.remoteEndpoint == remoteEndpoint &&
        other.useGyroscope == useGyroscope &&
        other.lowPowerMode == lowPowerMode;
  }

  @override
  int get hashCode => Object.hash(
        effect,
        depthModel,
        depthScale,
        parallaxFactor,
        meshResolution,
        focusDepth,
        bokehIntensity,
        floatDuration,
        remoteEndpoint,
        useGyroscope,
        lowPowerMode,
      );

  @override
  String toString() =>
      'DepthLiftOptions(effect: $effect, depthModel: $depthModel, '
      'depthScale: $depthScale, parallaxFactor: $parallaxFactor, '
      'meshResolution: $meshResolution, focusDepth: $focusDepth, '
      'bokehIntensity: $bokehIntensity, floatDuration: $floatDuration, '
      'remoteEndpoint: $remoteEndpoint, useGyroscope: $useGyroscope, '
      'lowPowerMode: $lowPowerMode)';
}
