import SwiftUI
import SceneKit
import CoreLocation

struct Route3DView: UIViewRepresentable {
    var coordinates: [CLLocation]
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        
        if let routeScene = RouteScene.build(from: coordinates) {
            scnView.scene = routeScene.scene
            scnView.isPlaying = true
        }
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        Route3DView(coordinates: SampleRoute.potreroHill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
