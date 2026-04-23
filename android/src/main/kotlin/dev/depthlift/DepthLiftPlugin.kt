package dev.depthlift

import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.view.TextureRegistry

/**
 * DepthLift Flutter plugin entry point for Android.
 *
 * Registers a Flutter [TextureRegistry.SurfaceTextureEntry] and delegates
 * rendering to [DepthRenderer] on a dedicated GL thread.
 */
class DepthLiftPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    /** Map of textureId → active renderer instances. */
    private val renderers = mutableMapOf<Long, RendererEntry>()

    /** Background thread for GL operations. */
    private var glThread: HandlerThread? = null
    private var glHandler: Handler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "dev.depthlift/engine")
        channel.setMethodCallHandler(this)

        glThread = HandlerThread("DepthLiftGL").also { it.start() }
        glHandler = Handler(glThread!!.looper)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)

        // Release all active renderers.
        renderers.values.forEach { it.release() }
        renderers.clear()

        glThread?.quitSafely()
        glThread = null
        glHandler = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createTexture" -> handleCreateTexture(call, result)
            "setDepthMap"   -> handleSetDepthMap(call, result)
            "updateTilt"    -> handleUpdateTilt(call, result)
            "setOptions"    -> handleSetOptions(call, result)
            "exportFrame"   -> handleExportFrame(call, result)
            "exportVideo"   -> handleExportVideo(call, result)
            "releaseTexture"-> handleReleaseTexture(call, result)
            else            -> result.notImplemented()
        }
    }

    // ─── Method handlers ──────────────────────────────────────────────────

    private fun handleCreateTexture(call: MethodCall, result: MethodChannel.Result) {
        val imageBytes = call.argument<ByteArray>("imageBytes")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val depthScale = call.argument<Double>("depthScale") ?: 0.6
        val parallaxFactor = call.argument<Double>("parallaxFactor") ?: 0.4
        val meshResolution = call.argument<Double>("meshResolution") ?: 64.0
        val focusDepth = call.argument<Double>("focusDepth") ?: 0.5
        val bokehIntensity = call.argument<Double>("bokehIntensity") ?: 0.5
        val effect = call.argument<String>("effect") ?: "parallax"

        if (imageBytes == null || width == 0 || height == 0) {
            result.error("INVALID_ARGS", "imageBytes, width, and height are required", null)
            return
        }

        glHandler?.post {
            try {
                // Register a Flutter texture.
                val entry = textureRegistry.createSurfaceTexture()
                val textureId = entry.id()
                val surfaceTexture = entry.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(width, height)

                val surface = Surface(surfaceTexture)

                // Create the renderer on the GL thread.
                val renderer = DepthRenderer(
                    surface = surface,
                    width = width,
                    height = height,
                    depthScale = depthScale.toFloat(),
                    parallaxFactor = parallaxFactor.toFloat(),
                    meshResolution = meshResolution.toInt(),
                    focusDepth = focusDepth.toFloat(),
                    bokehIntensity = bokehIntensity.toFloat(),
                    effect = effect,
                    assetManager = flutterPluginBinding.applicationContext.assets
                )

                renderer.uploadImage(imageBytes, width, height)
                renderer.startRenderLoop()

                renderers[textureId] = RendererEntry(entry, renderer, surface)

                // Reply on the main thread.
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.success(textureId)
                }
            } catch (e: Exception) {
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.error("CREATE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleSetDepthMap(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()
        val depthMap = call.argument<ByteArray>("depthMap")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0

        if (textureId == null || depthMap == null) {
            result.error("INVALID_ARGS", "textureId and depthMap required", null)
            return
        }

        glHandler?.post {
            renderers[textureId]?.renderer?.setDepthMap(depthMap, width, height)
            Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                result.success(null)
            }
        }
    }

    private fun handleUpdateTilt(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()
        val x = call.argument<Double>("x") ?: 0.0
        val y = call.argument<Double>("y") ?: 0.0

        if (textureId == null) {
            result.error("INVALID_ARGS", "textureId required", null)
            return
        }

        // Tilt updates are fire-and-forget for performance.
        renderers[textureId]?.renderer?.updateTilt(x.toFloat(), y.toFloat())
        result.success(null)
    }

    private fun handleSetOptions(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()

        if (textureId == null) {
            result.error("INVALID_ARGS", "textureId required", null)
            return
        }

        val renderer = renderers[textureId]?.renderer
        if (renderer != null) {
            renderer.depthScale = (call.argument<Double>("depthScale") ?: 0.6).toFloat()
            renderer.parallaxFactor = (call.argument<Double>("parallaxFactor") ?: 0.4).toFloat()
            renderer.focusDepth = (call.argument<Double>("focusDepth") ?: 0.5).toFloat()
            renderer.bokehIntensity = (call.argument<Double>("bokehIntensity") ?: 0.5).toFloat()
            renderer.effect = call.argument<String>("effect") ?: "parallax"
        }
        result.success(null)
    }

    private fun handleExportFrame(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()

        if (textureId == null) {
            result.error("INVALID_ARGS", "textureId required", null)
            return
        }

        glHandler?.post {
            try {
                val png = renderers[textureId]?.renderer?.exportFrame()
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.success(png)
                }
            } catch (e: Exception) {
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleExportVideo(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()
        val durationMs = call.argument<Int>("durationMs") ?: 3000
        val fps = call.argument<Int>("fps") ?: 30

        if (textureId == null) {
            result.error("INVALID_ARGS", "textureId required", null)
            return
        }

        glHandler?.post {
            try {
                val mp4 = renderers[textureId]?.renderer?.exportVideo(durationMs, fps)
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.success(mp4)
                }
            } catch (e: Exception) {
                Handler(flutterPluginBinding.applicationContext.mainLooper).post {
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleReleaseTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Long>("textureId") ?: call.argument<Int>("textureId")?.toLong()

        if (textureId == null) {
            result.error("INVALID_ARGS", "textureId required", null)
            return
        }

        renderers.remove(textureId)?.release()
        result.success(null)
    }

    // ─── Inner holder ─────────────────────────────────────────────────────

    /**
     * Groups the texture entry, renderer, and surface so they can be
     * released together.
     */
    private data class RendererEntry(
        val textureEntry: TextureRegistry.SurfaceTextureEntry,
        val renderer: DepthRenderer,
        val surface: Surface
    ) {
        fun release() {
            renderer.stopRenderLoop()
            renderer.release()
            surface.release()
            textureEntry.release()
        }
    }
}
