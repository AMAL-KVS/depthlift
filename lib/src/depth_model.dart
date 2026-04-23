/// Depth estimation backends supported by DepthLift.
///
/// The chosen model determines where and how the depth map is computed.
enum DepthModel {
  /// Depth Anything v2 Small (≈ 25 MB, fp16).
  ///
  /// Runs on-device:
  /// - Android — via TFLite (input `[1,3,518,518]`, output `[1,1,518,518]`).
  /// - iOS — via Core ML (`.mlpackage`).
  ///
  /// Best balance of quality and speed for mobile devices.
  depthAnythingV2,

  /// MiDaS v3.1 Small.
  ///
  /// An alternative on-device model with broader compatibility.
  /// Slightly less accurate than Depth Anything v2 but lighter.
  midas,

  /// Remote depth estimation via an HTTPS endpoint.
  ///
  /// The raw RGBA image is base64-encoded and POSTed to the URL
  /// specified in [DepthLiftOptions.remoteEndpoint]. The server
  /// returns a 16-bit grayscale depth map.
  ///
  /// Use this mode when the app's binary size budget cannot
  /// accommodate an on-device model.
  remote,
}
