import Foundation

enum FlybookResources {
    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent(
                "FlybookEurope_FlybookEurope.bundle",
                isDirectory: true
            ),
           let bundledResources = Bundle(url: resourceURL) {
            return bundledResources
        }

        return Bundle.module
    }()
}
