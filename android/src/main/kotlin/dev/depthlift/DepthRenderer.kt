package dev.depthlift

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.*
import android.view.Surface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.*
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.egl.EGLSurface

/**
 * OpenGL ES 3.0 renderer that displaces a textured mesh by a depth map
 * and composites to a Flutter [Surface].
 *
 * All GL calls run on the dedicated GL thread managed by [DepthLiftPlugin].
 */
class DepthRenderer(
    private val surface: Surface,
    private val width: Int,
    private val height: Int,
    var depthScale: Float,
    var parallaxFactor: Float,
    private val meshResolution: Int,
    var focusDepth: Float,
    var bokehIntensity: Float,
    var effect: String,
    private val assetManager: AssetManager
) {
    // EGL handles
    private var egl: EGL10? = null
    private var eglDisplay: EGLDisplay? = null
    private var eglContext: EGLContext? = null
    private var eglSurface: EGLSurface? = null

    // GL handles
    private var program = 0
    private var textureHandle = 0
    private var fboHandle = 0
    private var fboTextureHandle = 0

    // Uniform locations
    private var uMvpLoc = -1
    private var uDepthScaleLoc = -1
    private var uTiltOffsetLoc = -1
    private var uParallaxFactorLoc = -1
    private var uTextureLoc = -1
    private var uFocusDepthLoc = -1
    private var uBokehIntensityLoc = -1
    private var uBokehEnabledLoc = -1

    // Mesh
    private var mesh: DepthMesh? = null
    private var vertexCount = 0
    private var indexCount = 0
    private var vboPosition = 0
    private var vboUv = 0
    private var vboDepth = 0
    private var ibo = 0

    // Tilt offset (updated from Dart via updateTilt)
    @Volatile var tiltX = 0f
    @Volatile var tiltY = 0f

    // Render loop control
    @Volatile private var running = false

    // MVP matrix
    private val mvpMatrix = FloatArray(16)

    // ─── Initialisation ───────────────────────────────────────────────────

    init {
        initEGL()
        initGL()
    }

    private fun initEGL() {
        egl = EGLContext.getEGL() as EGL10
        eglDisplay = egl!!.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        egl!!.eglInitialize(eglDisplay, version)

        val configAttribs = intArrayOf(
            EGL10.EGL_RED_SIZE, 8,
            EGL10.EGL_GREEN_SIZE, 8,
            EGL10.EGL_BLUE_SIZE, 8,
            EGL10.EGL_ALPHA_SIZE, 8,
            EGL10.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
            EGL10.EGL_SURFACE_TYPE, EGL10.EGL_WINDOW_BIT,
            EGL10.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        egl!!.eglChooseConfig(eglDisplay, configAttribs, configs, 1, numConfigs)

        val contextAttribs = intArrayOf(
            EGLExt.EGL_CONTEXT_MAJOR_VERSION_KHR, 3,
            EGL10.EGL_NONE
        )
        eglContext = egl!!.eglCreateContext(
            eglDisplay, configs[0], EGL10.EGL_NO_CONTEXT, contextAttribs
        )
        eglSurface = egl!!.eglCreateWindowSurface(eglDisplay, configs[0], surface, null)
        egl!!.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
    }

    private fun initGL() {
        // Compile shaders.
        val vertSource = loadShaderAsset("depth_vert.glsl")
        val fragSource = loadShaderAsset("depth_frag.glsl")
        program = createProgram(vertSource, fragSource)

        // Uniform locations.
        uMvpLoc = GLES30.glGetUniformLocation(program, "u_mvp")
        uDepthScaleLoc = GLES30.glGetUniformLocation(program, "u_depthScale")
        uTiltOffsetLoc = GLES30.glGetUniformLocation(program, "u_tiltOffset")
        uParallaxFactorLoc = GLES30.glGetUniformLocation(program, "u_parallaxFactor")
        uTextureLoc = GLES30.glGetUniformLocation(program, "u_texture")
        uFocusDepthLoc = GLES30.glGetUniformLocation(program, "u_focusDepth")
        uBokehIntensityLoc = GLES30.glGetUniformLocation(program, "u_bokehIntensity")
        uBokehEnabledLoc = GLES30.glGetUniformLocation(program, "u_bokehEnabled")

        // Create image texture.
        val texIds = IntArray(1)
        GLES30.glGenTextures(1, texIds, 0)
        textureHandle = texIds[0]

        // Create FBO for bokeh pass.
        val fboIds = IntArray(1)
        GLES30.glGenFramebuffers(1, fboIds, 0)
        fboHandle = fboIds[0]

        val fboTexIds = IntArray(1)
        GLES30.glGenTextures(1, fboTexIds, 0)
        fboTextureHandle = fboTexIds[0]

        setupFBO()

        // Identity MVP.
        Matrix.setIdentityM(mvpMatrix, 0)

        GLES30.glViewport(0, 0, width, height)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glClearColor(0f, 0f, 0f, 1f)
    }

    private fun setupFBO() {
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, fboTextureHandle)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA,
            width, height, 0,
            GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null
        )
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)

        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fboHandle)
        GLES30.glFramebufferTexture2D(
            GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0,
            GLES30.GL_TEXTURE_2D, fboTextureHandle, 0
        )
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
    }

    // ─── Image upload ─────────────────────────────────────────────────────

    /**
     * Uploads RGBA image bytes to the GPU texture.
     */
    fun uploadImage(rgbaBytes: ByteArray, w: Int, h: Int) {
        val buffer = ByteBuffer.allocateDirect(rgbaBytes.size)
            .order(ByteOrder.nativeOrder())
        buffer.put(rgbaBytes)
        buffer.position(0)

        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textureHandle)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA,
            w, h, 0,
            GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, buffer
        )
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
    }

    // ─── Depth map ────────────────────────────────────────────────────────

    /**
     * Receives a normalised depth map and (re)builds the mesh.
     */
    fun setDepthMap(depthBytes: ByteArray, w: Int, h: Int) {
        mesh = DepthMesh(meshResolution, w, h, depthBytes)
        uploadMesh()
    }

    private fun uploadMesh() {
        val m = mesh ?: return

        // Delete old buffers if any.
        if (vboPosition != 0) {
            GLES30.glDeleteBuffers(4, intArrayOf(vboPosition, vboUv, vboDepth, ibo), 0)
        }

        val ids = IntArray(4)
        GLES30.glGenBuffers(4, ids, 0)
        vboPosition = ids[0]
        vboUv = ids[1]
        vboDepth = ids[2]
        ibo = ids[3]

        // Positions
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboPosition)
        GLES30.glBufferData(
            GLES30.GL_ARRAY_BUFFER,
            m.positions.capacity() * 4,
            m.positions,
            GLES30.GL_STATIC_DRAW
        )

        // UVs
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboUv)
        GLES30.glBufferData(
            GLES30.GL_ARRAY_BUFFER,
            m.uvs.capacity() * 4,
            m.uvs,
            GLES30.GL_STATIC_DRAW
        )

        // Depth values
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboDepth)
        GLES30.glBufferData(
            GLES30.GL_ARRAY_BUFFER,
            m.depths.capacity() * 4,
            m.depths,
            GLES30.GL_STATIC_DRAW
        )

        // Indices
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, ibo)
        GLES30.glBufferData(
            GLES30.GL_ELEMENT_ARRAY_BUFFER,
            m.indices.capacity() * 4,
            m.indices,
            GLES30.GL_STATIC_DRAW
        )

        vertexCount = m.vertexCount
        indexCount = m.indexCount
    }

    // ─── Tilt ─────────────────────────────────────────────────────────────

    fun updateTilt(x: Float, y: Float) {
        tiltX = x
        tiltY = y
    }

    // ─── Render loop ──────────────────────────────────────────────────────

    fun startRenderLoop() {
        running = true
        Thread {
            while (running) {
                drawFrame()
                egl?.eglSwapBuffers(eglDisplay, eglSurface)
                // Target ≈ 60 fps.
                Thread.sleep(16)
            }
        }.start()
    }

    fun stopRenderLoop() {
        running = false
    }

    private fun drawFrame() {
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)

        if (indexCount == 0) {
            // No mesh yet — just clear.
            return
        }

        GLES30.glUseProgram(program)

        // Uniforms
        GLES30.glUniformMatrix4fv(uMvpLoc, 1, false, mvpMatrix, 0)
        GLES30.glUniform1f(uDepthScaleLoc, depthScale)
        GLES30.glUniform2f(uTiltOffsetLoc, tiltX, tiltY)
        GLES30.glUniform1f(uParallaxFactorLoc, parallaxFactor)
        GLES30.glUniform1f(uFocusDepthLoc, focusDepth)
        GLES30.glUniform1f(uBokehIntensityLoc, bokehIntensity)
        GLES30.glUniform1i(uBokehEnabledLoc, if (effect == "bokeh") 1 else 0)

        // Texture
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textureHandle)
        GLES30.glUniform1i(uTextureLoc, 0)

        // Positions (location 0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboPosition)
        GLES30.glEnableVertexAttribArray(0)
        GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 0, 0)

        // UVs (location 1)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboUv)
        GLES30.glEnableVertexAttribArray(1)
        GLES30.glVertexAttribPointer(1, 2, GLES30.GL_FLOAT, false, 0, 0)

        // Depth (location 2)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vboDepth)
        GLES30.glEnableVertexAttribArray(2)
        GLES30.glVertexAttribPointer(2, 1, GLES30.GL_FLOAT, false, 0, 0)

        // Draw
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, ibo)
        GLES30.glDrawElements(
            GLES30.GL_TRIANGLES, indexCount,
            GLES30.GL_UNSIGNED_INT, 0
        )

        GLES30.glDisableVertexAttribArray(0)
        GLES30.glDisableVertexAttribArray(1)
        GLES30.glDisableVertexAttribArray(2)
    }

    // ─── Export ───────────────────────────────────────────────────────────

    fun exportFrame(): ByteArray {
        drawFrame()

        val buffer = ByteBuffer.allocateDirect(width * height * 4)
            .order(ByteOrder.nativeOrder())
        GLES30.glReadPixels(0, 0, width, height, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, buffer)
        buffer.position(0)

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(buffer)

        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()

        return out.toByteArray()
    }

    fun exportVideo(durationMs: Int, fps: Int): ByteArray {
        // Video export is a placeholder — full MediaCodec implementation
        // would go here. For now, return a single-frame PNG.
        return exportFrame()
    }

    // ─── Cleanup ──────────────────────────────────────────────────────────

    fun release() {
        if (vboPosition != 0) {
            GLES30.glDeleteBuffers(4, intArrayOf(vboPosition, vboUv, vboDepth, ibo), 0)
        }
        if (textureHandle != 0) {
            GLES30.glDeleteTextures(1, intArrayOf(textureHandle), 0)
        }
        if (fboTextureHandle != 0) {
            GLES30.glDeleteTextures(1, intArrayOf(fboTextureHandle), 0)
        }
        if (fboHandle != 0) {
            GLES30.glDeleteFramebuffers(1, intArrayOf(fboHandle), 0)
        }
        if (program != 0) {
            GLES30.glDeleteProgram(program)
        }

        egl?.eglMakeCurrent(
            eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT
        )
        egl?.eglDestroySurface(eglDisplay, eglSurface)
        egl?.eglDestroyContext(eglDisplay, eglContext)
        egl?.eglTerminate(eglDisplay)
    }

    // ─── Shader helpers ───────────────────────────────────────────────────

    private fun loadShaderAsset(filename: String): String {
        return try {
            assetManager.open("flutter_assets/packages/depthlift/assets/shaders/$filename")
                .bufferedReader().readText()
        } catch (_: Exception) {
            // Fallback: embedded minimal shader.
            if (filename.contains("vert")) DEFAULT_VERT_SHADER else DEFAULT_FRAG_SHADER
        }
    }

    private fun createProgram(vertSource: String, fragSource: String): Int {
        val vert = compileShader(GLES30.GL_VERTEX_SHADER, vertSource)
        val frag = compileShader(GLES30.GL_FRAGMENT_SHADER, fragSource)

        val prog = GLES30.glCreateProgram()
        GLES30.glAttachShader(prog, vert)
        GLES30.glAttachShader(prog, frag)

        // Bind attribute locations before linking.
        GLES30.glBindAttribLocation(prog, 0, "a_position")
        GLES30.glBindAttribLocation(prog, 1, "a_uv")
        GLES30.glBindAttribLocation(prog, 2, "a_depth")

        GLES30.glLinkProgram(prog)

        val status = IntArray(1)
        GLES30.glGetProgramiv(prog, GLES30.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetProgramInfoLog(prog)
            GLES30.glDeleteProgram(prog)
            throw RuntimeException("Program link failed: $log")
        }

        GLES30.glDeleteShader(vert)
        GLES30.glDeleteShader(frag)

        return prog
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)

        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetShaderInfoLog(shader)
            GLES30.glDeleteShader(shader)
            throw RuntimeException("Shader compile failed: $log")
        }
        return shader
    }

    companion object {
        private const val DEFAULT_VERT_SHADER = """
            #version 300 es
            layout(location = 0) in vec2 a_position;
            layout(location = 1) in vec2 a_uv;
            layout(location = 2) in float a_depth;
            uniform mat4 u_mvp;
            uniform float u_depthScale;
            uniform vec2 u_tiltOffset;
            uniform float u_parallaxFactor;
            out vec2 v_uv;
            out float v_depth;
            void main() {
                vec3 pos = vec3(a_position, a_depth * u_depthScale);
                pos.xy += u_tiltOffset * u_parallaxFactor * a_depth;
                gl_Position = u_mvp * vec4(pos, 1.0);
                v_uv = a_uv;
                v_depth = a_depth;
            }
        """

        private const val DEFAULT_FRAG_SHADER = """
            #version 300 es
            precision mediump float;
            in vec2 v_uv;
            in float v_depth;
            uniform sampler2D u_texture;
            uniform float u_focusDepth;
            uniform float u_bokehIntensity;
            uniform int u_bokehEnabled;
            out vec4 fragColor;
            void main() {
                fragColor = texture(u_texture, v_uv);
            }
        """
    }
}
