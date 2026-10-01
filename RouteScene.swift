import Foundation
import SceneKit
import CoreLocation
import UIKit
import simd

// MARK: - Palette
struct RoutePalette {
    static let dark = RoutePalette(
        backgroundColor: .black,
        foregroundColor: .white,
        accentColor: .white,
        wallWarm: UIColor(red: 1.00, green: 0.42, blue: 0.22, alpha: 1),
        wallCool: UIColor(red: 0.25, green: 0.80, blue: 0.85, alpha: 1)
    )
    
    static let pastel = RoutePalette(
        backgroundColor: .black,
        foregroundColor: .white,
        accentColor: .white,
        wallWarm: UIColor(red: 1.00, green: 0.70, blue: 0.55, alpha: 1),
        wallCool: UIColor(red: 0.65, green: 0.80, blue: 0.98, alpha: 1)
    )
    
    static let mono = RoutePalette(
        backgroundColor: .black,
        foregroundColor: .white,
        accentColor: .white,
        wallWarm: UIColor(red: 0.90, green: 0.92, blue: 1.0, alpha: 1),
        wallCool: UIColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 1)
    )
    
    let backgroundColor: UIColor
    let foregroundColor: UIColor
    let accentColor: UIColor
    let wallWarm: UIColor
    let wallCool: UIColor
    
    func vec4(_ c: UIColor) -> SCNVector4 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SCNVector4(Float(r), Float(g), Float(b), 1)
    }
}


// MARK: - RouteScene
struct RouteScene {
    let scene: SCNScene
    let camera: SCNCamera
    let lineNode: SCNNode
    let centerNode: SCNNode
    let dotNode: SCNNode
    let dotAnimationNode: SCNNode
    let wallNode: SCNNode
    let animationDuration: TimeInterval
    
    private static let initialFocalLength: CGFloat = 42.0
    private static let wallDepth: Float = 42.0
    private static let traceTime: Double = 4.0
    private static let holdTime: Double = 1.6
    
    var zoom: CGFloat = 1.0 {
        didSet { camera.focalLength = Self.initialFocalLength * zoom }
    }
    
    static func build(from coordinates: [CLLocation], palette: RoutePalette = .dark) -> RouteScene? {
        guard coordinates.count > 1 else { return nil }
        
        let latMin = coordinates.map { $0.coordinate.latitude }.min() ?? 0
        let latMax = coordinates.map { $0.coordinate.latitude }.max() ?? 0
        let lonMin = coordinates.map { $0.coordinate.longitude }.min() ?? 0
        let lonMax = coordinates.map { $0.coordinate.longitude }.max() ?? 0
        let altMin = coordinates.map { $0.altitude }.min() ?? 0
        
        let latRange = latMax - latMin
        let lonRange = lonMax - lonMin
        
        let boundsSize = CGSize.aspectFit(
            aspectRatio: CGSize(width: CGFloat(max(lonRange, 1e-9)), height: CGFloat(max(latRange, 1e-9))),
            boundingSize: CGSize(width: 200, height: 200)
        )
        
        let scene = SCNScene()
        scene.background.contents = palette.backgroundColor
        
        let routeCenterNode = SCNNode()
        scene.rootNode.addChildNode(routeCenterNode)
        
        // MARK: Points
        let altitudeMultiplier = 0.35
        let step = max(1, coordinates.count / 300)
        var raw: [SCNVector3] = []
        
        for i in stride(from: 0, to: coordinates.count, by: step) {
            let c = coordinates[i]
            let nLat = 1 - ((c.coordinate.latitude - latMin) / (latRange == 0 ? 1 : latRange))
            let z = Double(boundsSize.height) * nLat - Double(boundsSize.height / 2)
            let x = Double(boundsSize.width) * ((c.coordinate.longitude - lonMin) / (lonRange == 0 ? 1 : lonRange)) - Double(boundsSize.width / 2)
            let y = (c.altitude - altMin) * altitudeMultiplier
            raw.append(SCNVector3(x, y, z))
        }
        
        let points = smooth(raw, passes: 4)
        
        // Normalized distance along the route (0...1)
        var cum: [Float] = [0]
        for i in 1..<points.count {
            cum.append(cum[i - 1] + points[i].distance(to: points[i - 1]))
        }
        let total = max(cum.last ?? 1, 0.001)
        let ts = cum.map { $0 / total }
        
        // MARK: Fluid Stroke (Main Visual)
        let fluidMat = SCNMaterial()
        fluidMat.lightingModel = .constant
        fluidMat.diffuse.contents = UIColor.white
        fluidMat.isDoubleSided = true
        fluidMat.blendMode = .add
        fluidMat.writesToDepthBuffer = false
        fluidMat.readsFromDepthBuffer = false
        
        fluidMat.setValue(NSNumber(value: 0.0), forKey: "progress")
        fluidMat.setValue(NSNumber(value: 0.0), forKey: "time")
        fluidMat.setValue(NSValue(scnVector4: palette.vec4(palette.wallWarm)), forKey: "warmColor")
        fluidMat.setValue(NSValue(scnVector4: palette.vec4(palette.wallCool)), forKey: "coolColor")
        
        fluidMat.shaderModifiers = [
            .fragment: """
            uniform float progress;
            uniform float time;
            uniform float4 warmColor;
            uniform float4 coolColor;
            
            float t = _surface.diffuseTexcoord.x;  // Along path (0...1)
            float d = _surface.diffuseTexcoord.y;  // Radial distance (0...1)
            
            // Discard if past progress
            if (t > progress) {
                discard_fragment();
            }
            
            // Fluid morphing: create wavy, organic edges
            float waveFreq = 6.0;
            float waveAmp = 0.15;
            float waveMorph = sin(t * waveFreq + time * 2.5) * waveAmp + cos(t * waveFreq * 0.5 + time * 1.8) * waveAmp * 0.5;
            
            // Soft radial falloff with morphing
            float morphedD = d + waveMorph;
            float radialFade = 1.0 - smoothstep(0.4, 1.0, morphedD);
            
            // Turbulent inner glow
            float turbulence = sin(t * 3.0 + time) * 0.3 + cos(d * 2.0 + time * 1.2) * 0.2;
            float innerGlow = pow(max(0.0, 1.0 - morphedD), 2.5) * (0.8 + turbulence * 0.5);
            
            // Color shift based on position and time
            float colorShift = sin(t * 2.0 + time * 0.6) * 0.5 + 0.5;
            float3 tint = mix(warmColor.rgb, coolColor.rgb, colorShift);
            
            // Add bright core
            float core = pow(max(0.0, 1.0 - morphedD * 0.6), 3.0);
            float3 col = tint * radialFade + float3(1.0) * core * innerGlow;
            
            // Final alpha with pulsing effect
            float pulse = 0.7 + 0.3 * sin(time * 2.0 + t * 4.0);
            float a = radialFade * pulse * 0.9;
            
            _output.color = float4(col * a, a);
            """
        ]
        
        let fluidGeometry = makeTube(points: points, ts: ts, radius: 2.5, sides: 12)
        fluidGeometry.materials = [fluidMat]
        let fluidNode = SCNNode(geometry: fluidGeometry)
        fluidNode.renderingOrder = 1
        routeCenterNode.addChildNode(fluidNode)
        
        // MARK: Camera + bloom
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.focalLength = initialFocalLength
        camera.wantsHDR = true
        camera.bloomIntensity = 2.2
        camera.bloomThreshold = 0.25
        camera.bloomBlurRadius = 28
        camera.wantsExposureAdaptation = false
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 90, 300)
        scene.rootNode.addChildNode(cameraNode)
        
        let lookTarget = SCNNode()
        lookTarget.position = SCNVector3(0, -18, 0)
        scene.rootNode.addChildNode(lookTarget)
        cameraNode.constraints = [SCNLookAtConstraint(target: lookTarget)]
        
        let dolly = CABasicAnimation(keyPath: "position.z")
        dolly.fromValue = 320
        dolly.toValue = 285
        dolly.duration = 10
        dolly.autoreverses = true
        dolly.repeatCount = .infinity
        dolly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.addAnimation(dolly, forKey: "dolly")
        
        // MARK: Dots
        func makeDot(radius: CGFloat) -> SCNNode {
            let node = SCNNode(geometry: SCNSphere(radius: radius))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = palette.accentColor
            m.emission.contents = palette.accentColor
            m.emission.intensity = 2.0
            node.geometry?.materials = [m]
            node.renderingOrder = 2
            routeCenterNode.addChildNode(node)
            return node
        }
        
        let dotNode = makeDot(radius: 3.5)
        let trailNode = makeDot(radius: 2.0)
        
        // MARK: Trace animation
        func position(at p: Float) -> SCNVector3 {
            var lo = 0, hi = ts.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if ts[mid] <= p { lo = mid } else { hi = mid }
            }
            let span = max(ts[hi] - ts[lo], 1e-6)
            let f = min(max((p - ts[lo]) / span, 0), 1)
            let a = points[lo], b = points[hi]
            return SCNVector3(
                a.x + (b.x - a.x) * f,
                a.y + (b.y - a.y) * f,
                a.z + (b.z - a.z) * f
            )
        }
        
        let cycle = traceTime + holdTime
        let driver = SCNNode()
        let tick = SCNAction.customAction(duration: cycle) { _, elapsed in
            let r = min(Double(elapsed) / traceTime, 1)
            let eased = Float(r * r * (3 - 2 * r))
            
            fluidMat.setValue(NSNumber(value: eased), forKey: "progress")
            fluidMat.setValue(NSNumber(value: elapsed), forKey: "time")
            
            dotNode.position = position(at: eased)
            trailNode.position = position(at: max(eased - 0.025, 0))
        }
        driver.runAction(.repeatForever(tick))
        scene.rootNode.addChildNode(driver)
        
        // MARK: Slow spin
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 2 * Float.pi))
        spin.duration = 36
        spin.repeatCount = .infinity
        routeCenterNode.addAnimation(spin, forKey: "rotation")
        
        return RouteScene(
            scene: scene,
            camera: camera,
            lineNode: fluidNode,
            centerNode: routeCenterNode,
            dotNode: dotNode,
            dotAnimationNode: dotNode,
            wallNode: fluidNode,
            animationDuration: cycle
        )
    }
    
    // MARK: - Geometry helpers
    
    private static func smooth(_ pts: [SCNVector3], passes: Int) -> [SCNVector3] {
        guard pts.count > 2 else { return pts }
        var out = pts
        for _ in 0..<passes {
            var next = out
            for i in 1..<(out.count - 1) {
                next[i] = SCNVector3(
                    (out[i - 1].x + out[i].x * 2 + out[i + 1].x) / 4,
                    (out[i - 1].y + out[i].y * 2 + out[i + 1].y) / 4,
                    (out[i - 1].z + out[i].z * 2 + out[i + 1].z) / 4
                )
            }
            out = next
        }
        return out
    }
    
    private static func makeTube(points: [SCNVector3], ts: [Float], radius: Float, sides: Int) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var idx: [Int32] = []
        
        let n = points.count
        
        for i in 0..<n {
            let p = simd_float3(points[i].x, points[i].y, points[i].z)
            let a = points[max(i - 1, 0)]
            let b = points[min(i + 1, n - 1)]
            
            var tangent = simd_float3(b.x - a.x, b.y - a.y, b.z - a.z)
            if simd_length(tangent) < 1e-6 { tangent = simd_float3(1, 0, 0) }
            tangent = simd_normalize(tangent)
            
            let ref: simd_float3 = abs(tangent.y) > 0.95 ? simd_float3(1, 0, 0) : simd_float3(0, 1, 0)
            let right = simd_normalize(simd_cross(tangent, ref))
            let up = simd_cross(right, tangent)
            
            for j in 0..<sides {
                let ang = Float(j) / Float(sides) * 2 * Float.pi
                let v = p + right * cos(ang) * radius + up * sin(ang) * radius
                verts.append(SCNVector3(v.x, v.y, v.z))
                uvs.append(CGPoint(x: CGFloat(ts[i]), y: CGFloat(cos(ang)) * 0.5 + 0.5))
            }
        }
        
        for i in 0..<(n - 1) {
            for j in 0..<sides {
                let j2 = (j + 1) % sides
                let a = Int32(i * sides + j)
                let b = Int32(i * sides + j2)
                let c = Int32((i + 1) * sides + j)
                let d = Int32((i + 1) * sides + j2)
                idx += [a, b, c, c, b, d]
            }
        }
        
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: verts),
                SCNGeometrySource(textureCoordinates: uvs)
            ],
            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)]
        )
    }
}
