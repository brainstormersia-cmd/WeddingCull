import SwiftUI

public struct AnalysisView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                    .accessibilityIdentifier(AccessibilityIdentifiers.analysisProgressIndicator)

                Text("Analisi in corso")
                    .font(.title2)
                    .fontWeight(.bold)

                if let progress = appState.analysisProgress {
                    Text(progress.phase.rawValue)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .accessibilityIdentifier(AccessibilityIdentifiers.analysisPhaseLabel)

                    Text(progress.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Progress bar
                    if progress.totalUnits > 0 {
                        ProgressView(value: Double(progress.completedUnits), total: Double(progress.totalUnits))
                            .frame(width: 360)
                            .padding(.top, 8)

                        Text("\(progress.completedUnits) di \(progress.totalUnits) foto · \(formatElapsed(progress.elapsedTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Avvio pipeline locale...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Analysis pipeline stages list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AnalysisPhase.allCases, id: \.self) { phase in
                    HStack(spacing: 10) {
                        Image(systemName: isPhaseCompleted(phase) ? "checkmark.circle.fill" : (isCurrentPhase(phase) ? "arrow.right.circle.fill" : "circle"))
                            .foregroundColor(isPhaseCompleted(phase) ? .green : (isCurrentPhase(phase) ? .accentColor : .secondary))
                        Text(phase.rawValue)
                            .font(.callout)
                            .foregroundColor(isCurrentPhase(phase) ? .primary : .secondary)
                            .fontWeight(isCurrentPhase(phase) ? .semibold : .regular)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)

            HStack(spacing: 16) {
                if appState.isPaused {
                    Button("Riprendi") {
                        appState.resumeAnalysis()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityIdentifiers.analysisResumeButton)
                } else {
                    Button("Pausa") {
                        appState.pauseAnalysis()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityIdentifiers.analysisPauseButton)
                }

                Button("Annulla", role: .cancel) {
                    appState.cancelAnalysis()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.analysisCancelButton)
            }

            Spacer()
        }
        .frame(minWidth: 700, minHeight: 550)
        .padding()
    }

    private func isPhaseCompleted(_ phase: AnalysisPhase) -> Bool {
        guard let current = appState.analysisProgress?.phase else { return false }
        let allPhases = AnalysisPhase.allCases
        guard let currentIdx = allPhases.firstIndex(of: current),
              let phaseIdx = allPhases.firstIndex(of: phase) else { return false }
        return phaseIdx < currentIdx
    }

    private func isCurrentPhase(_ phase: AnalysisPhase) -> Bool {
        return appState.analysisProgress?.phase == phase
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
