import CoreLocation

enum SampleRoute {
    static var potreroHill: [CLLocation] {
        let startLat = 37.7655
        let startLon = -122.4025
        
        return (0...120).map { i in
            let angle = Double(i) * 0.18
            let radius = 0.000045 * Double(i)
            let lat = startLat + radius * cos(angle)
            let lon = startLon + radius * sin(angle)
            let alt = 20.0 + sin(Double(i) * 0.1) * 15.0 + Double(i) * 0.3 // Rolling hills
            
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: alt,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: Date()
            )
        }
    }
}
