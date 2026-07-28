import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var showKey = false

    var body: some View {
        NavigationSplitView {
            List(model.destinations, selection: $model.selectedICAO) { destination in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.name).fontWeight(.semibold)
                        Text(destination.id).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if destination.approved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    Text("\(destination.candidateURLs.count)/3").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(destination.id)
            }
            .navigationTitle("35 Ziele")
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let destination = model.selectedDestination {
                    destinationDetail(destination)
                } else {
                    emptySelectionView
                }
            }
        }
        .alert("Flybook Image Studio", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Kein Ziel ausgewählt")
                .font(.title3.weight(.semibold))
            Text("Wähle links eines der 35 Ziele aus.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                SecureField("OpenAI API-Schlüssel hier einfügen", text: $model.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isGenerating)
                Button(model.hasStoredKey ? "Schlüssel ersetzen" : "Schlüssel speichern") { model.saveAPIKey() }
                    .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGenerating)
                Button("Löschen", role: .destructive) { model.deleteAPIKey() }
                    .disabled(!model.hasStoredKey || model.isGenerating)
                Label(model.hasStoredKey ? "Im Schlüsselbund gespeichert" : "Kein Schlüssel gespeichert", systemImage: model.hasStoredKey ? "lock.fill" : "lock.open")
                    .font(.caption)
                    .foregroundStyle(model.hasStoredKey ? .green : .secondary)
            }
            HStack(spacing: 12) {
                Button {
                    model.isGenerating ? model.stopGeneration() : model.startGeneration()
                } label: {
                    Label(model.isGenerating ? "Stoppen" : "Alle Bilder erzeugen", systemImage: model.isGenerating ? "stop.fill" : "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasStoredKey && !model.isGenerating)

                ProgressView(value: model.progressValue).frame(maxWidth: 280)
                Text(model.progressText).font(.caption).lineLimit(1)
                Spacer()
                Button("Ordner öffnen") { model.openCandidatesFolder() }
                Button("35 Favoriten übernehmen") { model.approveAndCopy() }
            }
        }
        .padding(14)
    }

    private func destinationDetail(_ destination: StudioDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(destination.name).font(.system(size: 28, weight: .bold))
                        Text(destination.id).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Freigegeben", isOn: Binding(
                        get: { destination.approved },
                        set: { model.toggleApproval(for: destination.id, value: $0) }
                    ))
                    .toggleStyle(.switch)
                }

                HStack(alignment: .top, spacing: 16) {
                    ForEach(1...3, id: \.self) { number in
                        candidateCard(destination: destination, number: number)
                    }
                }

                GroupBox("Protokoll") {
                    ScrollView {
                        Text(model.logText.isEmpty ? "Noch keine Generierung in dieser Sitzung gestartet." : model.logText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 150, maxHeight: 230)
                }
            }
            .padding(20)
        }
    }

    private func candidateCard(destination: StudioDestination, number: Int) -> some View {
        let url = destination.candidateURLs.first { candidateNumber(from: $0) == number }
        let selected = destination.selectedCandidate == number
        return VStack(spacing: 10) {
            Group {
                if let url, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        VStack { Image(systemName: "photo.badge.plus").font(.largeTitle); Text("Noch nicht erzeugt").font(.caption) }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: .infinity, minHeight: 200, idealHeight: 250, maxHeight: 300)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1))

            if selected {
                Button("Favorit \(number)") {
                    model.chooseCandidate(number, for: destination.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(url == nil)
            } else {
                Button("Als Favorit wählen") {
                    model.chooseCandidate(number, for: destination.id)
                }
                .buttonStyle(.bordered)
                .disabled(url == nil)
            }
        }
    }

    private func candidateNumber(from url: URL) -> Int? {
        Int(url.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "")
    }
}
