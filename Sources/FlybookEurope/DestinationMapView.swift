import SwiftUI
import MapKit
import Foundation

enum DestinationMapPresentation {
    case europe
    case airportAerial
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
