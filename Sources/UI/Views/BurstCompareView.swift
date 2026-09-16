import SwiftUI

public struct BurstCompareView: View {
    @ObservedObject var appState: AppState
    let burst: BurstGroup

    public init(appState: AppState, burst: BurstGroup) {
        self.appState = appState
        self.burst = burst
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Confronto Sequenza Burst")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(burst.memberIDs.count) foto · Scegli lo scatto migliore")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Chiudi") {
                    appState.activeBurstForComparison = nil
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.closeBurstCompareButton)
            }
            .padding()

            Divider()

            // Side-by-side comparison grid
            let burstPhotos = appState.session.photos.filter { burst.memberIDs.contains($0.id) }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 16) {
                    ForEach(burstPhotos) { item in
                        burstPhotoCard(item: item)
                    }
                }
                .padding()
            }

            Spacer()
        }
        .frame(minWidth: 800, minHeight: 600)
        .accessibilityIdentifier(AccessibilityIdentifiers.burstCompareModal)
    }

    private func burstPhotoCard(item: PhotoItem) -> some View {
        let isWinner = (item.id == burst.winnerID)

        return VStack(spacing: 12) {
            // Image card
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 280, height: 280)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(item.fileName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )

                if isWinner {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                        Text("Vincitore")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(6)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(6)
                    .padding(8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isWinner ? Color.yellow : Color.clear, lineWidth: 3)
            )

            // Quality metrics
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Punteggio:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", item.metrics.overallScore * 100))
                        .font(.caption)
                        .fontWeight(.bold)
                }

                HStack {
                    Text("Nitidezza volti:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", item.metrics.faceSharpnessScore * 100))
                        .font(.caption)
                }

                if let eye = item.metrics.averageEyeOpenness {
                    HStack {
                        Text("Occhi aperti:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", eye * 100))
                            .font(.caption)
                    }
                }
            }
            .frame(width: 260)

            // Button to set as winner
            Button(action: {
                appState.setBurstWinner(burstID: burst.id, newWinnerID: item.id)
            }) {
                HStack {
                    Image(systemName: isWinner ? "checkmark" : "hand.thumbsup.fill")
                    Text(isWinner ? "Vincitore attuale" : "Imposta come migliore")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(isWinner ? .borderedProminent : .bordered)
            .tint(isWinner ? .green : .accentColor)
            .accessibilityIdentifier(AccessibilityIdentifiers.setWinnerButton)
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }
}
