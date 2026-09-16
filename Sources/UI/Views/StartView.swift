import SwiftUI
import UniformTypeIdentifiers

public struct StartView: View {
    @ObservedObject var appState: AppState
    private let hardware = HardwareCapabilities()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "camera.macro")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)

                Text("WeddingCull")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .accessibilityIdentifier(AccessibilityIdentifiers.startTitle)

                Text("Seleziona automaticamente le fotografie migliori del matrimonio.\nTutto rimane sul tuo Mac.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 500)
            }

            // Local privacy badge
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("100% Locale · Nessun dato lascia il tuo Mac · Nessun account richiesto")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(20)

            // Hardware profile badge
            HStack(spacing: 6) {
                Image(systemName: hardware.isAppleSilicon ? "cpu.fill" : "laptopcomputer")
                if hardware.isAppleSilicon {
                    Text("Profilo Avanzato · Apple Silicon (\(hardware.cpuArchitecture))")
                } else {
                    Text("Profilo Base · Intel (\(hardware.cpuArchitecture))")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Primary & Secondary Action Buttons
            VStack(spacing: 14) {
                Button(action: selectFolder) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Importa matrimonio")
                            .fontWeight(.semibold)
                    }
                    .frame(width: 240, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier(AccessibilityIdentifiers.importButton)

                Button(action: openSession) {
                    HStack {
                        Image(systemName: "doc.badge.arrow.up")
                        Text("Apri sessione")
                    }
                    .frame(width: 240, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.openSessionButton)
            }

            Spacer()
        }
        .frame(minWidth: 700, minHeight: 500)
        .padding()
    }

    private func selectFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Seleziona cartella matrimonio"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let url = openPanel.url {
            appState.startAnalysis(folderURL: url)
        }
    }

    private func openSession() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Apri sessione WeddingCull"
        openPanel.showsResizeIndicator = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            try? appState.loadSession(from: url)
        }
    }
}
