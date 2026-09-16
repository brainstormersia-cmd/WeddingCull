import SwiftUI

public struct TargetCountControl: View {
    @ObservedObject var appState: AppState
    @State private var targetInput: Double = 700

    public init(appState: AppState) {
        self.appState = appState
        _targetInput = State(initialValue: Double(appState.session.targetSelectionCount))
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
            let maxCount = max(10, appState.session.photos.count)
            Slider(value: $targetInput, in: 10...Double(maxCount), step: 5)
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
            targetInput = Double(appState.session.targetSelectionCount)
        }
    }
}
