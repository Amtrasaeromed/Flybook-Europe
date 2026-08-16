import Foundation

enum ImageCatalog {
    static func missingRegionalImages(for destinations: [Destination]) -> [Destination] {
        destinations.filter { destination in
            FlybookResources.bundle.url(
                forResource: destination.regionalImageName,
                withExtension: "jpg",
                subdirectory: "regions"
            ) == nil
            && FlybookResources.bundle.url(
                forResource: destination.regionalImageName,
                withExtension: "webp",
                subdirectory: "regions"
            ) == nil
            && FlybookResources.bundle.url(
                forResource: destination.regionalImageName,
                withExtension: "png",
                subdirectory: "regions"
            ) == nil
        }
    }
}
