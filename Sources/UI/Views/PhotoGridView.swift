import SwiftUI

public struct PhotoGridView: View {
    @ObservedObject var appState: AppState
    @State private var thumbnailSize: CGFloat = 160

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 12)
    ]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Grid toolbar: zoom slider and quick actions
            HStack {
                Text("\(appState.filteredPhotos.count) foto")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Keyboard workflow shortcuts hint
                HStack(spacing: 8) {
                    Text("Scorciatoie: [1] Seleziona · [2] Alternativa · [3] Scarta · [Spazio] Anteprima · [Invio] Burst")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "photo")
                    .font(.caption2)
                Slider(value: $thumbnailSize, in: 100...260)
                    .frame(width: 100)
                Image(systemName: "photo.fill")
                    .font(.caption2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.5), spacing: 10)], spacing: 10) {
                    ForEach(appState.filteredPhotos) { item in
                        photoCell(item: item)
                            .onTapGesture {
                                appState.selectedPhotoID = item.id
                            }
                            .onTapGesture(count: 2) {
                                if let burstID = item.burstGroupID,
                                   let burst = appState.session.burstGroups.first(where: { $0.id == burstID }) {
                                    appState.activeBurstForComparison = burst
                                }
                            }
                    }
                }
                .padding(12)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.photoGrid)
        }
    }

    private func photoCell(item: PhotoItem) -> some View {
        let isSelected = appState.selectedPhotoID == item.id

        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail image representation
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(3/2, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text(item.fileName)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                    )

                // Top left badge: Burst indicator
                if let burstID = item.burstGroupID,
                   let burst = appState.session.burstGroups.first(where: { $0.id == burstID }) {
                    HStack(spacing: 2) {
                        Image(systemName: "square.stack.3d.forward.dottedline")
                        Text("\(burst.memberIDs.count)")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(3)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                // Top right badge: Selection status
                statusBadge(item: item)
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            // Minimal photo info footer
            HStack {
                Text(item.category.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", item.metrics.overallScore * 100))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func statusBadge(item: PhotoItem) -> some View {
        switch item.selectionState {
        case .selected, .userSelected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .background(Circle().fill(Color.white))
        case .alternative:
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 11))
                .foregroundColor(.orange)
                .padding(2)
                .background(Circle().fill(Color.white))
        case .rejected, .userRejected:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
                .background(Circle().fill(Color.white))
        }
    }
}
