import Flutter
import UIKit

/// DepthLift Flutter plugin entry point for iOS.
///
/// Registers a `FlutterTexture` backed by a Metal renderer and handles
/// all method channel calls from the Dart side.
public class DepthLiftPlugin: NSObject, FlutterPlugin {

    private var registrar: FlutterPluginRegistrar?
    private var channel: FlutterMethodChannel?
    private var textureRegistry: FlutterTextureRegistry?

    /// Active renderer instances keyed by texture ID.
    private var renderers: [Int64: RendererEntry] = [:]

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dev.depthlift/engine",
            binaryMessenger: registrar.messenger()
        )
        let instance = DepthLiftPlugin()
        instance.registrar = registrar
        instance.channel = channel
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Method handling

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createTexture":
            handleCreateTexture(call, result: result)
        case "setDepthMap":
            handleSetDepthMap(call, result: result)
        case "updateTilt":
            handleUpdateTilt(call, result: result)
        case "setOptions":
            handleSetOptions(call, result: result)
        case "exportFrame":
            handleExportFrame(call, result: result)
        case "exportVideo":
            handleExportVideo(call, result: result)
        case "releaseTexture":
            handleReleaseTexture(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - createTexture

    private func handleCreateTexture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let imageBytes = args["imageBytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "imageBytes, width, and height required",
                                details: nil))
            return
        }

        let depthScale = args["depthScale"] as? Double ?? 0.6
        let parallaxFactor = args["parallaxFactor"] as? Double ?? 0.4
        let meshResolution = args["meshResolution"] as? Double ?? 64.0
        let focusDepth = args["focusDepth"] as? Double ?? 0.5
        let bokehIntensity = args["bokehIntensity"] as? Double ?? 0.5
        let effect = args["effect"] as? String ?? "parallax"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let registry = self.textureRegistry else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CREATE_FAILED",
                                        message: "Plugin not attached",
                                        details: nil))
                }
                return
            }

            do {
                let renderer = try MetalDepthRenderer(
                    width: width,
                    height: height,
                    depthScale: Float(depthScale),
                    parallaxFactor: Float(parallaxFactor),
                    meshResolution: Int(meshResolution),
                    focusDepth: Float(focusDepth),
                    bokehIntensity: Float(bokehIntensity),
                    effect: effect
                )

                renderer.uploadImage(imageBytes.data, width: width, height: height)

                let textureId = registry.register(renderer)
                renderer.textureId = textureId

                let entry = RendererEntry(renderer: renderer, textureId: textureId)
                DispatchQueue.main.async {
                    self.renderers[textureId] = entry
                    result(textureId)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CREATE_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    // MARK: - setDepthMap

    private func handleSetDepthMap(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64,
              let depthMap = args["depthMap"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId, depthMap, width, height required",
                                details: nil))
            return
        }

        renderers[textureId]?.renderer.setDepthMap(depthMap.data, width: width, height: height)
        result(nil)
    }

    // MARK: - updateTilt

    private func handleUpdateTilt(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId required",
                                details: nil))
            return
        }

        let x = args["x"] as? Double ?? 0.0
        let y = args["y"] as? Double ?? 0.0

        renderers[textureId]?.renderer.updateTilt(x: Float(x), y: Float(y))
        result(nil)
    }

    // MARK: - setOptions

    private func handleSetOptions(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId required",
                                details: nil))
            return
        }

        if let renderer = renderers[textureId]?.renderer {
            renderer.depthScale = Float(args["depthScale"] as? Double ?? 0.6)
            renderer.parallaxFactor = Float(args["parallaxFactor"] as? Double ?? 0.4)
            renderer.focusDepth = Float(args["focusDepth"] as? Double ?? 0.5)
            renderer.bokehIntensity = Float(args["bokehIntensity"] as? Double ?? 0.5)
            renderer.effect = args["effect"] as? String ?? "parallax"
        }

        result(nil)
    }

    // MARK: - exportFrame

    private func handleExportFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId required",
                                details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let png = self?.renderers[textureId]?.renderer.exportFrame()
            DispatchQueue.main.async {
                result(png)
            }
        }
    }

    // MARK: - exportVideo

    private func handleExportVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId required",
                                details: nil))
            return
        }

        let durationMs = args["durationMs"] as? Int ?? 3000
        let fps = args["fps"] as? Int ?? 30

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mp4 = self?.renderers[textureId]?.renderer.exportVideo(
                durationMs: durationMs, fps: fps
            )
            DispatchQueue.main.async {
                result(mp4)
            }
        }
    }

    // MARK: - releaseTexture

    private func handleReleaseTexture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS",
                                message: "textureId required",
                                details: nil))
            return
        }

        if let entry = renderers.removeValue(forKey: textureId) {
            textureRegistry?.unregisterTexture(entry.textureId)
            entry.renderer.release()
        }

        result(nil)
    }
}

// MARK: - RendererEntry

private struct RendererEntry {
    let renderer: MetalDepthRenderer
    let textureId: Int64
}
