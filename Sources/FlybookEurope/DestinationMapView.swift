import SwiftUI
import MapKit

struct DestinationMapView: NSViewRepresentable {
    let latitude: Double?
    let longitude: Double?
    let title: String

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .mutedStandard
        map.showsCompass = false
        map.showsScale = false
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateNSView(
        _ map: MKMapView,
        context: Context
    ) {
        map.removeAnnotations(map.annotations)

        guard
            let latitude,
            let longitude
        else {
            map.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: 50.5,
                        longitude: 10.0
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: 22,
                        longitudeDelta: 30
                    )
                ),
                animated: false
            )
            return
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = title
        map.addAnnotation(annotation)

        map.setRegion(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 8,
                    longitudeDelta: 12
                )
            ),
            animated: false
        )
    }
}
