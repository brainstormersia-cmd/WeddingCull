import SwiftUI

public struct InspectorView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            if let photo = appState.selectedPhoto {
                VStack(alignment: .leading, spacing: 18) {
                    // Header & File info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photo.fileName)
                            .font(.headline)
                            .lineLimit(2)

                        if let date = photo.metadata.captureDate {
                            Text(date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if photo.hasRawJpegPair {
                            Text("RAW + JPEG")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Divider()

                    // Selection state buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stato selezione")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: { appState.markPhoto(id: photo.id, state: .userSelected) }) {
                                Label("Seleziona [1]", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .accessibilityIdentifier(AccessibilityIdentifiers.selectButton)

                            Button(action: { appState.markPhoto(id: photo.id, state: .alternative) }) {
                                Label("Alt [2]", systemImage: "arrow.triangle.swap")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityIdentifier(AccessibilityIdentifiers.alternativeButton)

                            Button(action: { appState.markPhoto(id: photo.id, state: .userRejected) }) {
                                Label("Scarta [3]", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                            .accessibilityIdentifier(AccessibilityIdentifiers.rejectButton)
                        }
                    }

                    // Selection Reason
                    if !photo.metrics.selectionReason.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Motivo selezione")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                                Text(photo.metrics.selectionReason)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(8)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    Divider()

                    // Quality Scores breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Metriche di qualità")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        scoreBar(label: "Punteggio globale", value: photo.metrics.overallScore, color: .accentColor)
                        scoreBar(label: "Nitidezza", value: photo.metrics.sharpnessScore, color: .blue)
                        scoreBar(label: "Esposizione", value: photo.metrics.exposureScore, color: .orange)

                        if photo.metrics.faceCount > 0 {
                            scoreBar(label: "Nitidezza volti", value: photo.metrics.faceSharpnessScore, color: .purple)
                            scoreBar(label: "Qualità volti", value: photo.metrics.faceQualityScore, color: .indigo)
                            if let eye = photo.metrics.averageEyeOpenness {
                                scoreBar(label: "Apertura occhi", value: eye, color: .teal)
                            }
                        }
                    }

                    Divider()

                    // Burst info
                    if let burstID = photo.burstGroupID,
                       let burst = appState.session.burstGroups.first(where: { $0.id == burstID }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gruppo Burst")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("\(burst.memberIDs.count) foto scattate in sequenza rapida")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if photo.isBurstWinner {
                                Label("Miglior scatto consigliato", systemImage: "crown.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }

                            Button("Confronta burst [Invio]") {
                                appState.activeBurstForComparison = burst
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Divider()
                    }

                    // Camera & EXIF Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadati fotocamera")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        metadataRow(label: "Fotocamera", value: photo.metadata.cameraSummary)
                        if let lens = photo.metadata.lensModel {
                            metadataRow(label: "Obiettivo", value: lens)
                        }
                        metadataRow(label: "Tempo", value: photo.metadata.shutterSpeedFormatted)
                        metadataRow(label: "Diaframma", value: photo.metadata.apertureFormatted)
                        metadataRow(label: "ISO", value: photo.metadata.isoFormatted)
                        metadataRow(label: "Focale", value: photo.metadata.focalLengthFormatted)
                        metadataRow(label: "Dimensioni", value: "\(photo.metadata.width) × \(photo.metadata.height) px")
                    }

                    Spacer()
                }
                .padding()
            } else {
                VStack {
                    Spacer()
                    Text("Nessuna foto selezionata")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
        .accessibilityIdentifier(AccessibilityIdentifiers.inspectorPanel)
    }

    private func scoreBar(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            ProgressView(value: max(0.0, min(1.0, value)))
                .tint(color)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
