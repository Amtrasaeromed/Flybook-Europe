import SwiftUI
import MapKit

enum DestinationMapPresentation {
    case europe
    case airportAerial
}

struct DestinationMapView: NSViewRepresentable {
    let latitude: Double?
    let longitude: Double?
    let title: String
    var presentation: DestinationMapPresentation = .europe

    final class Coordinator: NSObject, MKMapViewDelegate {
        var displayedLocationKey: String?

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }

            return MKTileOverlayRenderer(
                tileOverlay: tileOverlay
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        configureAppearance(of: map)
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
        let locationKey =
            "\(presentation)-"
            + "\(latitude ?? 999)-"
            + "\(longitude ?? 999)"

        guard
            context.coordinator.displayedLocationKey
                != locationKey
        else {
            return
        }

        context.coordinator.displayedLocationKey =
            locationKey
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

        if presentation == .europe {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = title
            map.addAnnotation(annotation)
        }

        map.setRegion(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta:
                        presentation == .airportAerial
                            ? 0.025
                            : 8,
                    longitudeDelta:
                        presentation == .airportAerial
                            ? 0.04
                            : 12
                )
            ),
            animated: false
        )
    }

    private func configureAppearance(
        of map: MKMapView
    ) {
        guard presentation == .airportAerial else {
            map.mapType = .mutedStandard
            return
        }

        map.mapType = .standard
        let imagery = MKTileOverlay(
            urlTemplate:
                "https://server.arcgisonline.com/ArcGIS/"
                + "rest/services/World_Imagery/MapServer/"
                + "tile/{z}/{y}/{x}"
        )
        imagery.canReplaceMapContent = true
        imagery.minimumZ = 3
        imagery.maximumZ = 19
        map.addOverlay(imagery, level: .aboveLabels)
    }
}
