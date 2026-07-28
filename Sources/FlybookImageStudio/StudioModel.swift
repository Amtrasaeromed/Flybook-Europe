import AppKit
import Foundation
import SwiftUI

struct StudioDestination: Identifiable, Hashable {
    let id: String
    let name: String
    var selectedCandidate: Int
    var approved: Bool
    var notes: String
    var candidateURLs: [URL]
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var destinations: [StudioDestination] = []
    @Published var selectedICAO: String?
    @Published var apiKeyInput = ""
    @Published var hasStoredKey = false
    @Published var isGenerating = false
    @Published var progressValue = 0.0
    @Published var progressText = "Bereit"
    @Published var logText = ""
    @Published var alertMessage: String?

    private let keychain = KeychainStore()
    private var generationProcess: Process?

    /// Resolves the checked-out Swift-package root independently of Xcode's
    /// current working directory. Xcode normally launches package executables
    /// from DerivedData, so relying only on `currentDirectoryPath` is unsafe.
    let rootURL: URL = {
        let fileManager = FileManager.default

        func isProjectRoot(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) &&
            fileManager.fileExists(atPath: url.appendingPathComponent("Sources/FlybookEurope/Resources/Flybook_Master.csv").path) &&
            fileManager.fileExists(atPath: url.appendingPathComponent("Tools/generate_destination_images.py").path)
        }

        var candidates: [URL] = []

        // Works when launched through the provided .command file or `swift run`.
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))

        // Reliable when launched from Xcode: #filePath points into
        // <project>/Sources/FlybookImageStudio/StudioModel.swift.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FlybookImageStudio
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // package root
        candidates.append(sourceRoot)

        // Useful for a locally built executable placed beside the project.
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())

        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            if isProjectRoot(standardized) { return standardized }
        }

        // Return the source-derived location so any later error includes the
        // most useful expected path rather than a DerivedData directory.
        return sourceRoot.standardizedFileURL
    }()

    var selectedDestination: StudioDestination? {
        guard let selectedICAO else { return destinations.first }
        return destinations.first(where: { $0.id == selectedICAO })
    }

    func reload() {
        do {
            hasStoredKey = try keychain.read() != nil
            destinations = try loadDestinations()
            if selectedICAO == nil { selectedICAO = destinations.first?.id }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20 else {
            alertMessage = "Der eingegebene Schlüssel ist zu kurz. Bitte den vollständigen Secret Key einfügen."
            return
        }
        do {
            try keychain.save(key)
            apiKeyInput = ""
            hasStoredKey = true
            alertMessage = "Der API-Schlüssel wurde sicher im macOS-Schlüsselbund gespeichert."
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteAPIKey() {
        do {
            try keychain.delete()
            hasStoredKey = false
            alertMessage = "Der gespeicherte API-Schlüssel wurde gelöscht."
        } catch { alertMessage = error.localizedDescription }
    }

    func startGeneration() {
        guard !isGenerating else { return }
        do {
            guard let key = try keychain.read(), !key.isEmpty else {
                alertMessage = "Bitte zuerst einen OpenAI-API-Schlüssel speichern."
                return
            }
            let script = rootURL.appendingPathComponent("Tools/generate_destination_images.py")
            guard FileManager.default.fileExists(atPath: script.path) else {
                throw NSError(domain: "FlybookImageStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generatorskript nicht gefunden: \(script.path)"])
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script.path]
            process.currentDirectoryURL = rootURL
            var environment = ProcessInfo.processInfo.environment
            environment["OPENAI_API_KEY"] = key
            environment["PYTHONUNBUFFERED"] = "1"
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.consumeOutput(text) }
            }
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    self?.generationProcess = nil
                    self?.isGenerating = false
                    self?.progressText = process.terminationStatus == 0 ? "Generierung abgeschlossen" : "Generierung mit Fehler beendet"
                    self?.reload()
                }
            }
            generationProcess = process
            isGenerating = true
            progressValue = 0
            progressText = "Generierung wird gestartet …"
            logText = ""
            try process.run()
        } catch {
            isGenerating = false
            alertMessage = error.localizedDescription
        }
    }

    func stopGeneration() {
        generationProcess?.terminate()
        progressText = "Abbruch angefordert – vorhandene Bilder bleiben erhalten"
    }

    func chooseCandidate(_ candidate: Int, for icao: String) {
        guard let index = destinations.firstIndex(where: { $0.id == icao }) else { return }
        destinations[index].selectedCandidate = candidate
        destinations[index].approved = true
        saveSelections()
    }

    func toggleApproval(for icao: String, value: Bool) {
        guard let index = destinations.firstIndex(where: { $0.id == icao }) else { return }
        destinations[index].approved = value
        saveSelections()
    }

    func approveAndCopy() {
        let approved = destinations.filter(\.approved)
        guard approved.count == 35 else {
            alertMessage = "Es müssen exakt 35 Ziele freigegeben sein. Aktuell freigegeben: \(approved.count)."
            return
        }
        do {
            let targetDir = rootURL.appendingPathComponent("Sources/FlybookEurope/Resources/regions", isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            for destination in approved {
                guard let source = destination.candidateURLs.first(where: { candidateNumber(from: $0) == destination.selectedCandidate }) else {
                    throw NSError(domain: "FlybookImageStudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Gewähltes Bild fehlt für \(destination.id)."])
                }
                let target = targetDir.appendingPathComponent("\(destination.id).\(source.pathExtension.lowercased())")
                for ext in ["jpg", "jpeg", "png", "webp"] where ext != source.pathExtension.lowercased() {
                    try? FileManager.default.removeItem(at: targetDir.appendingPathComponent("\(destination.id).\(ext)"))
                }
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
            }
            saveSelections()
            alertMessage = "Alle 35 freigegebenen Bilder wurden in die Flybook-Ressourcen übernommen."
        } catch { alertMessage = error.localizedDescription }
    }

    func openCandidatesFolder() {
        NSWorkspace.shared.open(rootURL.appendingPathComponent("ImageProduction/Candidates", isDirectory: true))
    }

    private func consumeOutput(_ text: String) {
        logText.append(text)
        if logText.count > 40_000 { logText.removeFirst(logText.count - 40_000) }
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("[") && line.contains("]") { progressText = line }
            if line.contains("candidate") && (line.contains("✓") || line.contains("✗") || line.contains("already exists")) {
                let completed = logText.components(separatedBy: "candidate").count - 1
                progressValue = min(Double(completed) / 105.0, 1.0)
            }
        }
    }

    private func loadDestinations() throws -> [StudioDestination] {
        let csvURL = rootURL.appendingPathComponent("Sources/FlybookEurope/Resources/Flybook_Master.csv")
        guard FileManager.default.fileExists(atPath: csvURL.path) else {
            throw NSError(
                domain: "FlybookImageStudio",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Flybook_Master.csv wurde im Projekt nicht gefunden. Erwarteter Pfad: \(csvURL.path)"]
            )
        }
        let text = try String(contentsOf: csvURL, encoding: .utf8)
        let rows = SimpleCSV.parse(text)
        guard let header = rows.first, let icaoIndex = header.firstIndex(of: "ICAO"), let nameIndex = header.firstIndex(of: "Ziel") else {
            throw NSError(domain: "FlybookImageStudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Flybook_Master.csv hat keine Spalten ICAO/Ziel."])
        }
        let saved = loadSelections()
        let candidateRoot = rootURL.appendingPathComponent("ImageProduction/Candidates", isDirectory: true)
        let loaded: [StudioDestination] = rows.dropFirst().compactMap { row -> StudioDestination? in
            guard row.indices.contains(icaoIndex), row.indices.contains(nameIndex) else { return nil }
            let icao = row[icaoIndex].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !icao.isEmpty else { return nil }
            let folder = candidateRoot.appendingPathComponent(icao, isDirectory: true)
            let urls = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let selection = saved[icao]
            return StudioDestination(
                id: icao,
                name: row[nameIndex],
                selectedCandidate: selection?.candidate ?? 1,
                approved: selection?.approved ?? false,
                notes: selection?.notes ?? "",
                candidateURLs: urls
            )
        }
        guard loaded.count == 35 else {
            throw NSError(
                domain: "FlybookImageStudio",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Es wurden \(loaded.count) statt exakt 35 Ziele aus Flybook_Master.csv geladen."]
            )
        }
        return loaded
    }

    private func candidateNumber(from url: URL) -> Int? {
        let stem = url.deletingPathExtension().lastPathComponent
        return Int(stem.split(separator: "_").last ?? "")
    }

    private typealias SavedSelection = (candidate: Int, approved: Bool, notes: String)

    private func loadSelections() -> [String: SavedSelection] {
        let url = rootURL.appendingPathComponent("ImageProduction/selections.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let rows = SimpleCSV.parse(text)
        guard let header = rows.first else { return [:] }
        func idx(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let i = idx("icao"), let c = idx("candidate"), let a = idx("approved") else { return [:] }
        let n = idx("notes")
        var result: [String: SavedSelection] = [:]
        for row in rows.dropFirst() where row.indices.contains(i) {
            let icao = row[i].uppercased()
            let candidate = row.indices.contains(c) ? Int(row[c]) ?? 1 : 1
            let approved = row.indices.contains(a) && ["yes", "true", "1", "ja"].contains(row[a].lowercased())
            let notes = n.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            result[icao] = (candidate, approved, notes)
        }
        return result
    }

    private func saveSelections() {
        let url = rootURL.appendingPathComponent("ImageProduction/selections.csv")
        var output = "icao,destination,candidate,approved,notes\n"
        for destination in destinations {
            let fields = [destination.id, destination.name, String(destination.selectedCandidate), destination.approved ? "yes" : "no", destination.notes]
            output += fields.map(SimpleCSV.escape).joined(separator: ",") + "\n"
        }
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}

private enum SimpleCSV {
    static func parse(_ input: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let scalars = Array(input.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" { field.unicodeScalars.append(scalar); index += 1 }
                    else { quoted = false }
                } else { field.unicodeScalars.append(scalar) }
            } else {
                switch scalar {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r":
                    row.append(field); rows.append(row); row = []; field = ""
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                default: field.unicodeScalars.append(scalar)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
