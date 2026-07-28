import Foundation

enum ImageCatalog {
    static func missingRegionalImages(for destinations: [Destination]) -> [Destination] {
        destinations.filter { destination in
            Bundle.module.url(
                forResource: destination.regionalImageName,
                withExtension: "jpg",
                subdirectory: "regions"
            ) == nil
            && Bundle.module.url(
                forResource: destination.regionalImageName,
                withExtension: "webp",
                subdirectory: "regions"
            ) == nil
            && Bundle.module.url(
                forResource: destination.regionalImageName,
                withExtension: "png",
                subdirectory: "regions"
            ) == nil
        }
    }
}
