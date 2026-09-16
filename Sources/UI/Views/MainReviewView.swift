import SwiftUI

public struct MainReviewView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            PhotoGridView(appState: appState)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            InspectorView(appState: appState)
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 350)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: saveCurrentSession) {
                    Label("Salva sessione", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItem(placement: .principal) {
                TargetCountControl(appState: appState)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.isExportSheetPresented = true }) {
                    Label("Esporta", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityIdentifiers.exportButton)
            }
        }
        // Keyboard Shortcuts
        .background(
            Button("") {
                if let id = appState.selectedPhotoID {
                    appState.markPhoto(id: id, state: .userSelected)
                }
            }
            .keyboardShortcut("1", modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                if let id = appState.selectedPhotoID {
                    appState.markPhoto(id: id, state: .alternative)
                }
            }
            .keyboardShortcut("2", modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                if let id = appState.selectedPhotoID {
                    appState.markPhoto(id: id, state: .userRejected)
                }
            }
            .keyboardShortcut("3", modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                appState.selectNextPhoto()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                appState.selectPreviousPhoto()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                if let photo = appState.selectedPhoto,
                   let burstID = photo.burstGroupID,
                   let burst = appState.session.burstGroups.first(where: { $0.id == burstID }) {
                    appState.activeBurstForComparison = burst
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
        )
        // Sheets
        .sheet(item: $appState.activeBurstForComparison) { burst in
            BurstCompareView(appState: appState, burst: burst)
        }
        .sheet(isPresented: $appState.isExportSheetPresented) {
            ExportDialogView(appState: appState)
        }
    }

    private func saveCurrentSession() {
        let savePanel = NSSavePanel()
        savePanel.title = "Salva sessione WeddingCull"
        savePanel.nameFieldStringValue = "WeddingCull_Session.json"
        savePanel.allowedContentTypes = [.json]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? appState.saveSession(to: url)
        }
    }
}
