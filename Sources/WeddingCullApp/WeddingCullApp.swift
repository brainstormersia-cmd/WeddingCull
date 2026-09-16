import SwiftUI

@main
public struct WeddingCullApp: App {
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Group {
                switch appState.navigationState {
                case .start:
                    StartView(appState: appState)
                case .analyzing:
                    AnalysisView(appState: appState)
                case .review:
                    MainReviewView(appState: appState)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Importa matrimonio...") {
                    appState.navigationState = .start
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Selezione") {
                Button("Seleziona") {
                    if let id = appState.selectedPhotoID {
                        appState.markPhoto(id: id, state: .userSelected)
                    }
                }
                .keyboardShortcut("1", modifiers: [])

                Button("Alternativa") {
                    if let id = appState.selectedPhotoID {
                        appState.markPhoto(id: id, state: .alternative)
                    }
                }
                .keyboardShortcut("2", modifiers: [])

                Button("Scarta") {
                    if let id = appState.selectedPhotoID {
                        appState.markPhoto(id: id, state: .userRejected)
                    }
                }
                .keyboardShortcut("3", modifiers: [])
            }
        }
    }
}
