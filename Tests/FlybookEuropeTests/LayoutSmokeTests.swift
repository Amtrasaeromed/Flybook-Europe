import AppKit
import SwiftUI
import XCTest
@testable import FlybookEurope

@MainActor
final class LayoutSmokeTests: XCTestCase {
    func testDestinationPageRendersAtReferenceSize() throws {
        let store = DestinationStore()
        guard let destination = store.destinations.first(where: { $0.icao == "EDKA" }) else {
            return XCTFail("EDKA fehlt in den Masterdaten")
        }
        let origins = [AirportReference.edfz] + store.destinations.compactMap { airport in
            guard airport.icao != "EDFZ",
                  let latitude = airport.latitude,
                  let longitude = airport.longitude else { return nil }
            return AirportReference(
                icao: airport.icao,
                name: airport.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: airport.elevationFeet,
                timeZone: DestinationTimeZone.value(for: airport, weatherTimeZone: nil)
            )
        }
        let view = DestinationPage(
            destination: destination,
            availableDestinations: store.destinations,
            availableOrigins: origins
        )
        .frame(width: 1800, height: 1200)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("SwiftUI-Seite konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-layout-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 1800)
        XCTAssertEqual(Int(image.size.height), 1200)
    }
}
