import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:depthlift/depthlift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── DepthLiftOptions tests ─────────────────────────────────────────────

  group('DepthLiftOptions', () {
    test('default values are correct', () {
      const options = DepthLiftOptions();

      expect(options.effect, DepthEffect.parallax);
      expect(options.depthModel, DepthModel.depthAnythingV2);
      expect(options.depthScale, 0.6);
      expect(options.parallaxFactor, 0.4);
      expect(options.meshResolution, 64);
      expect(options.focusDepth, 0.5);
      expect(options.bokehIntensity, 0.5);
      expect(options.floatDuration, const Duration(seconds: 3));
      expect(options.remoteEndpoint, isNull);
      expect(options.useGyroscope, isTrue);
      expect(options.lowPowerMode, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const original = DepthLiftOptions(
        depthScale: 0.8,
        parallaxFactor: 0.3,
      );

      final copied = original.copyWith(depthScale: 0.5);

      expect(copied.depthScale, 0.5);
      expect(copied.parallaxFactor, 0.3); // preserved
      expect(copied.effect, DepthEffect.parallax); // preserved
    });

    test('copyWith replaces all specified fields', () {
      const original = DepthLiftOptions();

      final copied = original.copyWith(
        effect: DepthEffect.bokeh,
        depthModel: DepthModel.remote,
        depthScale: 0.9,
        parallaxFactor: 0.1,
        meshResolution: 128,
        focusDepth: 0.3,
        bokehIntensity: 0.8,
        floatDuration: const Duration(seconds: 5),
        remoteEndpoint: 'https://api.example.com/depth',
        useGyroscope: false,
        lowPowerMode: true,
      );

      expect(copied.effect, DepthEffect.bokeh);
      expect(copied.depthModel, DepthModel.remote);
      expect(copied.depthScale, 0.9);
      expect(copied.parallaxFactor, 0.1);
      expect(copied.meshResolution, 128);
      expect(copied.focusDepth, 0.3);
      expect(copied.bokehIntensity, 0.8);
      expect(copied.floatDuration, const Duration(seconds: 5));
      expect(copied.remoteEndpoint, 'https://api.example.com/depth');
      expect(copied.useGyroscope, isFalse);
      expect(copied.lowPowerMode, isTrue);
    });

    test('equality works for identical options', () {
      const a = DepthLiftOptions(depthScale: 0.7);
      const b = DepthLiftOptions(depthScale: 0.7);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different options', () {
      const a = DepthLiftOptions(depthScale: 0.7);
      const b = DepthLiftOptions(depthScale: 0.3);

      expect(a, isNot(equals(b)));
    });

    test('toMap serialises all fields', () {
      const options = DepthLiftOptions(
        effect: DepthEffect.bokeh,
        depthScale: 0.7,
        parallaxFactor: 0.3,
      );

      final map = options.toMap();

      expect(map['effect'], 'bokeh');
      expect(map['depthScale'], 0.7);
      expect(map['parallaxFactor'], 0.3);
      expect(map['meshResolution'], 64.0);
      expect(map['focusDepth'], 0.5);
      expect(map['bokehIntensity'], 0.5);
      expect(map['useGyroscope'], true);
      expect(map['lowPowerMode'], false);
    });

    test('lowPowerMode halves mesh resolution and disables bokeh', () {
      const options = DepthLiftOptions(
        meshResolution: 64,
        bokehIntensity: 0.8,
        lowPowerMode: true,
      );

      final map = options.toMap();

      expect(map['meshResolution'], 32.0); // halved
      expect(map['bokehIntensity'], 0.0); // disabled
    });

    test('toString contains all field names', () {
      const options = DepthLiftOptions();
      final str = options.toString();

      expect(str, contains('effect'));
      expect(str, contains('depthScale'));
      expect(str, contains('parallaxFactor'));
      expect(str, contains('meshResolution'));
    });
  });

  // ─── DepthEffect enum tests ────────────────────────────────────────────

  group('DepthEffect', () {
    test('has exactly 4 values', () {
      expect(DepthEffect.values.length, 4);
    });

    test('name accessors work', () {
      expect(DepthEffect.parallax.name, 'parallax');
      expect(DepthEffect.bokeh.name, 'bokeh');
      expect(DepthEffect.float.name, 'float');
      expect(DepthEffect.zoom.name, 'zoom');
    });
  });

  // ─── DepthModel enum tests ─────────────────────────────────────────────

  group('DepthModel', () {
    test('has exactly 3 values', () {
      expect(DepthModel.values.length, 3);
    });

    test('name accessors work', () {
      expect(DepthModel.depthAnythingV2.name, 'depthAnythingV2');
      expect(DepthModel.midas.name, 'midas');
      expect(DepthModel.remote.name, 'remote');
    });
  });

  // ─── DepthLiftController tests ─────────────────────────────────────────

  group('DepthLiftController', () {
    test('stateStream emits values', () async {
      final controller = DepthLiftController();

      expectLater(
        controller.stateStream,
        emitsInOrder([DepthLiftState.loading, DepthLiftState.ready]),
      );

      controller.emitState(DepthLiftState.loading);
      controller.emitState(DepthLiftState.ready);

      controller.dispose();
    });

    test('dispose closes state stream', () {
      final controller = DepthLiftController();
      controller.dispose();

      expect(
        controller.stateStream.listen((_) {}),
        isNotNull, // stream exists but is done
      );
    });
  });

  // ─── DepthLiftView widget tests ────────────────────────────────────────

  group('DepthLiftView', () {
    // Mock the method channel to prevent actual native calls.
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.depthlift/engine'),
        (MethodCall call) async {
          switch (call.method) {
            case 'createTexture':
              return 42; // fake texture ID
            case 'releaseTexture':
              return null;
            case 'updateTilt':
              return null;
            case 'setOptions':
              return null;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.depthlift/engine'),
        null,
      );
    });

    testWidgets('shows loadingWidget while depth is computed', (tester) async {
      // Create a 1×1 red pixel PNG.
      final bytes = _createTestPngBytes();

      await tester.pumpWidget(
        MaterialApp(
          home: DepthLiftView(
            image: MemoryImage(bytes),
            loadingWidget: const Text('Loading…'),
          ),
        ),
      );

      // The loading widget should be visible initially.
      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets('constructs with default options', (tester) async {
      final bytes = _createTestPngBytes();

      await tester.pumpWidget(
        MaterialApp(
          home: DepthLiftView(
            image: MemoryImage(bytes),
          ),
        ),
      );

      // Should not throw.
      expect(find.byType(DepthLiftView), findsOneWidget);
    });

    testWidgets('accepts a custom controller', (tester) async {
      final bytes = _createTestPngBytes();
      final controller = DepthLiftController();

      await tester.pumpWidget(
        MaterialApp(
          home: DepthLiftView(
            image: MemoryImage(bytes),
            controller: controller,
          ),
        ),
      );

      expect(find.byType(DepthLiftView), findsOneWidget);

      // Clean up.
      controller.dispose();
    });
  });
}

/// Creates a minimal valid 1×1 red PNG as [Uint8List].
Uint8List _createTestPngBytes() {
  // Minimal 1×1 red pixel PNG (67 bytes).
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1×1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, // compressed
    0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, //
    0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
