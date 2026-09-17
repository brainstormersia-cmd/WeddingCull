import SwiftUI
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

@main
public struct WeddingCullApp: App {
    @StateObject private var appState = AppState()
    @State private var hasHandledCommandLine = false

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
            .onAppear {
                handleCommandLineArguments()
            }
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

    private func handleCommandLineArguments() {
        guard !hasHandledCommandLine else { return }
        hasHandledCommandLine = true

        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment

        if args.contains("--ui-testing") || env["UI_TESTING"] == "YES" {
            // Check for direct session reopening
            var sessionPath: String? = env["UI_TEST_SESSION_FILE"]
            if let idx = args.firstIndex(of: "--reopen-session"), idx + 1 < args.count {
                sessionPath = args[idx + 1]
            }
            if let sPath = sessionPath, FileManager.default.fileExists(atPath: sPath) {
                let url = URL(fileURLWithPath: sPath)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    try? appState.loadSession(from: url)
                }
                return
            }

            var folderPath: String? = env["UI_TEST_SOURCE_FOLDER"]
            if let idx = args.firstIndex(of: "--source-folder"), idx + 1 < args.count {
                folderPath = args[idx + 1]
            }

            var targetCount = 120
            if let idx = args.firstIndex(of: "--target-count"), idx + 1 < args.count, let tc = Int(args[idx + 1]) {
                targetCount = tc
            }

            if let path = folderPath, FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.startAnalysis(folderURL: url, targetCount: targetCount)
                }
            }
        }
    }
}
