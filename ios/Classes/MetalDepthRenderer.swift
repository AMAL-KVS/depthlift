import Foundation
import Metal
import MetalKit
import CoreVideo
import Flutter

/// Metal-based renderer that displaces a textured mesh by a depth map
/// and writes each frame to a `CVPixelBuffer` registered as a
/// `FlutterTexture`.
///
/// All GPU work runs on a background dispatch queue; the pixel buffer
/// is handed to Flutter's texture registry for compositing.
class MetalDepthRenderer: NSObject, FlutterTexture {

    // MARK: - Public properties

    var depthScale: Float
    var parallaxFactor: Float
    var focusDepth: Float
    var bokehIntensity: Float
    var effect: String

    /// Set by the plugin after texture registration.
    var textureId: Int64 = -1

    // MARK: - Metal state

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var depthStencilState: MTLDepthStencilState?

    // MARK: - Buffers

    private var vertexBuffer: MTLBuffer?
    private var uvBuffer: MTLBuffer?
    private var depthBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var indexCount: Int = 0

    // MARK: - Texture

    private var imageTexture: MTLTexture?
    private let textureLoader: MTKTextureLoader

    // MARK: - CVPixelBuffer output

    private let width: Int
    private let height: Int
    private var outputPixelBuffer: CVPixelBuffer?
    private var outputTexture: MTLTexture?
    private var renderPassDescriptor: MTLRenderPassDescriptor?

    // MARK: - Mesh

    private let meshResolution: Int
    private var mesh: DepthMesh?

    // MARK: - Tilt

    private var tiltX: Float = 0
    private var tiltY: Float = 0

    // MARK: - Render loop

    private var displayLink: CADisplayLink?
    private var isRunning = false

    // MARK: - Uniform struct (matches Metal shader)

    struct Uniforms {
        var mvp: simd_float4x4
        var depthScale: Float
        var parallaxFactor: Float
        var tiltOffset: SIMD2<Float>
        var focusDepth: Float
        var bokehIntensity: Float
        var bokehEnabled: Int32
        var _padding: Int32 = 0
    }

    // MARK: - Init

    init(width: Int,
         height: Int,
         depthScale: Float,
         parallaxFactor: Float,
         meshResolution: Int,
         focusDepth: Float,
         bokehIntensity: Float,
         effect: String) throws {

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "DepthLift", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Metal not available"])
        }

        self.device = device
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        self.width = width
        self.height = height
        self.depthScale = depthScale
        self.parallaxFactor = parallaxFactor
        self.meshResolution = meshResolution
        self.focusDepth = focusDepth
        self.bokehIntensity = bokehIntensity
        self.effect = effect

        super.init()

        try setupPipeline()
        setupOutputBuffer()
    }

    // MARK: - Pipeline setup

    private func setupPipeline() throws {
        guard let library = try? device.makeDefaultLibrary() ??
                device.makeLibrary(source: MetalDepthRenderer.defaultShaderSource,
                                   options: nil) else {
            throw NSError(domain: "DepthLift", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile Metal shaders"])
        }

        let vertexFunc = library.makeFunction(name: "depth_vertex")
        let fragmentFunc = library.makeFunction(name: "depth_fragment")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)

        // Uniform buffer.
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride,
                                          options: .storageModeShared)
    }

    // MARK: - CVPixelBuffer output

    private func setupOutputBuffer() {
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                            &pixelBuffer)
        outputPixelBuffer = pixelBuffer

        // Create a Metal texture backed by the pixel buffer.
        if let pb = pixelBuffer {
            var cvTexture: CVMetalTexture?
            var textureCache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
            if let cache = textureCache {
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, cache, pb, nil,
                    .bgra8Unorm, width, height, 0, &cvTexture
                )
                if let cvTex = cvTexture {
                    outputTexture = CVMetalTextureGetTexture(cvTex)
                }
            }
        }

        // Render pass descriptor.
        renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor?.colorAttachments[0].texture = outputTexture
        renderPassDescriptor?.colorAttachments[0].loadAction = .clear
        renderPassDescriptor?.colorAttachments[0].storeAction = .store
        renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1
        )

        // Depth attachment.
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width, height: height, mipmapped: false
        )
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        let depthTexture = device.makeTexture(descriptor: depthDesc)
        renderPassDescriptor?.depthAttachment.texture = depthTexture
        renderPassDescriptor?.depthAttachment.loadAction = .clear
        renderPassDescriptor?.depthAttachment.storeAction = .dontCare
        renderPassDescriptor?.depthAttachment.clearDepth = 1.0
    }

    // MARK: - FlutterTexture

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pb = outputPixelBuffer else { return nil }
        return Unmanaged.passRetained(pb)
    }

    // MARK: - Image upload

    func uploadImage(_ data: Data, width: Int, height: Int) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height, mipmapped: false
        )
        desc.usage = [.shaderRead]
        imageTexture = device.makeTexture(descriptor: desc)
        imageTexture?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: (data as NSData).bytes,
            bytesPerRow: width * 4
        )
    }

    // MARK: - Depth map

    func setDepthMap(_ data: Data, width: Int, height: Int) {
        mesh = DepthMesh(resolution: meshResolution,
                         imageWidth: width,
                         imageHeight: height,
                         depthData: data)
        uploadMesh()
    }

    private func uploadMesh() {
        guard let m = mesh else { return }

        vertexBuffer = device.makeBuffer(
            bytes: m.positions, length: m.positions.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        uvBuffer = device.makeBuffer(
            bytes: m.uvs, length: m.uvs.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        depthBuffer = device.makeBuffer(
            bytes: m.depths, length: m.depths.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        indexBuffer = device.makeBuffer(
            bytes: m.indices, length: m.indices.count * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        )
        indexCount = m.indices.count
    }

    // MARK: - Tilt

    func updateTilt(x: Float, y: Float) {
        tiltX = x
        tiltY = y
    }

    // MARK: - Render

    func startRenderLoop() {
        guard !isRunning else { return }
        isRunning = true

        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopRenderLoop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func renderFrame() {
        drawFrame()
    }

    private func drawFrame() {
        guard let rpd = renderPassDescriptor,
              let pipeline = pipelineState,
              indexCount > 0 else { return }

        // Update uniforms.
        var uniforms = Uniforms(
            mvp: matrix_identity_float4x4,
            depthScale: depthScale,
            parallaxFactor: parallaxFactor,
            tiltOffset: SIMD2<Float>(tiltX, tiltY),
            focusDepth: focusDepth,
            bokehIntensity: bokehIntensity,
            bokehEnabled: effect == "bokeh" ? 1 : 0
        )
        memcpy(uniformBuffer?.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        // Vertex buffers.
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(depthBuffer, offset: 0, index: 2)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)

        // Fragment texture.
        encoder.setFragmentTexture(imageTexture, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Draw indexed triangles.
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer!,
            indexBufferOffset: 0
        )

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - Export

    func exportFrame() -> Data? {
        drawFrame()
        guard let pb = outputPixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let totalBytes = bytesPerRow * height

        let data = Data(bytes: baseAddress, count: totalBytes)

        // Convert raw BGRA to PNG via UIImage.
        guard let cgImage = createCGImage(from: data, width: width, height: height,
                                          bytesPerRow: bytesPerRow) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData()
    }

    func exportVideo(durationMs: Int, fps: Int) -> Data? {
        // Placeholder — full AVAssetWriter implementation would go here.
        return exportFrame()
    }

    private func createCGImage(from data: Data, width: Int, height: Int,
                               bytesPerRow: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                    CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Cleanup

    func release() {
        stopRenderLoop()
        vertexBuffer = nil
        uvBuffer = nil
        depthBuffer = nil
        indexBuffer = nil
        uniformBuffer = nil
        imageTexture = nil
        outputTexture = nil
        outputPixelBuffer = nil
    }

    // MARK: - Fallback shader source

    static let defaultShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 mvp;
        float    depthScale;
        float    parallaxFactor;
        float2   tiltOffset;
        float    focusDepth;
        float    bokehIntensity;
        int      bokehEnabled;
        int      _padding;
    };

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 uv       [[attribute(1)]];
        float  depth    [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float  depth;
    };

    vertex VertexOut depth_vertex(uint vid [[vertex_id]],
                                  const device float2 *positions [[buffer(0)]],
                                  const device float2 *uvs       [[buffer(1)]],
                                  const device float  *depths    [[buffer(2)]],
                                  constant Uniforms &u           [[buffer(3)]]) {
        VertexOut out;
        float2 pos = positions[vid];
        float2 uv  = uvs[vid];
        float  d   = depths[vid];

        float3 displaced = float3(pos, d * u.depthScale);
        displaced.xy += u.tiltOffset * u.parallaxFactor * d;

        out.position = u.mvp * float4(displaced, 1.0);
        out.uv       = uv;
        out.depth    = d;
        return out;
    }

    fragment float4 depth_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(mag_filter::linear, min_filter::linear);
        float4 color = tex.sample(s, in.uv);

        if (u.bokehEnabled == 1) {
            float blurAmount = abs(in.depth - u.focusDepth) * u.bokehIntensity * 8.0;
            if (blurAmount > 0.1) {
                float2 texSize = float2(tex.get_width(), tex.get_height());
                float2 texel = 1.0 / texSize;
                float4 blurred = float4(0.0);
                float weights[9] = {0.0279, 0.0659, 0.1210, 0.1747, 0.2010,
                                     0.1747, 0.1210, 0.0659, 0.0279};
                for (int i = 0; i < 9; i++) {
                    float offset = float(i - 4) * blurAmount;
                    blurred += tex.sample(s, in.uv + float2(offset * texel.x, 0.0)) * weights[i] * 0.5;
                    blurred += tex.sample(s, in.uv + float2(0.0, offset * texel.y)) * weights[i] * 0.5;
                }
                color = blurred;
            }
        }

        return color;
    }
    """
}
