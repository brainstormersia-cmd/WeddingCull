import SwiftUI

public struct TargetCountControl: View {
    @ObservedObject var appState: AppState
    @State private var targetInput: Double = 700

    public init(appState: AppState) {
        self.appState = appState
        let initial = Double(appState.session.targetSelectionCount)
        _targetInput = State(initialValue: max(1.0, initial))
    }

    public var body: some View {
        HStack(spacing: 20) {
            // Count statistics
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Originali")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(appState.session.photos.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Divider().frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Obiettivo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(targetInput))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }

                Divider().frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Selezionate")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let selectedCount = appState.session.photos.filter { $0.selectionState.isIncludedInFinal }.count
                    Text("\(selectedCount)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }

            // Slider control
            let minCount: Double = 1.0
            let maxCount: Double = max(Double(appState.session.photos.count), Double(appState.session.targetSelectionCount), 2.0)
            Slider(value: $targetInput, in: minCount...maxCount, step: 1)
                .frame(width: 180)
                .accessibilityIdentifier(AccessibilityIdentifiers.targetCountSlider)
                .onChange(of: targetInput) { newValue in
                    appState.updateTargetCount(Int(newValue))
                }

            // Recalculate button
            Button(action: {
                appState.updateTargetCount(Int(targetInput))
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Ricalcola")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityIdentifiers.recalculateButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
        .onAppear {
            let current = Double(appState.session.targetSelectionCount)
            let maxC = max(Double(appState.session.photos.count), current, 2.0)
            targetInput = max(1.0, min(maxC, current))
        }
    }
}
