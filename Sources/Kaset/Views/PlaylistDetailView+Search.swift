import SwiftUI

// MARK: - In-playlist search

@available(macOS 26.0, *)
extension PlaylistDetailView {
    /// Minimum loaded track count before the in-playlist search field appears, so short
    /// albums and playlists stay uncluttered.
    private static var searchFieldMinimumTrackCount: Int {
        8
    }

    /// Whether the in-playlist search field should be offered. Hidden for short, fully
    /// loaded lists where filtering adds clutter without value.
    func shouldShowSearchField(for detail: PlaylistDetail) -> Bool {
        // Once a query is active, keep the field visible even if the list later shrinks below
        // the threshold (eager load finishing, a track being removed) — otherwise the field
        // and its clear button would vanish while the list stays filtered, stranding the user.
        if !self.searchQuery.isEmpty {
            return true
        }
        return detail.tracks.count >= Self.searchFieldMinimumTrackCount || self.viewModel.hasMore
    }

    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(String(localized: "Find in playlist"), text: self.$searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.PlaylistDetail.searchField)

            if !self.searchQuery.isEmpty {
                Button {
                    self.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
                .accessibilityIdentifier(AccessibilityID.PlaylistDetail.clearSearchButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .compatGlass(in: .capsule)
        .frame(maxWidth: 360, alignment: .leading)
    }

    /// The playlist's tracks, filtered by `searchQuery`, as direct children of the detail
    /// view's lazy stack. Each rendered row carries its original playlist index, so playing a
    /// match starts the queue at that track's real position — identical to the unfiltered list.
    @ViewBuilder
    func trackRows(
        _ tracks: [Song], isAlbum: Bool, author: String?, fallbackAlbum: Album? = nil
    ) -> some View {
        let rows = PlaylistTrackFilter.filter(tracks, query: self.searchQuery)

        // Show "No Results" only for an active query that is done loading: a genuinely
        // empty playlist (no query) renders nothing, and while the playlist is still
        // paging in — an eager search load may not have reached the matching tail yet —
        // the pagination spinner below signals progress instead of a premature empty state.
        if rows.isEmpty, !self.searchQuery.isEmpty, !self.viewModel.hasMore {
            self.noSearchResultsView
        }

        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
            // Row and divider form one lazy-stack element: as siblings they doubled
            // the subviews the stack places and re-realizes while scrolling.
            VStack(spacing: 0) {
                // Invariant: pass the FULL `tracks` and the row's ORIGINAL `row.index` (not the
                // filtered position) so playback queues the whole playlist from the right spot.
                self.trackRow(
                    row.track, index: row.index, tracks: tracks, isAlbum: isAlbum, author: author,
                    fallbackAlbum: fallbackAlbum
                )

                if position < rows.count - 1 {
                    Divider()
                        // For albums: 28 (index) + 12 (spacing)
                        // For playlists: 28 (index) + 12 (spacing) + 40 (thumbnail) + 16 (spacing)
                        .padding(.leading, isAlbum ? 40 : 96)
                }
            }
            .onAppear {
                // Scroll-based pagination only applies to the unfiltered list; a search
                // eagerly loads the whole playlist, so the last *visible* filtered row is
                // not a meaningful pagination trigger.
                if self.searchQuery.isEmpty {
                    self.viewModel.loadMoreIfNeeded(appearingAt: row.index)
                }
            }
        }

        // Loading indicator for pagination
        if self.viewModel.loadingState == .loadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .padding()
                Spacer()
            }
        }
    }

    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: self.searchQuery)
            .accessibilityIdentifier(AccessibilityID.PlaylistDetail.searchEmptyState)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }
}
