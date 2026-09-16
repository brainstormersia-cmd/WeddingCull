import SwiftUI

public struct ExportDialogView: View {
    @ObservedObject var appState: AppState
    @State private var folderStructure: ExportFolderStructure = .singleFolder
    @State private var rawHandling: ExportRawHandling = .rawAndJpegPair
    @State private var destinationURL: URL? = nil
    @State private var isExporting: Bool = false
    @State private var exportProgress: (current: Int, total: Int) = (0, 0)
    @State private var exportSummary: String? = nil

    private let exporter = PhotoExporter()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Esporta fotografie selezionate")
                .font(.title2)
                .fontWeight(.bold)

            let selectedCount = appState.session.photos.filter { $0.selectionState.isIncludedInFinal }.count
            Text("\(selectedCount) fotografie pronte per l'esportazione")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            Form {
                Picker("Struttura cartelle", selection: $folderStructure) {
                    ForEach(ExportFolderStructure.allCases, id: \.self) { structure in
                        Text(structure.displayName).tag(structure)
                    }
                }

                Picker("Gestione RAW / JPEG", selection: $rawHandling) {
                    ForEach(ExportRawHandling.allCases, id: \.self) { handling in
                        Text(handling.displayName).tag(handling)
                    }
                }

                HStack {
                    Text("Cartella destinazione:")
                    Spacer()
                    if let dest = destinationURL {
                        Text(dest.lastPathComponent)
                            .fontWeight(.medium)
                    } else {
                        Text("Nessuna cartella scelta")
                            .foregroundColor(.secondary)
                    }
                    Button("Scegli...") {
                        selectDestination()
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.exportDestinationFolder)
                }
            }
            .padding(.horizontal)

            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: Double(exportProgress.current), total: Double(max(1, exportProgress.total)))
                        .frame(width: 300)
                    Text("Copia file originali: \(exportProgress.current) / \(exportProgress.total)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            if let summary = exportSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding()
            }

            Divider()

            HStack {
                Button("Chiudi") {
                    appState.isExportSheetPresented = false
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.exportCancelButton)

                Spacer()

                Button("Avvia esportazione") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationURL == nil || isExporting || selectedCount == 0)
                .accessibilityIdentifier(AccessibilityIdentifiers.exportConfirmButton)
            }
            .padding(.horizontal)
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }

    private func selectDestination() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Scegli cartella di esportazione"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let url = openPanel.url {
            destinationURL = url
        }
    }

    private func startExport() {
        guard let dest = destinationURL else { return }
        isExporting = true

        Task {
            do {
                let result = try exporter.exportSelection(
                    items: appState.session.photos,
                    to: dest,
                    folderStructure: folderStructure,
                    rawHandling: rawHandling
                ) { current, total in
                    Task { @MainActor in
                        exportProgress = (current, total)
                    }
                }

                Task { @MainActor in
                    isExporting = false
                    exportSummary = "Esportazione completata con successo (\(result.exportedCount) file salvati)."
                }
            } catch {
                Task { @MainActor in
                    isExporting = false
                    exportSummary = "Errore durante l'esportazione: \(error.localizedDescription)"
                }
            }
        }
    }
}
