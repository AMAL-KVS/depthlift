/// DepthLift — Convert any 2D image into a live 3D parallax scene.
///
/// This library provides on-device depth estimation powered by
/// Depth Anything v2 and real-time GPU rendering via OpenGL ES (Android)
/// and Metal (iOS).
///
/// ## Quick start
///
/// ```dart
/// import 'package:depthlift/depthlift.dart';
///
/// DepthLiftView(
///   image: const AssetImage('assets/photo.jpg'),
///   options: const DepthLiftOptions(
///     effect: DepthEffect.parallax,
///     parallaxFactor: 0.45,
///   ),
/// );
/// ```
library depthlift;

export 'src/depth_effect.dart';
export 'src/depth_model.dart';
export 'src/depthlift_controller.dart' show DepthLiftController, DepthLiftState;
export 'src/depthlift_method_channel.dart' show DepthLiftModelException;
export 'src/depthlift_options.dart';
export 'src/depthlift_view.dart';
