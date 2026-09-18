import SwiftUI

public struct BurstCompareView: View {
    @ObservedObject var appState: AppState
    let burst: BurstGroup

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var isLoupeActive: Bool = false

    public init(appState: AppState, burst: BurstGroup) {
        self.appState = appState
        self.burst = burst
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header with professional comparison controls
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confronto Sequenza Burst")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(burst.memberIDs.count) foto · Scegli lo scatto migliore · Zoom e pan sincronizzati")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Synchronized Loupe / 1:1 Zoom control
                HStack(spacing: 8) {
                    Button(action: {
                        toggleLoupe()
                    }) {
                        Label(isLoupeActive ? "Vista Intera (Fit)" : "Loupe 1:1 (Nitidezza)",
                              systemImage: isLoupeActive ? "arrow.down.right.and.arrow.up.left" : "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityIdentifiers.burstZoomLoupeButton)

                    Button(action: {
                        focusFace()
                    }) {
                        Label("Centra Volto", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityIdentifiers.burstFaceFocusButton)

                    Button("Chiudi") {
                        appState.activeBurstForComparison = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityIdentifiers.closeBurstCompareButton)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            // Side-by-side comparison strip
            let burstPhotos = appState.session.photos.filter { burst.memberIDs.contains($0.id) }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 16) {
                    ForEach(burstPhotos) { item in
                        burstPhotoCard(item: item)
                    }
                }
                .padding()
            }

            if isLoupeActive {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                    Text("Trascina per spostare il loupe sincronizzato su tutti i fotogrammi")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .accessibilityIdentifier(AccessibilityIdentifiers.burstLoupeView)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 850, minHeight: 650)
        .accessibilityIdentifier(AccessibilityIdentifiers.burstCompareModal)
    }

    private func burstPhotoCard(item: PhotoItem) -> some View {
        let isWinner = (item.id == burst.winnerID)

        return VStack(spacing: 10) {
            // High-resolution preview with synchronized loupe & pan
            ZStack(alignment: .topTrailing) {
                AsyncBurstPreviewView(
                    item: item,
                    loader: appState.thumbnailLoader,
                    zoomScale: zoomScale,
                    panOffset: panOffset,
                    onPan: { translation in
                        panOffset = CGSize(
                            width: panOffset.width + translation.width,
                            height: panOffset.height + translation.height
                        )
                    }
                )
                .frame(width: 320, height: 320)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .clipped()

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

            // Fine-grained metrics for comparing focus, eyes, and expressions
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Punteggio complessivo:")
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
                        Text("Apertura occhi:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", eye * 100))
                            .font(.caption)
                    }
                }
            }
            .frame(width: 300)

            // Winner selection: preserves alternatives without auto-rejecting
            if isWinner {
                Button(action: {
                    appState.setBurstWinner(burstID: burst.id, newWinnerID: item.id)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Vincitore attuale")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier(AccessibilityIdentifiers.setWinnerButton)
            } else {
                Button(action: {
                    appState.setBurstWinner(burstID: burst.id, newWinnerID: item.id)
                }) {
                    HStack {
                        Image(systemName: "hand.thumbsup")
                        Text("Imposta come migliore")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityIdentifier(AccessibilityIdentifiers.setWinnerButton)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }

    private func toggleLoupe() {
        if isLoupeActive {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 1.0
                panOffset = .zero
                isLoupeActive = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 2.5
                isLoupeActive = true
            }
        }
    }

    private func focusFace() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 2.5
            // Center towards the upper middle area where wedding portraits/faces typically sit
            panOffset = CGSize(width: 0, height: 40)
            isLoupeActive = true
        }
    }
}

public struct AsyncBurstPreviewView: View {
    let item: PhotoItem
    @ObservedObject var loader: ThumbnailLoader
    let zoomScale: CGFloat
    let panOffset: CGSize
    let onPan: (CGSize) -> Void
    @State private var previewImage: NSImage?

    public init(
        item: PhotoItem,
        loader: ThumbnailLoader,
        zoomScale: CGFloat = 1.0,
        panOffset: CGSize = .zero,
        onPan: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.item = item
        self.loader = loader
        self.zoomScale = zoomScale
        self.panOffset = panOffset
        self.onPan = onPan
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let nsImage = previewImage ?? loader.cachedPreview(for: item) ?? loader.cachedThumbnail(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    onPan(val.translation)
                                }
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(AccessibilityIdentifiers.photoPreviewLoaded)
                        .accessibilityLabel(item.fileName)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                Text(item.fileName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(AccessibilityIdentifiers.photoPreviewPlaceholder)
                        .accessibilityLabel(item.fileName)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: item.previewCacheKey) {
            if previewImage == nil {
                previewImage = await loader.requestPreview(for: item)
            }
        }
    }
}
