import SwiftUI
import CoreLocation
import MetalKit
import simd

struct RoutePalette {
    static let dark = RoutePalette(
        backgroundColor: .black,
        warm: SIMD4<Float>(1.00, 0.42, 0.22, 1.0),
        cool: SIMD4<Float>(0.25, 0.80, 0.85, 1.0),
        white: SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    )

    static let pastel = RoutePalette(
        backgroundColor: .black,
        warm: SIMD4<Float>(1.00, 0.70, 0.55, 1.0),
        cool: SIMD4<Float>(0.65, 0.80, 0.98, 1.0),
        white: SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    )

    let backgroundColor: Color
    let warm: SIMD4<Float>
    let cool: SIMD4<Float>
    let white: SIMD4<Float>
}

struct RouteVertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
}

struct RouteUniforms {
    var warm: SIMD4<Float>
    var cool: SIMD4<Float>
    var time: Float
}

struct RoutePoint {
    var x: Float
    var y: Float
}

struct RouteScene {
    static func build(from coordinates: [CLLocation], palette: RoutePalette = .dark) -> [SIMD2<Float>] {
        guard !coordinates.isEmpty else { return [] }

        let latitudes = coordinates.map { $0.coordinate.latitude }
        let longitudes = coordinates.map { $0.coordinate.longitude }

        let latMin = latitudes.min() ?? 0
        let latMax = latitudes.max() ?? 0
        let lonMin = longitudes.min() ?? 0
        let lonMax = longitudes.max() ?? 0

        let latRange = max(latMax - latMin, 0.0001)
        let lonRange = max(lonMax - lonMin, 0.0001)

        return coordinates.map { coordinate in
            let nx = Float((coordinate.coordinate.longitude - lonMin) / lonRange)
            let ny = Float(1.0 - ((coordinate.coordinate.latitude - latMin) / latRange))
            return SIMD2<Float>(nx, ny)
        }
    }
}

struct PRAXISRouteView: UIViewRepresentable {
    let coordinates: [CLLocation]
    let palette: RoutePalette

    init(coordinates: [CLLocation], palette: RoutePalette = .dark) {
        self.coordinates = coordinates
        self.palette = palette
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(points: RouteScene.build(from: coordinates), palette: palette)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let pipelineState: MTLRenderPipelineState
        private var vertexBuffer: MTLBuffer
        private var indexBuffer: MTLBuffer
        private let uniformsBuffer: MTLBuffer
        private let pointCount: Int
        private var time: Float = 0

        init(points: [SIMD2<Float>], palette: RoutePalette) {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Metal not available")
            }
            self.device = device
            self.commandQueue = device.makeCommandQueue()!

            let library = device.makeDefaultLibrary()
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library?.makeFunction(name: "routeVertex")
            pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "routeFragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            let (vertices, indices) = Self.makeMesh(from: points)
            self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<RouteVertex>.stride, options: [])!
            self.indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: [])!
            self.pointCount = points.count

            self.uniformsBuffer = device.makeBuffer(length: MemoryLayout<RouteUniforms>.stride, options: [])!
            let ptr = uniformsBuffer.contents().bindMemory(to: RouteUniforms.self, capacity: 1)
            ptr[0] = RouteUniforms(warm: palette.warm, cool: palette.cool, time: 0)
        }

        private static func makeMesh(from points: [SIMD2<Float>]) -> ([RouteVertex], [UInt16]) {
            guard !points.isEmpty else { return ([], []) }

            var vertices: [RouteVertex] = []
            var indices: [UInt16] = []
            let ribbonWidth: Float = 1.3
            let wallDepth: Float = 1.25

            for i in 0..<points.count {
                let p = points[i]
                let prev = i == 0 ? points[0] : points[i - 1]
                let next = i == points.count - 1 ? points[points.count - 1] : points[i + 1]
                let tangent = normalize(SIMD2<Float>(next.x - prev.x, next.y - prev.y))
                let normal = SIMD2<Float>(-tangent.y, tangent.x)

                let topLeft = SIMD3<Float>(p.x - normal.x * ribbonWidth, p.y - normal.y * ribbonWidth, 0)
                let topRight = SIMD3<Float>(p.x + normal.x * ribbonWidth, p.y + normal.y * ribbonWidth, 0)
                let bottomLeft = SIMD3<Float>(p.x - normal.x * ribbonWidth, p.y - normal.y * ribbonWidth, -wallDepth)
                let bottomRight = SIMD3<Float>(p.x + normal.x * ribbonWidth, p.y + normal.y * ribbonWidth, -wallDepth)

                let a = RouteVertex(position: topLeft, uv: SIMD2<Float>(Float(i) / Float(max(points.count - 1, 1)), 0.0))
                let b = RouteVertex(position: topRight, uv: SIMD2<Float>(Float(i) / Float(max(points.count - 1, 1)), 0.0))
                let c = RouteVertex(position: bottomLeft, uv: SIMD2<Float>(Float(i) / Float(max(points.count - 1, 1)), 1.0))
                let d = RouteVertex(position: bottomRight, uv: SIMD2<Float>(Float(i) / Float(max(points.count - 1, 1)), 1.0))

                vertices.append(contentsOf: [a, b, c, d])

                if i < points.count - 1 {
                    let base = UInt16(i * 4)
                    indices.append(contentsOf: [
                        base, base + 1, base + 2,
                        base + 1, base + 3, base + 2
                    ])
                }
            }

            return (vertices, indices)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pass = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                return
            }

            time += 1.0 / 60.0

            let ptr = uniformsBuffer.contents().bindMemory(to: RouteUniforms.self, capacity: 1)
            ptr[0].time = time

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexBuffer.length / MemoryLayout<UInt16>.stride, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PRAXISRouteView(coordinates: SampleRoute.potreroHill)
            .frame(width: 360, height: 360)
    }
}


// MARK: - Metal shaders

@MainActor
private func routeShaderSource() -> String {
    """
    #include <metal_stdlib>
    using namespace metal;

    struct RouteVertex {
        float3 position;
        float2 uv;
    };

    struct RouteUniforms {
        float4 warm;
        float4 cool;
        float time;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut routeVertex(uint vid [[vertex_id]],
                                const device RouteVertex* vertices [[buffer(0)]],
                                constant RouteUniforms& uniforms [[buffer(1)]]) {
        RouteVertex v = vertices[vid];
        float noiseWave = sin(v.uv.x * 28.0 + uniforms.time * 2.5 + v.position.y * 9.0) * 0.12;
        float3 pos = v.position;
        pos.z += noiseWave;

        VertexOut out;
        out.position = float4(pos, 1.0);
        out.uv = v.uv;
        return out;
    }

    fragment float4 routeFragment(VertexOut in [[stage_in]],
                                 constant RouteUniforms& uniforms [[buffer(0)]]) {
        float t = in.uv.x;
        float d = in.uv.y; // 0 = top, 1 = bottom

        float noise = sin((t * 22.0) + (uniforms.time * 1.5)) * 0.45
                    + cos((t * 12.0) - (uniforms.time * 1.1) + (in.position.y * 4.0)) * 0.2;

        float verticalFade = pow(1.0 - d, 1.8);
        float edgeBoost = pow(1.0 - d, 4.2);

        float drift = 0.5 + 0.5 * sin(uniforms.time * 0.6 + t * 2.0);
        float3 tint = mix(uniforms.warm.rgb, uniforms.cool.rgb, drift + noise * 0.3);
        float3 core = mix(float3(1.0), tint, 0.35 + noise * 0.2);
        float3 col = mix(tint, core, edgeBoost * 0.8);
        float alpha = (0.35 + (0.65 * verticalFade)) * (0.75 + noise * 0.6);

        return float4(col * alpha, alpha);
    }
    """
}

// This file intentionally keeps the route geometry and shader pipeline self-contained.
// If your project already has a Metal library, move the shader functions into `.metal` files and
// keep this Swift wrapper as the view/controller layer.
