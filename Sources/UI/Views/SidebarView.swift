import SwiftUI

public struct SidebarView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        List(selection: Binding(
            get: { appState.currentFilter },
            set: { if let val = $0 { appState.currentFilter = val } }
        )) {
            Section("Raccolte smart") {
                albumRow(title: "Tutte", icon: "photo.on.rectangle", count: appState.session.photos.count, filter: .smartAlbum("all"))
                albumRow(title: "Selezionate", icon: "checkmark.circle.fill", color: .green, count: appState.session.photos.filter { $0.selectionState.isIncludedInFinal }.count, filter: .smartAlbum("selected"))
                albumRow(title: "Alternative", icon: "arrow.triangle.swap", color: .orange, count: appState.session.photos.filter { $0.selectionState == .alternative }.count, filter: .smartAlbum("alternative"))
                albumRow(title: "Scartate", icon: "xmark.circle", color: .gray, count: appState.session.photos.filter { $0.selectionState == .rejected || $0.selectionState == .userRejected }.count, filter: .smartAlbum("rejected"))
                albumRow(title: "Duplicati", icon: "doc.on.doc", count: appState.session.photos.filter { $0.isDuplicate }.count, filter: .smartAlbum("duplicates"))
                albumRow(title: "Bassa qualità", icon: "exclamationmark.triangle", count: appState.session.photos.filter { $0.metrics.isTechnicallyLowQuality }.count, filter: .smartAlbum("lowQuality"))
            }

            Section("Categorie matrimonio") {
                ForEach(WeddingCategory.allCases) { category in
                    let count = appState.session.photos.filter { $0.category == category }.count
                    if count > 0 {
                        NavigationLink(value: SidebarFilter.category(category)) {
                            Label {
                                HStack {
                                    Text(category.displayName)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: category.iconName)
                            }
                        }
                    }
                }
            }

            if !appState.session.segments.isEmpty {
                Section("Momenti") {
                    ForEach(appState.session.segments) { segment in
                        NavigationLink(value: SidebarFilter.segment(segment.id)) {
                            Label {
                                HStack {
                                    Text(segment.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(segment.photoIDs.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            }

            if !appState.session.personClusters.isEmpty {
                Section("Persone") {
                    ForEach(appState.session.personClusters) { cluster in
                        NavigationLink(value: SidebarFilter.person(cluster.id)) {
                            Label {
                                HStack {
                                    Text(cluster.name)
                                    Spacer()
                                    Text("\(cluster.photoIDs.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: cluster.isSuggestedPrimary ? "star.fill" : "person.fill")
                                    .foregroundColor(cluster.isSuggestedPrimary ? .yellow : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier(AccessibilityIdentifiers.sidebarList)
    }

    private func albumRow(title: String, icon: String, color: Color? = nil, count: Int, filter: SidebarFilter) -> some View {
        NavigationLink(value: filter) {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(color)
            }
        }
    }
}
