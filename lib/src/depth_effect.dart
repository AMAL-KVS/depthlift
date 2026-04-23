/// Visual effects available for the DepthLift 3D scene.
///
/// Each effect changes how the depth-displaced mesh is rendered and
/// animated in the viewport.
enum DepthEffect {
  /// Gyroscope / pointer-driven parallax — the default experience.
  ///
  /// Foreground elements shift more than background elements to
  /// produce a convincing 3D look.
  parallax,

  /// Simulated depth-of-field (bokeh) blur.
  ///
  /// Regions far from [DepthLiftOptions.focusDepth] receive an
  /// increasing Gaussian blur, mimicking a shallow-DOF lens.
  bokeh,

  /// Gentle autonomous floating / breathing animation.
  ///
  /// A Lissajous-curve drift is applied to the tilt offset so the
  /// scene slowly moves without user input.
  float,

  /// Ken Burns-style slow zoom into the focal region.
  ///
  /// The camera gradually pushes in on the area around
  /// [DepthLiftOptions.focusDepth], creating cinematic movement.
  zoom,
}
