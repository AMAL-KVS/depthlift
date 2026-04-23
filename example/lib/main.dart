import 'package:flutter/material.dart';
import 'package:depthlift/depthlift.dart';

void main() {
  runApp(const DepthLiftExampleApp());
}

/// Full demo app showcasing all four DepthLift effects.
class DepthLiftExampleApp extends StatelessWidget {
  const DepthLiftExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DepthLift Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const DepthLiftDemoPage(),
    );
  }
}

/// Demonstrates all four [DepthEffect] modes with interactive controls.
class DepthLiftDemoPage extends StatefulWidget {
  const DepthLiftDemoPage({super.key});

  @override
  State<DepthLiftDemoPage> createState() => _DepthLiftDemoPageState();
}

class _DepthLiftDemoPageState extends State<DepthLiftDemoPage> {
  final DepthLiftController _controller = DepthLiftController();

  DepthEffect _currentEffect = DepthEffect.parallax;
  double _depthScale = 0.65;
  double _parallaxFactor = 0.45;
  double _focusDepth = 0.5;
  double _bokehIntensity = 0.5;

  @override
  void initState() {
    super.initState();
    _controller.stateStream.listen((state) {
      debugPrint('DepthLift state: $state');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DepthLiftOptions get _options => DepthLiftOptions(
        effect: _currentEffect,
        depthModel: DepthModel.depthAnythingV2,
        depthScale: _depthScale,
        parallaxFactor: _parallaxFactor,
        focusDepth: _focusDepth,
        bokehIntensity: _bokehIntensity,
        useGyroscope: true,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('DepthLift Demo'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play float animation',
            onPressed: () => _controller.play(),
          ),
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Pause animation',
            onPressed: () => _controller.pause(),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Export frame',
            onPressed: () async {
              final png = await _controller.exportFrame();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Exported ${png.length} bytes PNG'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 3D scene ───────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DepthLiftView(
                  image: const AssetImage('assets/sample.jpg'),
                  options: _options,
                  controller: _controller,
                  loadingWidget: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Computing depth map…',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  onError: (e) => debugPrint('DepthLift error: $e'),
                ),
              ),
            ),
          ),

          // ── Effect selector ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<DepthEffect>(
              segments: const [
                ButtonSegment(
                  value: DepthEffect.parallax,
                  label: Text('Parallax'),
                  icon: Icon(Icons.threed_rotation),
                ),
                ButtonSegment(
                  value: DepthEffect.bokeh,
                  label: Text('Bokeh'),
                  icon: Icon(Icons.blur_on),
                ),
                ButtonSegment(
                  value: DepthEffect.float,
                  label: Text('Float'),
                  icon: Icon(Icons.air),
                ),
                ButtonSegment(
                  value: DepthEffect.zoom,
                  label: Text('Zoom'),
                  icon: Icon(Icons.zoom_in),
                ),
              ],
              selected: {_currentEffect},
              onSelectionChanged: (selected) {
                setState(() => _currentEffect = selected.first);
                _controller.setEffect(_currentEffect);
              },
            ),
          ),
          const SizedBox(height: 8),

          // ── Sliders ────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSlider(
                  label: 'Depth Scale',
                  value: _depthScale,
                  onChanged: (v) => setState(() => _depthScale = v),
                ),
                _buildSlider(
                  label: 'Parallax Factor',
                  value: _parallaxFactor,
                  onChanged: (v) => setState(() => _parallaxFactor = v),
                ),
                _buildSlider(
                  label: 'Focus Depth',
                  value: _focusDepth,
                  onChanged: (v) => setState(() => _focusDepth = v),
                ),
                _buildSlider(
                  label: 'Bokeh Intensity',
                  value: _bokehIntensity,
                  onChanged: (v) => setState(() => _bokehIntensity = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            onChanged: (v) {
              onChanged(v);
              _controller.setOptions(_options);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
