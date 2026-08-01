import SwiftUI
import MapKit
import Foundation

enum DestinationMapPresentation {
    case europe
    case airportAerial
}

private final class RouteAirportAnnotation: MKPointAnnotation {
    enum Role {
        case origin
        case intermediate
        case destination
    }

    let role: Role

    init(role: Role) {
        self.role = role
        super.init()
    }
}

final class YearlyCachedTileOverlay: MKTileOverlay {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    override init(urlTemplate: String?) {
        let applicationSupport =
            try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        cacheDirectory = (applicationSupport
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(
                "FlybookEurope/AerialTiles",
                isDirectory: true
            )
        super.init(urlTemplate: urlTemplate)
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let localURL = cacheDirectory.appendingPathComponent(
            "\(path.z)-\(path.x)-\(path.y)-"
                + "\(Int(path.contentScaleFactor)).tile"
        )

        if isFresh(localURL),
           let data = try? Data(contentsOf: localURL)
        {
            result(data, nil)
            return
        }

        let remoteURL = url(forTilePath: path)

        URLSession.shared.dataTask(with: remoteURL) {
            data, response, error in
            let statusCode =
                (response as? HTTPURLResponse)?.statusCode
            if let data,
               statusCode.map({ 200...299 ~= $0 }) ?? true
            {
                try? data.write(to: localURL, options: .atomic)
                result(data, nil)
                return
            }

            if let staleData = try? Data(contentsOf: localURL) {
                result(staleData, nil)
            } else {
                result(nil, error ?? URLError(.badServerResponse))
            }
        }.resume()
    }

    private func isFresh(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ),
            let modificationDate = values.contentModificationDate,
            let refreshDate = Calendar.current.date(
                byAdding: .month,
                value: 12,
                to: modificationDate
            )
        else {
            return false
        }
        return Date() < refreshDate
    }
}

struct DestinationMapView: NSViewRepresentable {
    let latitude: Double?
    let longitude: Double?
    let title: String
    var originLatitude: Double? = nil
    var originLongitude: Double? = nil
    var originTitle: String? = nil
    var intermediateLatitude: Double? = nil
    var intermediateLongitude: Double? = nil
    var intermediateTitle: String? = nil
    var presentation: DestinationMapPresentation = .europe

    final class Coordinator: NSObject, MKMapViewDelegate {
        var displayedLocationKey: String?
        var routeOverlay: MKPolyline?

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if let route = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = NSColor(
                    red: 0.02,
                    green: 0.20,
                    blue: 0.38,
                    alpha: 0.9
                )
                renderer.lineWidth = 3
                return renderer
            }

            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard let routeAnnotation =
                annotation as? RouteAirportAnnotation
            else { return nil }

            let identifier = "route-airport-\(routeAnnotation.role)"
            let marker =
                mapView.dequeueReusableAnnotationView(
                    withIdentifier: identifier
                ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: routeAnnotation,
                    reuseIdentifier: identifier
                )
            marker.annotation = routeAnnotation
            marker.canShowCallout = true
            marker.displayPriority = .required
            marker.glyphTintColor = .white

            switch routeAnnotation.role {
            case .origin:
                marker.markerTintColor = NSColor(
                    red: 0.08,
                    green: 0.31,
                    blue: 0.52,
                    alpha: 1
                )
                marker.glyphImage = NSImage(
                    systemSymbolName: "house.fill",
                    accessibilityDescription: "Abflugplatz"
                )
            case .intermediate:
                marker.markerTintColor = .systemOrange
                marker.glyphImage = NSImage(
                    systemSymbolName: "circle.fill",
                    accessibilityDescription: "Zwischenstopp"
                )
            case .destination:
                marker.markerTintColor = .systemRed
                marker.glyphImage = NSImage(
                    systemSymbolName: "flag.fill",
                    accessibilityDescription: "Zielflugplatz"
                )
            }
            return marker
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
            + "\(longitude ?? 999)-"
            + "\(originLatitude ?? 999)-"
            + "\(originLongitude ?? 999)-"
            + "\(intermediateLatitude ?? 999)-"
            + "\(intermediateLongitude ?? 999)"

        guard
            context.coordinator.displayedLocationKey
                != locationKey
        else {
            return
        }

        context.coordinator.displayedLocationKey =
            locationKey
        map.removeAnnotations(map.annotations)
        if let route = context.coordinator.routeOverlay {
            map.removeOverlay(route)
            context.coordinator.routeOverlay = nil
        }

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
            let destinationAnnotation =
                RouteAirportAnnotation(role: .destination)
            destinationAnnotation.coordinate = coordinate
            destinationAnnotation.title = title
            map.addAnnotation(destinationAnnotation)

            if let originLatitude, let originLongitude {
                let originCoordinate = CLLocationCoordinate2D(
                    latitude: originLatitude,
                    longitude: originLongitude
                )
                let originAnnotation =
                    RouteAirportAnnotation(role: .origin)
                originAnnotation.coordinate = originCoordinate
                originAnnotation.title = originTitle
                map.addAnnotation(originAnnotation)

                var coordinates = [originCoordinate]

                if let intermediateLatitude,
                   let intermediateLongitude
                {
                    let intermediateCoordinate =
                        CLLocationCoordinate2D(
                            latitude: intermediateLatitude,
                            longitude: intermediateLongitude
                        )
                    let intermediateAnnotation =
                        RouteAirportAnnotation(role: .intermediate)
                    intermediateAnnotation.coordinate =
                        intermediateCoordinate
                    intermediateAnnotation.title = intermediateTitle
                    map.addAnnotation(intermediateAnnotation)
                    coordinates.append(intermediateCoordinate)
                }

                coordinates.append(coordinate)
                let route = MKPolyline(
                    coordinates: &coordinates,
                    count: coordinates.count
                )
                context.coordinator.routeOverlay = route
                map.addOverlay(route, level: .aboveRoads)
            }
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

        if let route = context.coordinator.routeOverlay {
            map.setVisibleMapRect(
                route.boundingMapRect,
                edgePadding: NSEdgeInsets(
                    top: 55,
                    left: 55,
                    bottom: 55,
                    right: 55
                ),
                animated: false
            )
        }
    }

    private func configureAppearance(
        of map: MKMapView
    ) {
        guard presentation == .airportAerial else {
            map.mapType = .mutedStandard
            return
        }

        map.mapType = .standard
        let imagery = YearlyCachedTileOverlay(
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
