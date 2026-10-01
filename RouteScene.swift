import SwiftUI
import CoreLocation

struct RoutePalette {
    static let dark = RoutePalette(
        backgroundColor: Color.black,
        warm: Color(red: 1.00, green: 0.42, blue: 0.22),
        cool: Color(red: 0.25, green: 0.80, blue: 0.85),
        highlight: Color.white,
        glow: Color.white.opacity(0.92)
    )
    
    static let pastel = RoutePalette(
        backgroundColor: Color.black,
        warm: Color(red: 1.00, green: 0.70, blue: 0.55),
        cool: Color(red: 0.65, green: 0.80, blue: 0.98),
        highlight: Color.white,
        glow: Color.white.opacity(0.92)
    )
    
    static let mono = RoutePalette(
        backgroundColor: Color.black,
        warm: Color(red: 0.90, green: 0.92, blue: 1.0),
        cool: Color(red: 0.65, green: 0.78, blue: 1.0),
        highlight: Color.white,
        glow: Color.white.opacity(0.92)
    )
    
    let backgroundColor: Color
    let warm: Color
    let cool: Color
    let highlight: Color
    let glow: Color
}

struct RouteScene {
    static func build(from coordinates: [CLLocation], palette: RoutePalette = .dark) -> [CGPoint] {
        guard !coordinates.isEmpty else { return [] }

        let latitudes = coordinates.map { $0.coordinate.latitude }
        let longitudes = coordinates.map { $0.coordinate.longitude }

        let latMin = latitudes.min() ?? 0
        let latMax = latitudes.max() ?? 0
        let lonMin = longitudes.min() ?? 0
        let lonMax = longitudes.max() ?? 0

        let latRange = max(latMax - latMin, 0.0001)
        let lonRange = max(lonMax - lonMin, 0.0001)

        let points = coordinates.map { coordinate -> CGPoint in
            let nx = (coordinate.coordinate.longitude - lonMin) / lonRange
            let ny = 1 - ((coordinate.coordinate.latitude - latMin) / latRange)
            return CGPoint(x: nx, y: ny)
        }

        return points
    }
}

struct FluidRouteView: View {
    let coordinates: [CLLocation]
    let palette: RoutePalette

    init(coordinates: [CLLocation], palette: RoutePalette = .dark) {
        self.coordinates = coordinates
        self.palette = palette
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let routePoints = RouteScene.build(from: coordinates, palette: palette)

            Canvas { graphicsContext, size in
                let drawPoints = routePoints.map { point in
                    CGPoint(
                        x: point.x * size.width * 0.72 + size.width * 0.14,
                        y: point.y * size.height * 0.72 + size.height * 0.14
                    )
                }

                guard !drawPoints.isEmpty else { return }

                for layer in 0..<6 {
                    let amplitude = 1.8 + Double(layer) * 1.1
                    let phase = t * (0.8 + Double(layer) * 0.18)
                    let path = makeFluidPath(points: drawPoints, amplitude: amplitude, phase: phase)

                    let alpha = 0.18 + Double(6 - layer) * 0.09
                    let width = 12 + CGFloat(layer) * 5.5

                    graphicsContext.stroke(
                        path,
                        with: .color(colorForLayer(layer: layer, alpha: alpha)),
                        lineWidth: width
                    )

                    graphicsContext.stroke(
                        path,
                        with: .color(colorForLayer(layer: layer, alpha: 0.8)),
                        lineWidth: max(1.2, width * 0.18)
                    )
                }

                let corePath = makeFluidPath(points: drawPoints, amplitude: 1.2, phase: t * 1.1)
                graphicsContext.stroke(
                    corePath,
                    with: .color(palette.highlight.opacity(0.98)),
                    lineWidth: 1.8
                )

                let end = drawPoints.last ?? CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let glowDot = Circle().fill(palette.highlight.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .position(x: end.x, y: end.y)
                graphicsContext.draw(glowDot, at: end)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.backgroundColor)
        }
    }

    private func colorForLayer(layer: Int, alpha: Double) -> Color {
        let t = Double(layer) / 5.0
        let warm = palette.warm.opacity(alpha)
        let cool = palette.cool.opacity(alpha)
        return mixColor(from: warm, to: cool, t: t)
    }

    private func mixColor(from left: Color, to right: Color, t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let start = left.sRGBColor
        let end = right.sRGBColor

        let r = Double(start.red) + (Double(end.red) - Double(start.red)) * clamped
        let g = Double(start.green) + (Double(end.green) - Double(start.green)) * clamped
        let b = Double(start.blue) + (Double(end.blue) - Double(start.blue)) * clamped
        return Color(red: r, green: g, blue: b)
    }

    private func makeFluidPath(points: [CGPoint], amplitude: Double, phase: Double) -> Path {
        guard points.count > 1 else {
            return Path()
        }

        var path = Path()
        var warped: [CGPoint] = []

        for (index, point) in points.enumerated() {
            let p = Double(index) / max(Double(points.count - 1), 1.0)
            let previous = index == 0 ? point : points[index - 1]
            let next = index == points.count - 1 ? point : points[index + 1]

            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let angle = atan2(dy, dx)
            let normalX = -sin(angle)
            let normalY = cos(angle)

            let wave = sin(p * 26.0 + phase * 1.8) * amplitude + cos(p * 14.0 - phase * 1.2) * (amplitude * 0.55)
            let offsetX = normalX * CGFloat(wave)
            let offsetY = normalY * CGFloat(wave)

            warped.append(CGPoint(x: point.x + offsetX, y: point.y + offsetY))
        }

        guard let first = warped.first else { return path }
        path.move(to: first)

        for i in 1..<warped.count {
            let prev = warped[i - 1]
            let current = warped[i]
            let mid = CGPoint(x: (prev.x + current.x) * 0.5, y: (prev.y + current.y) * 0.5)
            path.addQuadCurve(to: mid, control: prev)
            path.addQuadCurve(to: current, control: mid)
        }

        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FluidRouteView(coordinates: SampleRoute.potreroHill)
            .frame(width: 360, height: 360)
            .padding()
    }
}
