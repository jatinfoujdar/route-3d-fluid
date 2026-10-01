import SceneKit
import UIKit

// MARK: - SCNVector3 Helpers
extension SCNVector3 {
    func distance(to vector: SCNVector3) -> Float {
        return sqrt(pow(vector.x - x, 2) + pow(vector.y - y, 2) + pow(vector.z - z, 2))
    }
    
    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
    
    static func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }
    
    static func / (lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        return SCNVector3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }
    
    func length() -> Float {
        return sqrt(x * x + y * y + z * z)
    }
}

// MARK: - CGSize Helpers
extension CGSize {
    static func aspectFit(aspectRatio: CGSize, boundingSize: CGSize) -> CGSize {
        let widthRatio = boundingSize.width / aspectRatio.width
        let heightRatio = boundingSize.height / aspectRatio.height
        let minRatio = min(widthRatio, heightRatio)
        return CGSize(width: aspectRatio.width * minRatio, height: aspectRatio.height * minRatio)
    }
}
