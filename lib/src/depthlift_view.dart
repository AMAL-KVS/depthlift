import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'depth_effect.dart';
import 'depthlift_controller.dart';
import 'depthlift_method_channel.dart';
import 'depthlift_options.dart';
import 'depthlift_platform.dart';

/// A widget that displays any 2D image as a live, interactive 3D parallax
/// scene using on-device depth estimation.
///
/// Provide an [ImageProvider] via the [image] parameter. The widget will:
/// 1. Decode the image to RGBA bytes.
/// 2. Run depth estimation (on-device or remote).
/// 3. Construct a displacement mesh on the GPU.
/// 4. Render the parallax scene at 60 fps via Flutter's Texture API.
///
/// ```dart
/// DepthLiftView(
///   image: const AssetImage('assets/photo.jpg'),
///   options: const DepthLiftOptions(
///     effect: DepthEffect.parallax,
///     parallaxFactor: 0.45,
///   ),
/// )
/// ```
class DepthLiftView extends StatefulWidget {
  /// The source image to render as a 3D parallax scene.
  final ImageProvider image;

  /// Rendering and effect configuration.
  final DepthLiftOptions options;

  /// Optional controller for programmatic playback and export.
  final DepthLiftController? controller;

  /// Widget displayed while the depth map is being computed.
  ///
  /// Defaults to an empty [SizedBox] if not specified.
  final Widget? loadingWidget;

  /// Called when an error occurs during depth estimation or rendering.
  ///
  /// The image will still be displayed flat (no depth) so the user
  /// never sees a broken state.
  final void Function(Object error)? onError;

  /// Creates a [DepthLiftView].
  const DepthLiftView({
    super.key,
    required this.image,
    this.options = const DepthLiftOptions(),
    this.controller,
    this.loadingWidget,
    this.onError,
  });

  @override
  State<DepthLiftView> createState() => _DepthLiftViewState();
}

class _DepthLiftViewState extends State<DepthLiftView>
    with TickerProviderStateMixin {
  /// Platform channel implementation.
  final DepthLiftPlatform _platform = DepthLiftMethodChannel();

  /// The controller — either user-supplied or internally created.
  late DepthLiftController _controller;

  /// Whether we own the controller (and must dispose it).
  bool _ownsController = false;

  /// Native texture ID, `null` until the texture is registered.
  int? _textureId;

  /// Gyroscope subscription.
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  /// Current tilt offset accumulated from the gyroscope.
  double _tiltX = 0.0;
  double _tiltY = 0.0;

  /// Decoded image dimensions.
  int _imageWidth = 0;
  int _imageHeight = 0;

  /// Whether we are still loading.
  bool _isLoading = true;

  /// Whether an error occurred.
  bool _hasError = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DepthLiftController();
    _ownsController = widget.controller == null;

    _controller.attach(
      platform: _platform,
      tickerProvider: this,
      options: widget.options,
    );

    _initPipeline();
  }

  @override
  void didUpdateWidget(covariant DepthLiftView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Image changed — rebuild the entire pipeline.
    if (widget.image != oldWidget.image) {
      _teardown().then((_) => _initPipeline());
      return;
    }

    // Options changed — push to native.
    if (widget.options != oldWidget.options) {
      _controller.setOptions(widget.options);
    }
  }

  @override
  void dispose() {
    _teardown();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  // ─── Pipeline ───────────────────────────────────────────────────────────

  Future<void> _initPipeline() async {
    _controller.emitState(DepthLiftState.loading);
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // 1. Decode image from the ImageProvider.
      final imageBytes = await _resolveImage(widget.image);
      if (!mounted) return;

      // 2. Create a native texture and upload the image.
      final textureId = await _platform.createTexture(
        imageBytes: imageBytes,
        width: _imageWidth,
        height: _imageHeight,
        options: widget.options,
      );
      if (!mounted) return;

      _textureId = textureId;
      _controller.textureId = textureId;

      // 3. Start gyroscope listening if enabled.
      if (widget.options.useGyroscope) {
        _startGyroscope();
      }

      _controller.emitState(DepthLiftState.ready);
      setState(() => _isLoading = false);

      // 4. Auto-play float if effect is float.
      if (widget.options.effect == DepthEffect.float) {
        await _controller.play();
      }
    } catch (e) {
      _hasError = true;
      _controller.emitState(DepthLiftState.error);
      widget.onError?.call(e);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _teardown() async {
    _gyroSubscription?.cancel();
    _gyroSubscription = null;

    if (_textureId != null) {
      await _platform.releaseTexture(_textureId!);
      _textureId = null;
      _controller.textureId = null;
    }
  }

  // ─── Image decoding ────────────────────────────────────────────────────

  Future<Uint8List> _resolveImage(ImageProvider provider) async {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stackTrace) {
        completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    final image = await completer.future;

    // Resize to max 1024px on the long edge.
    final int maxDim = 1024;
    int w = image.width;
    int h = image.height;

    if (w > maxDim || h > maxDim) {
      final scale = maxDim / (w > h ? w : h);
      w = (w * scale).round();
      h = (h * scale).round();
    }

    _imageWidth = w;
    _imageHeight = h;

    // Encode to raw RGBA bytes.
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const DepthLiftModelException(
        'Failed to decode image to RGBA bytes.',
      );
    }

    return byteData.buffer.asUint8List();
  }

  // ─── Gyroscope ──────────────────────────────────────────────────────────

  void _startGyroscope() {
    _gyroSubscription?.cancel();
    _gyroSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        if (_textureId == null) return;

        // Accumulate gyroscope deltas, clamped to [-1, 1].
        _tiltX = (_tiltX + event.y * 0.01).clamp(-1.0, 1.0);
        _tiltY = (_tiltY + event.x * 0.01).clamp(-1.0, 1.0);

        // Only send tilt when the controller isn't auto-animating.
        if (!_controller.isPlaying) {
          _platform.updateTilt(_textureId!, _tiltX, _tiltY);
        }
      },
      onError: (_) {
        // Gyroscope unavailable — fall back to pointer-only input.
      },
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingWidget ??
          const SizedBox.shrink();
    }

    if (_textureId == null || _hasError) {
      // Fallback: show the original image flat.
      return Image(image: widget.image, fit: BoxFit.cover);
    }

    return Texture(textureId: _textureId!);
  }
}

