import MapKit
import SwiftUI

struct IPadRouteMapWaypoint: Identifiable, Equatable {
    enum Role: Equatable {
        case departure
        case stop
        case virtualStop
        case arrival
    }

    let id = UUID()
    let title: String
    let latitude: Double
    let longitude: Double
    let role: Role

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct IPadRouteMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let waypoints: [IPadRouteMapWaypoint]

    var body: some View {
        ZStack(alignment: .top) {
            IPadRouteMapView(waypoints: waypoints)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.dashboardBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("STRECKENKARTE")
                        .font(.headline.bold())
                        .foregroundStyle(Color.dashboardNavy)
                    Text(waypoints.map(\.title).joined(separator: "  →  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.dashboardNavy)
                        .frame(width: 38, height: 38)
                        .background(Color.white, in: Circle())
                        .overlay {
                            Circle().stroke(Color.dashboardNavy.opacity(0.22), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Streckenkarte schließen")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 58)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

private struct IPadRouteMapView: UIViewRepresentable {
    let waypoints: [IPadRouteMapWaypoint]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let annotations = waypoints.map(RouteAnnotation.init)
        map.addAnnotations(annotations)

        let coordinates = waypoints.map(\.coordinate)
        guard coordinates.count >= 2 else { return }
        let route = MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(route)

        let padding = UIEdgeInsets(top: 105, left: 70, bottom: 70, right: 70)
        map.setVisibleMapRect(route.boundingMapRect, edgePadding: padding, animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(red: 0.03, green: 0.22, blue: 0.40, alpha: 0.92)
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let routeAnnotation = annotation as? RouteAnnotation else { return nil }
            let identifier = "FlybookRouteWaypoint"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: routeAnnotation, reuseIdentifier: identifier)
            view.annotation = routeAnnotation
            view.canShowCallout = true
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .hidden

            switch routeAnnotation.role {
            case .departure:
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "airplane.departure")
            case .stop:
                view.markerTintColor = .systemOrange
                view.glyphImage = UIImage(systemName: "fuelpump.fill")
            case .virtualStop:
                view.markerTintColor = .systemTeal
                view.glyphImage = UIImage(systemName: "circle.dashed")
            case .arrival:
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "airplane.arrival")
            }
            return view
        }
    }
}

private final class RouteAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let role: IPadRouteMapWaypoint.Role

    init(waypoint: IPadRouteMapWaypoint) {
        coordinate = waypoint.coordinate
        title = waypoint.title
        role = waypoint.role
    }
}
