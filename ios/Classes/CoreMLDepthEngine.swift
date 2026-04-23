import Foundation
import CoreML
import CoreImage
import Accelerate

/// On-device depth estimation engine using Core ML.
///
/// Loads the Depth Anything v2 Small `.mlpackage` model once (singleton)
/// and runs inference on a background thread. The model expects an input
/// of shape `[1, 3, 518, 518]` and produces `[1, 1, 518, 518]`.
///
/// Post-processing includes normalisation, boundary median filtering,
/// and bilinear upsampling to the original image resolution.
class CoreMLDepthEngine {

    static let inputSize = 518

    /// Singleton instance — the model is loaded once per plugin lifetime.
    static let shared = CoreMLDepthEngine()

    /// The compiled Core ML model, or `nil` if loading failed.
    private var model: MLModel?

    /// Whether the model loaded successfully.
    var isLoaded: Bool { model != nil }

    // MARK: - Init

    private init() {
        loadModel()
    }

    private func loadModel() {
        // Try to load from the app bundle (the .mlmodelc compiled asset).
        let modelName = "depth_anything_v2_small"
        if let url = Bundle.main.url(forResource: modelName,
                                     withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                model = try MLModel(contentsOf: url, configuration: config)
                print("[DepthLift] Core ML model loaded: \(modelName)")
            } catch {
                print("[DepthLift] Failed to load Core ML model: \(error)")
            }
        } else {
            print("[DepthLift] Core ML model asset not found: \(modelName).mlmodelc")
        }
    }

    // MARK: - Public API

    /// Runs depth inference on an RGBA image.
    ///
    /// - Parameters:
    ///   - rgbaData: Raw RGBA pixel bytes.
    ///   - width:    Image width.
    ///   - height:   Image height.
    /// - Returns: 16-bit unsigned LE depth map bytes at the original resolution.
    /// - Throws: If the model is not loaded or inference fails.
    func runInference(rgbaData: Data, width: Int, height: Int) throws -> Data {
        guard let model = model else {
            throw NSError(domain: "DepthLift", code: -1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Core ML model not loaded. Ensure " +
                            "'depth_anything_v2_small.mlmodelc' is in your app bundle."])
        }

        // 1. Pre-process: resize to 518×518, RGBA → RGB, ImageNet normalise.
        let inputArray = preprocessImage(rgbaData: rgbaData, width: width, height: height)

        // 2. Run inference.
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLMultiArray(inputArray)
        ])

        let output = try model.prediction(from: input)

        // 3. Extract raw depth values.
        guard let depthArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw NSError(domain: "DepthLift", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Model output missing"])
        }

        let rawDepth = extractFloats(from: depthArray)

        // 4. Post-process: normalise, median filter, upsample.
        return postprocess(rawDepth: rawDepth, targetWidth: width, targetHeight: height)
    }

    // MARK: - Pre-processing

    private func preprocessImage(rgbaData: Data, width: Int, height: Int) -> [Float] {
        let bytes = [UInt8](rgbaData)
        let size = CoreMLDepthEngine.inputSize
        var result = [Float](repeating: 0, count: 3 * size * size)

        // ImageNet normalisation.
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]

        for c in 0..<3 {
            for y in 0..<size {
                for x in 0..<size {
                    let srcX = min(Int(Float(x) / Float(size) * Float(width)), width - 1)
                    let srcY = min(Int(Float(y) / Float(size) * Float(height)), height - 1)
                    let idx = (srcY * width + srcX) * 4 + c

                    let pixel: Float = idx < bytes.count
                        ? Float(bytes[idx]) / 255.0
                        : 0.0

                    let normalised = (pixel - mean[c]) / std[c]
                    result[c * size * size + y * size + x] = normalised
                }
            }
        }

        return result
    }

    // MARK: - Output extraction

    private func extractFloats(from array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = ptr[i]
        }
        return result
    }

    // MARK: - Post-processing

    private func postprocess(rawDepth: [Float], targetWidth: Int, targetHeight: Int) -> Data {
        let size = CoreMLDepthEngine.inputSize

        // Normalise to [0, 1].
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for v in rawDepth {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
        let range = maxVal - minVal > 1e-6 ? maxVal - minVal : 1.0

        var normalised = rawDepth.map { ($0 - minVal) / range }

        // 5×5 median filter at foreground/background boundaries.
        normalised = medianFilter(normalised, width: size, height: size)

        // Bilinear upsample to target resolution.
        let upsampled = bilinearUpsample(normalised,
                                         srcW: size, srcH: size,
                                         dstW: targetWidth, dstH: targetHeight)

        // Encode to 16-bit unsigned LE.
        var output = Data(count: targetWidth * targetHeight * 2)
        for i in 0..<upsampled.count {
            let value = UInt16(min(max(upsampled[i] * 65535, 0), 65535))
            output[i * 2] = UInt8(value & 0xFF)
            output[i * 2 + 1] = UInt8((value >> 8) & 0xFF)
        }

        return output
    }

    // MARK: - Median filter

    private func medianFilter(_ data: [Float], width: Int, height: Int) -> [Float] {
        var output = data
        let threshold: Float = 0.55
        let radius = 2

        for y in radius..<(height - radius) {
            for x in radius..<(width - radius) {
                let centre = data[y * width + x]
                let isFg = centre > threshold
                var isBoundary = false

                boundaryCheck: for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let neighbour = data[(y + dy) * width + (x + dx)]
                        if (neighbour > threshold) != isFg {
                            isBoundary = true
                            break boundaryCheck
                        }
                    }
                }

                if isBoundary {
                    var window = [Float]()
                    window.reserveCapacity(25)
                    for dy in -radius...radius {
                        for dx in -radius...radius {
                            window.append(data[(y + dy) * width + (x + dx)])
                        }
                    }
                    window.sort()
                    output[y * width + x] = window[window.count / 2]
                }
            }
        }

        return output
    }

    // MARK: - Bilinear upsample

    private func bilinearUpsample(_ src: [Float],
                                   srcW: Int, srcH: Int,
                                   dstW: Int, dstH: Int) -> [Float] {
        var dst = [Float](repeating: 0, count: dstW * dstH)

        for y in 0..<dstH {
            for x in 0..<dstW {
                let srcX = Float(x) / Float(dstW) * Float(srcW - 1)
                let srcY = Float(y) / Float(dstH) * Float(srcH - 1)

                let x0 = min(Int(srcX), srcW - 2)
                let y0 = min(Int(srcY), srcH - 2)

                let fx = srcX - Float(x0)
                let fy = srcY - Float(y0)

                let v00 = src[y0 * srcW + x0]
                let v10 = src[y0 * srcW + x0 + 1]
                let v01 = src[(y0 + 1) * srcW + x0]
                let v11 = src[(y0 + 1) * srcW + x0 + 1]

                dst[y * dstW + x] =
                    v00 * (1 - fx) * (1 - fy) +
                    v10 * fx * (1 - fy) +
                    v01 * (1 - fx) * fy +
                    v11 * fx * fy
            }
        }

        return dst
    }
}

// MARK: - MLMultiArray convenience

private extension MLMultiArray {
    convenience init(_ array: [Float]) throws {
        let shape: [NSNumber] = [1, 3, NSNumber(value: CoreMLDepthEngine.inputSize),
                                  NSNumber(value: CoreMLDepthEngine.inputSize)]
        try self.init(shape: shape, dataType: .float32)
        let ptr = self.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        for i in 0..<array.count {
            ptr[i] = array[i]
        }
    }
}
