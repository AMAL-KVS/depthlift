import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

/// Pure-Dart mirror of the native mesh generation logic, used for
/// verifying vertex counts, UV correctness, and depth normalisation math
/// without requiring a platform channel.

void main() {
  group('Mesh vertex count', () {
    test('resolution 16 produces (16+1)² = 289 vertices', () {
      final mesh = _TestMesh(resolution: 16);
      expect(mesh.vertexCount, 289);
    });

    test('resolution 64 produces (64+1)² = 4225 vertices', () {
      final mesh = _TestMesh(resolution: 64);
      expect(mesh.vertexCount, 4225);
    });

    test('resolution 256 produces (256+1)² = 66049 vertices', () {
      final mesh = _TestMesh(resolution: 256);
      expect(mesh.vertexCount, 66049);
    });
  });

  group('Mesh index count', () {
    test('resolution 16 produces 16² × 6 = 1536 indices', () {
      final mesh = _TestMesh(resolution: 16);
      expect(mesh.indexCount, 1536);
    });

    test('resolution 64 produces 64² × 6 = 24576 indices', () {
      final mesh = _TestMesh(resolution: 64);
      expect(mesh.indexCount, 24576);
    });
  });

  group('UV coordinate correctness', () {
    test('first vertex UV is (0, 0)', () {
      final mesh = _TestMesh(resolution: 4);
      expect(mesh.uvs[0], 0.0);
      expect(mesh.uvs[1], 0.0);
    });

    test('last vertex UV is (1, 1)', () {
      final mesh = _TestMesh(resolution: 4);
      final lastIdx = (mesh.vertexCount - 1) * 2;
      expect(mesh.uvs[lastIdx], 1.0);
      expect(mesh.uvs[lastIdx + 1], 1.0);
    });

    test('UVs are all within [0, 1]', () {
      final mesh = _TestMesh(resolution: 8);
      for (final uv in mesh.uvs) {
        expect(uv, greaterThanOrEqualTo(0.0));
        expect(uv, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('NDC position correctness', () {
    test('first vertex position is (-1, -1)', () {
      final mesh = _TestMesh(resolution: 4);
      expect(mesh.positions[0], -1.0);
      expect(mesh.positions[1], -1.0);
    });

    test('last vertex position is (1, 1)', () {
      final mesh = _TestMesh(resolution: 4);
      final lastIdx = (mesh.vertexCount - 1) * 2;
      expect(mesh.positions[lastIdx], 1.0);
      expect(mesh.positions[lastIdx + 1], 1.0);
    });

    test('positions are all within [-1, 1]', () {
      final mesh = _TestMesh(resolution: 8);
      for (final p in mesh.positions) {
        expect(p, greaterThanOrEqualTo(-1.0));
        expect(p, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('Depth normalisation math', () {
    test('normalises raw 16-bit values to [0, 1]', () {
      expect(_normalise16(0), 0.0);
      expect(_normalise16(65535), 1.0);
      expect(_normalise16(32768), closeTo(0.5, 0.001));
    });

    test('foreground amplification applies at threshold', () {
      const threshold = 0.55;
      const amplification = 1.5;

      final belowThreshold = 0.4;
      final aboveThreshold = 0.6;

      expect(_amplify(belowThreshold, threshold, amplification),
          belowThreshold);
      expect(
        _amplify(aboveThreshold, threshold, amplification),
        closeTo(aboveThreshold * amplification, 0.001),
      );
    });

    test('foreground amplification clamps to 1.0', () {
      const threshold = 0.55;
      const amplification = 1.5;

      // 0.9 * 1.5 = 1.35, should clamp to 1.0
      expect(_amplify(0.9, threshold, amplification), 1.0);
    });
  });

  group('Triangle winding', () {
    test('all triangles have valid vertex indices', () {
      final mesh = _TestMesh(resolution: 8);
      for (final idx in mesh.indices) {
        expect(idx, greaterThanOrEqualTo(0));
        expect(idx, lessThan(mesh.vertexCount));
      }
    });

    test('index count is divisible by 3 (complete triangles)', () {
      final mesh = _TestMesh(resolution: 16);
      expect(mesh.indexCount % 3, 0);
    });
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────

/// Pure-Dart mesh builder that mirrors the native DepthMesh logic.
class _TestMesh {
  final int resolution;
  late final int vertexCount;
  late final int indexCount;
  late final List<double> positions;
  late final List<double> uvs;
  late final List<double> depths;
  late final List<int> indices;

  _TestMesh({required this.resolution}) {
    final cols = resolution + 1;
    final rows = resolution + 1;
    vertexCount = cols * rows;
    indexCount = resolution * resolution * 6;

    positions = <double>[];
    uvs = <double>[];
    depths = <double>[];
    indices = <int>[];

    // Build vertices.
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final u = col / (cols - 1);
        final v = row / (rows - 1);

        positions.add(u * 2.0 - 1.0); // x in NDC
        positions.add(v * 2.0 - 1.0); // y in NDC

        uvs.add(u);
        uvs.add(v);

        // Synthetic depth: radial gradient.
        final cx = (u - 0.5) * 2.0;
        final cy = (v - 0.5) * 2.0;
        final d = (1.0 - math.sqrt(cx * cx + cy * cy)).clamp(0.0, 1.0);
        depths.add(d);
      }
    }

    // Build indices.
    for (int row = 0; row < rows - 1; row++) {
      for (int col = 0; col < cols - 1; col++) {
        final topLeft = row * cols + col;
        final topRight = topLeft + 1;
        final bottomLeft = (row + 1) * cols + col;
        final bottomRight = bottomLeft + 1;

        indices.addAll([topLeft, bottomLeft, topRight]);
        indices.addAll([topRight, bottomLeft, bottomRight]);
      }
    }
  }
}

/// Normalises a raw unsigned 16-bit value to [0, 1].
double _normalise16(int raw) => raw / 65535.0;

/// Applies foreground amplification, clamping to 1.0.
double _amplify(double depth, double threshold, double amplification) {
  if (depth > threshold) {
    return (depth * amplification).clamp(0.0, 1.0);
  }
  return depth;
}
