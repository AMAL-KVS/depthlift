import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'depth_effect.dart';
import 'depthlift_options.dart';
import 'depthlift_platform.dart';

/// Lifecycle states emitted by [DepthLiftController.stateStream].
enum DepthLiftState {
  /// The depth map is being computed or the texture is being set up.
  loading,

  /// The 3D scene is ready and rendering frames.
  ready,

  /// An unrecoverable error occurred. The image is displayed flat.
  error,
}

/// Controls the DepthLift 3D scene.
///
/// Create a [DepthLiftController] and pass it to [DepthLiftView.controller]
/// to programmatically start/stop animations, change effects, or export
/// rendered frames.
///
/// ```dart
/// final ctrl = DepthLiftController();
/// // later …
/// await ctrl.play();
/// final png = await ctrl.exportFrame();
/// ctrl.dispose();
/// ```
class DepthLiftController {
  final StreamController<DepthLiftState> _stateController =
      StreamController<DepthLiftState>.broadcast();

  /// The native texture ID allocated for this controller's view.
  ///
  /// Set internally by [DepthLiftView] after the platform channel returns
  /// the texture registration result.
  int? textureId;

  /// Internal reference to the platform implementation.
  DepthLiftPlatform? _platform;

  /// Current options. Updated via [setOptions].
  DepthLiftOptions _options = const DepthLiftOptions();

  /// Whether the float / breathing animation is running.
  bool _isPlaying = false;

  /// Animation controller used for the float / breathing effect.
  AnimationController? _animationController;

  /// The [TickerProvider] supplied by the host widget's state.
  TickerProvider? _tickerProvider;

  // ─── Public API ─────────────────────────────────────────────────────────

  /// A broadcast stream of [DepthLiftState] changes.
  ///
  /// Emits [DepthLiftState.loading] when depth inference begins,
  /// [DepthLiftState.ready] when the scene is fully rendered, or
  /// [DepthLiftState.error] on failure.
  Stream<DepthLiftState> get stateStream => _stateController.stream;

  /// Whether the float animation is currently active.
  bool get isPlaying => _isPlaying;

  // ─── Internal wiring ────────────────────────────────────────────────────

  /// Binds this controller to a [DepthLiftPlatform] and a [TickerProvider].
  ///
  /// Called by [DepthLiftView]'s state during [initState].
  void attach({
    required DepthLiftPlatform platform,
    required TickerProvider tickerProvider,
    required DepthLiftOptions options,
  }) {
    _platform = platform;
    _tickerProvider = tickerProvider;
    _options = options;
  }

  /// Emits a new [DepthLiftState].
  void emitState(DepthLiftState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  // ─── Playback ───────────────────────────────────────────────────────────

  /// Starts the floating / breathing Lissajous animation.
  ///
  /// Has no effect if the scene is not yet [DepthLiftState.ready].
  Future<void> play() async {
    if (_isPlaying) return;
    _isPlaying = true;

    _animationController?.dispose();
    _animationController = AnimationController(
      vsync: _tickerProvider!,
      duration: _options.floatDuration,
    )..repeat();

    _animationController!.addListener(_onFloatTick);
  }

  /// Pauses the floating animation, freezing the scene at its current tilt.
  Future<void> pause() async {
    _isPlaying = false;
    _animationController?.stop();
    _animationController?.removeListener(_onFloatTick);
  }

  void _onFloatTick() {
    if (_platform == null || textureId == null) return;

    final t = _animationController!.value;
    final durationSec =
        _options.floatDuration.inMilliseconds / 1000.0;

    // Lissajous-style drift for a natural feel.
    final double pi2 = 2.0 * 3.141592653589793;
    final offsetX =
        _sin(t * pi2 / durationSec) * 0.08;
    final offsetY =
        _sin(t * pi2 / durationSec * 0.7 + 3.141592653589793 / 4) * 0.05;

    _platform!.updateTilt(textureId!, offsetX, offsetY);
  }

  /// Fast sine approximation — avoids importing `dart:math` on the hot path.
  static double _sin(double x) {
    // Normalise to [-π, π].
    const double pi = 3.141592653589793;
    x = x % (2 * pi);
    if (x > pi) x -= 2 * pi;
    if (x < -pi) x += 2 * pi;
    // Bhaskara I approximation.
    final double abs = x < 0 ? -x : x;
    return (16 * x * (pi - abs)) /
        (5 * pi * pi - 4 * x * (pi - abs));
  }

  // ─── Effect / Option changes ────────────────────────────────────────────

  /// Switches the active [DepthEffect] without rebuilding the mesh.
  Future<void> setEffect(DepthEffect effect) async {
    _options = _options.copyWith(effect: effect);
    if (_platform != null && textureId != null) {
      await _platform!.setOptions(textureId!, _options);
    }
  }

  /// Replaces all rendering options. Triggers a mesh rebuild if the
  /// resolution changed.
  Future<void> setOptions(DepthLiftOptions options) async {
    _options = options;
    if (_platform != null && textureId != null) {
      await _platform!.setOptions(textureId!, options);
    }
  }

  // ─── Export ─────────────────────────────────────────────────────────────

  /// Captures the current rendered frame as a PNG image.
  ///
  /// Returns raw PNG bytes suitable for `Image.memory` or file I/O.
  Future<Uint8List> exportFrame() async {
    assert(_platform != null && textureId != null,
        'Controller is not attached to a DepthLiftView');
    return _platform!.exportFrame(textureId!);
  }

  /// Renders a looping video of the current effect.
  ///
  /// [duration] defaults to 3 seconds. [fps] defaults to 30.
  /// Returns raw MP4 bytes.
  Future<Uint8List> exportVideo({
    Duration duration = const Duration(seconds: 3),
    int fps = 30,
  }) async {
    assert(_platform != null && textureId != null,
        'Controller is not attached to a DepthLiftView');
    return _platform!.exportVideo(
      textureId!,
      durationMs: duration.inMilliseconds,
      fps: fps,
    );
  }

  // ─── Disposal ───────────────────────────────────────────────────────────

  /// Releases all resources held by this controller.
  ///
  /// Always call this when the controller is no longer needed. The
  /// [DepthLiftView] calls this automatically in its own `dispose`.
  void dispose() {
    _isPlaying = false;
    _animationController?.removeListener(_onFloatTick);
    _animationController?.dispose();
    _animationController = null;
    _stateController.close();
    _platform = null;
    _tickerProvider = null;
  }
}
