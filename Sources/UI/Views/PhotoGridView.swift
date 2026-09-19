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

            if appState.isAnalyzing, let prog = appState.analysisProgress {
                HStack(spacing: 12) {
                    ProgressView(value: Double(prog.completedUnits), total: Double(max(1, prog.totalUnits)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                        .accessibilityIdentifier(AccessibilityIdentifiers.analysisProgressIndicator)

                    Text("\(prog.phase.rawValue): \(prog.message)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .accessibilityIdentifier(AccessibilityIdentifiers.analysisPhaseLabel)

                    Spacer()

                    if appState.isPaused {
                        Button("Riprendi") {
                            appState.resumeAnalysis()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(AccessibilityIdentifiers.analysisResumeButton)
                    } else {
                        Button("Pausa") {
                            appState.pauseAnalysis()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(AccessibilityIdentifiers.analysisPauseButton)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))

                Divider()
            }

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
                // Real thumbnail with async loading and caching
                AsyncThumbnailView(item: item, loader: appState.thumbnailLoader)
                    .onAppear {
                        if let idx = appState.filteredPhotos.firstIndex(where: { $0.id == item.id }) {
                            let nextItems = Array(appState.filteredPhotos.dropFirst(idx + 1).prefix(12))
                            appState.thumbnailLoader.prefetchThumbnails(for: nextItems)
                        }
                    }

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
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func statusBadge(item: PhotoItem) -> some View {
        switch item.selectionState {
        case .selected, .userSelected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .background(Circle().fill(Color.white))
        case .review:
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.blue)
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

public struct AsyncThumbnailView: View {
    let item: PhotoItem
    @ObservedObject var loader: ThumbnailLoader
    @State private var thumbnailImage: NSImage?

    public init(item: PhotoItem, loader: ThumbnailLoader) {
        self.item = item
        self.loader = loader
    }

    public var body: some View {
        let currentImage = thumbnailImage ?? loader.cachedThumbnail(for: item)
        let isLoaded = (currentImage != nil)

        ZStack {
            if let nsImage = currentImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        VStack(spacing: 4) {
                            if ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["UI_TESTING"] == "YES" {
                                Image(systemName: "photo")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                            Text(item.fileName)
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .aspectRatio(3/2, contentMode: .fit)
        .clipped()
        .cornerRadius(6)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(isLoaded ? AccessibilityIdentifiers.photoThumbnailLoaded : AccessibilityIdentifiers.photoThumbnailPlaceholder)
        .accessibilityLabel(item.fileName)
        .task(id: item.previewCacheKey) {
            if thumbnailImage == nil {
                let img = await loader.requestThumbnail(for: item)
                if let img = img {
                    thumbnailImage = img
                }
            }
        }
    }
}
