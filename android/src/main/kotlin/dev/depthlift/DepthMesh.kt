package dev.depthlift

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer

/**
 * Builds a planar triangle-strip mesh displaced by a depth map.
 *
 * The mesh is a regular grid of [resolution] × [resolution] quads,
 * each split into two triangles. Vertex positions are in normalised
 * device coordinates [-1, 1], UVs are [0, 1], and per-vertex depth
 * values are read from the supplied depth map bytes.
 *
 * Foreground vertices (depth > [FOREGROUND_THRESHOLD]) receive 1.5×
 * amplified Z displacement for a pop-out feel.
 *
 * @param resolution number of subdivisions along each axis (16–256).
 * @param imageWidth  original image width in pixels.
 * @param imageHeight original image height in pixels.
 * @param depthBytes  raw depth map — expected as 16-bit unsigned values,
 *                    two bytes per pixel, little-endian.
 */
class DepthMesh(
    private val resolution: Int,
    private val imageWidth: Int,
    private val imageHeight: Int,
    private val depthBytes: ByteArray
) {
    /** XY positions in NDC, 2 floats per vertex. */
    val positions: FloatBuffer

    /** UV texture coordinates, 2 floats per vertex. */
    val uvs: FloatBuffer

    /** Normalised depth value, 1 float per vertex. */
    val depths: FloatBuffer

    /** Triangle indices (unsigned int). */
    val indices: IntBuffer

    /** Total number of vertices in the mesh. */
    val vertexCount: Int

    /** Total number of index elements. */
    val indexCount: Int

    init {
        val cols = resolution + 1
        val rows = resolution + 1
        vertexCount = cols * rows

        // Two triangles per quad, 3 indices each.
        indexCount = resolution * resolution * 6

        positions = allocFloat(vertexCount * 2)
        uvs = allocFloat(vertexCount * 2)
        depths = allocFloat(vertexCount)
        indices = allocInt(indexCount)

        buildVertices(cols, rows)
        buildIndices(cols, rows)

        positions.position(0)
        uvs.position(0)
        depths.position(0)
        indices.position(0)
    }

    // ─── Vertex generation ────────────────────────────────────────────────

    private fun buildVertices(cols: Int, rows: Int) {
        for (row in 0 until rows) {
            for (col in 0 until cols) {
                val u = col.toFloat() / (cols - 1)
                val v = row.toFloat() / (rows - 1)

                // NDC: x ∈ [-1, 1], y ∈ [-1, 1]
                val x = u * 2f - 1f
                val y = v * 2f - 1f

                positions.put(x)
                positions.put(y)

                uvs.put(u)
                uvs.put(v)

                // Sample depth from the map.
                val depth = sampleDepth(u, v)
                depths.put(depth)
            }
        }
    }

    /**
     * Samples the depth map at normalised coordinates (u, v) using
     * nearest-neighbour lookup. 16-bit values are normalised to [0, 1].
     *
     * Foreground vertices (> [FOREGROUND_THRESHOLD]) get 1.5× amplification.
     */
    private fun sampleDepth(u: Float, v: Float): Float {
        val px = (u * (imageWidth - 1)).toInt().coerceIn(0, imageWidth - 1)
        val py = (v * (imageHeight - 1)).toInt().coerceIn(0, imageHeight - 1)

        val index = (py * imageWidth + px) * 2  // 16-bit per pixel

        if (index + 1 >= depthBytes.size) return 0f

        // Little-endian unsigned 16-bit.
        val lo = depthBytes[index].toInt() and 0xFF
        val hi = depthBytes[index + 1].toInt() and 0xFF
        val raw = (hi shl 8) or lo
        var normalised = raw / 65535f

        // Foreground amplification.
        if (normalised > FOREGROUND_THRESHOLD) {
            normalised *= FOREGROUND_AMPLIFICATION
            normalised = normalised.coerceAtMost(1f)
        }

        return normalised
    }

    // ─── Index generation ─────────────────────────────────────────────────

    private fun buildIndices(cols: Int, rows: Int) {
        for (row in 0 until rows - 1) {
            for (col in 0 until cols - 1) {
                val topLeft = row * cols + col
                val topRight = topLeft + 1
                val bottomLeft = (row + 1) * cols + col
                val bottomRight = bottomLeft + 1

                // First triangle.
                indices.put(topLeft)
                indices.put(bottomLeft)
                indices.put(topRight)

                // Second triangle.
                indices.put(topRight)
                indices.put(bottomLeft)
                indices.put(bottomRight)
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    companion object {
        /** Depth threshold above which a vertex is considered foreground. */
        const val FOREGROUND_THRESHOLD = 0.55f

        /** Z amplification factor for foreground vertices. */
        const val FOREGROUND_AMPLIFICATION = 1.5f

        private fun allocFloat(count: Int): FloatBuffer {
            return ByteBuffer.allocateDirect(count * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
        }

        private fun allocInt(count: Int): IntBuffer {
            return ByteBuffer.allocateDirect(count * 4)
                .order(ByteOrder.nativeOrder())
                .asIntBuffer()
        }
    }
}
