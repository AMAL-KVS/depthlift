import Foundation

/// Builds a planar triangle mesh displaced by a depth map for Metal rendering.
///
/// The mesh is a regular grid of `resolution × resolution` quads, each split
/// into two triangles. Positions are in NDC [-1, 1], UVs are [0, 1], and
/// per-vertex depth values are sampled from the supplied 16-bit depth map.
///
/// Foreground vertices (depth > 0.55) receive 1.5× amplified Z displacement.
class DepthMesh {

    /// Foreground / background threshold.
    static let foregroundThreshold: Float = 0.55

    /// Z amplification for foreground vertices.
    static let foregroundAmplification: Float = 1.5

    /// XY positions in NDC, 2 floats per vertex.
    let positions: [Float]

    /// UV texture coordinates, 2 floats per vertex.
    let uvs: [Float]

    /// Normalised depth values, 1 float per vertex.
    let depths: [Float]

    /// Triangle indices (UInt32).
    let indices: [UInt32]

    /// Total number of vertices.
    let vertexCount: Int

    /// Total number of index elements.
    let indexCount: Int

    /// Creates a new depth mesh.
    ///
    /// - Parameters:
    ///   - resolution: Grid subdivisions along each axis (16–256).
    ///   - imageWidth: Original image width in pixels.
    ///   - imageHeight: Original image height in pixels.
    ///   - depthData: Raw 16-bit unsigned LE depth map bytes.
    init(resolution: Int, imageWidth: Int, imageHeight: Int, depthData: Data) {
        let cols = resolution + 1
        let rows = resolution + 1
        vertexCount = cols * rows
        indexCount = resolution * resolution * 6

        var pos = [Float]()
        pos.reserveCapacity(vertexCount * 2)

        var uv = [Float]()
        uv.reserveCapacity(vertexCount * 2)

        var dep = [Float]()
        dep.reserveCapacity(vertexCount)

        var idx = [UInt32]()
        idx.reserveCapacity(indexCount)

        let depthBytes = [UInt8](depthData)

        // ── Build vertices ──────────────────────────────────────────

        for row in 0..<rows {
            for col in 0..<cols {
                let u = Float(col) / Float(cols - 1)
                let v = Float(row) / Float(rows - 1)

                // NDC: [-1, 1]
                let x = u * 2.0 - 1.0
                let y = v * 2.0 - 1.0

                pos.append(x)
                pos.append(y)

                uv.append(u)
                uv.append(v)

                // Sample depth.
                let px = min(Int(u * Float(imageWidth - 1)), imageWidth - 1)
                let py = min(Int(v * Float(imageHeight - 1)), imageHeight - 1)
                let byteIndex = (py * imageWidth + px) * 2

                var depth: Float = 0
                if byteIndex + 1 < depthBytes.count {
                    let lo = UInt16(depthBytes[byteIndex])
                    let hi = UInt16(depthBytes[byteIndex + 1])
                    let raw = (hi << 8) | lo
                    depth = Float(raw) / 65535.0
                }

                // Foreground amplification.
                if depth > DepthMesh.foregroundThreshold {
                    depth = min(depth * DepthMesh.foregroundAmplification, 1.0)
                }

                dep.append(depth)
            }
        }

        // ── Build indices ───────────────────────────────────────────

        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                let topLeft = UInt32(row * cols + col)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((row + 1) * cols + col)
                let bottomRight = bottomLeft + 1

                // First triangle.
                idx.append(topLeft)
                idx.append(bottomLeft)
                idx.append(topRight)

                // Second triangle.
                idx.append(topRight)
                idx.append(bottomLeft)
                idx.append(bottomRight)
            }
        }

        self.positions = pos
        self.uvs = uv
        self.depths = dep
        self.indices = idx
    }
}
