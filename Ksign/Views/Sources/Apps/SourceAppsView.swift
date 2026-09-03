//
//  SourceAppsView.swift
//  Feather
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import AltSourceKit
import NimbleViews
import UIKit

// MARK: - Extension: View (Enil)
extension SourceAppsView {
    enum SortOption: String, CaseIterable {
        /// The list's own order: most recently updated first.
        case `default` = "default"
        case name
        case date
        
        var displayName: String {
            switch self {
            case .default:  .localized("Latest")
            case .name:     .localized("Name")
            case .date:     .localized("Date")
            }
        }
    }
}

// MARK: - View
struct SourceAppsView: View {
    @AppStorage("Feather.sortOptionRawValue") private var _sortOptionRawValue: String = SortOption.default.rawValue
    @AppStorage("Feather.sortAscending") private var _sortAscending: Bool = true
    
    @State private var _sortOption: SortOption = .default
    @State private var _selectedRoute: SourceAppRoute?
    @State private var _selectedCategory: String?
    @State private var _categories: [SourceAppsCategoryStrip.Category] = []
    
    @State var isLoading = true
    @State var hasLoadedOnce = false
    @State private var _searchText = ""
    var fromAppStore: Bool = false
    
    private var _navigationTitle: String {
        if fromAppStore {
            return .localized("Apps")
        } else if object.count == 1 {
            return object[0].name ?? .localized("Unknown")
        } else {
            return .localized("%lld Sources", arguments: object.count)
        }
    }
    
    var object: [AltSource]
    @ObservedObject var viewModel: SourcesViewModel
    @State private var _sources: [ASRepository]?
    
    /// The shop's own catalog, read a page at a time. Every other source is
    /// still one file fetched whole through `viewModel`.
    @ObservedObject private var _pager = CatalogPager.shared
    
    /// The catalog source among the ones this page was handed, if any.
    ///
    /// The store tab falls back to the built-in address. Its whole list is the
    /// shop's catalog, and the row in Core Data is only where the address is
    /// normally kept — an install whose seeding failed has no row at all, and
    /// that used to be a store that showed "the store didn't answer" and never
    /// asked anyone anything. The catalog does not need the row to be read.
    private var _catalogURL: URL? {
        if let stored = object.compactMap(\.sourceURL).first(where: CeresifyAPI.isOurs) {
            return stored
        }
        
        guard fromAppStore else { return nil }
        
        return Storage.builtInSourceURLs.first.flatMap(URL.init(string:))
    }
    
    private var _isPaged: Bool { _catalogURL != nil }
    
    /// What the pager is being asked for right now: the chip, the search field,
    /// the sort menu and the language, in one value.
    private var _query: CatalogPager.Query {
        CatalogPager.Query(
            category: _selectedCategory,
            search: _searchText,
            sort: _sortOption,
            ascending: _sortAscending,
            language: LanguageManager.shared.effectiveCode
        )
    }
    
    /// What the list draws. One repository either way — the paged catalog's is
    /// the pages read so far.
    private var _displayed: [ASRepository] {
        if _isPaged {
            return _pager.repository.map { [$0] } ?? []
        }
        return _sources ?? []
    }
    
    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var _allSources: FetchedResults<AltSource>
    
    // MARK: Body
    var body: some View {
        VStack(spacing: 0) {
            // The shop's own line, and the word that the store is running on
            // what it loaded last. Kept above the table rather than inside its
            // header: the header is sized once by UIKit, and either of these
            // can turn up after that pass has already run.
            CeresifyStoreNoticesView(selectedCategory: _selectedCategory)
            
            // The store's own countdown, above the list rather than on any one
            // app's page.
            CeresifyCountdownStack(placement: .store)
                .padding(.horizontal, 21)
            
            _list
        }
        .navigationTitle(_navigationTitle)
        .searchable(text: $_searchText, placement: .platform())
        .toolbarTitleMenu {
            if
                let _sources,
                _sources.count == 1
            {
                if let url = _sources[0].website {
                    Button(.localized("Visit Website"), systemImage: "globe") {
                        UIApplication.open(url)
                    }
                }
                
                if let url = _sources[0].patreonURL {
                    Button(.localized("Visit Patreon"), systemImage: "dollarsign.circle") {
                        UIApplication.open(url)
                    }
                }
            }
            
        }
        .toolbar {
            // The Sources shortcut used to sit here; sources are managed from
            // the General tab now, so the store's toolbar stays to refresh and
            // sort only.
            NBToolbarButton(
                systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90",
                style: .icon,
                placement: .topBarTrailing
            ) {
                Task {
                    if _isPaged { _pager.refresh() }
                    await viewModel.fetchSources(Array(_allSources), refresh: true)
                }
            }
            
            NBToolbarMenu(
                systemImage: "line.3.horizontal.decrease",
                style: .icon,
                placement: .topBarTrailing
            ) {
                _sortActions()
            }
        }
        .onAppear {
            // Whatever the model already holds — the stored copy, or a
            // fetch that finished while another tab was up — goes on screen
            // straight away, fetching or not.
            if !hasLoadedOnce {
                _load()
                hasLoadedOnce = true
            }
            _sortOption = SortOption(rawValue: _sortOptionRawValue) ?? .default
            
            _applyQuery()
        }
        // The chip, the sort menu and the language are all part of the one
        // question put to the server, so any of them moving asks it again from
        // the first page. The search field has its own wait below.
        .onChange(of: _selectedCategory) { _ in _applyQuery() }
        .onChange(of: _sortAscending) { _ in _applyQuery() }
        // Typing is not a question per letter: the store waits for the typing
        // to stop before asking. `task(id:)` cancels the wait on every new
        // letter, which is the whole of the debounce.
        .task(id: _searchText) {
            guard _isPaged else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run { _applyQuery() }
        }
        // Driven by `isFetching`, which is published: `isFinished` is written
        // off the main actor and a view could only notice it flipping by
        // accident, which is what left this page waiting forever.
        .onChange(of: viewModel.isFetching) { isFetching in
            guard !isFetching else { return }
            _load()
        }
        // The stored copy lands first and the fresh one after it; each is
        // shown as it arrives rather than at the end of the whole fetch.
        .onChange(of: viewModel.revision) { _ in
            _load()
        }
        .onChange(of: _sortOption) { newValue in
            _sortOptionRawValue = newValue.rawValue
            _applyQuery()
        }
        .navigationDestinationIfAvailable(item: $_selectedRoute) { route in
            SourceAppsDetailView(source: route.source, app: route.app)
        }
        
    }
    
    /// The store's list — the table with the banner and category strip in its
    /// header, or the wait for a source to arrive.
    @ViewBuilder
    private var _list: some View {
        ZStack {
            if !_displayed.isEmpty {
                // The banner and the category strip ride inside the list's
                // header, so the page reads banner → categories → apps and
                // scrolls as one piece.
                SourceAppsTableRepresentableView(
                    sources: _displayed,
                    categories: _isPaged ? _pager.categories : _categories,
                    searchText: $_searchText,
                    sortOption: $_sortOption,
                    sortAscending: $_sortAscending,
                    selectedCategory: $_selectedCategory,
                    onSelect: {self._selectedRoute = $0},
                    isPaged: _isPaged,
                    totalCount: _isPaged ? _pager.total : nil,
                    isLoadingMore: _isPaged && _pager.isLoadingMore,
                    onReachEnd: { _pager.loadMore() }
                )
                .ignoresSafeArea(edges: .bottom)
                // The strip is inside the table, so a category that came back
                // with nothing still has to draw it — the way out of an empty
                // category is the strip that led into it.
                .overlay {
                    if _isPaged, _pager.repository?.apps.isEmpty == true, !_pager.isLoading {
                        _empty
                    }
                }
            } else if _isPaged ? _pager.isLoading : (viewModel.isFetching || _sources == nil) {
                _waiting
            } else {
                // The fetch is over and it brought nothing. Saying `Fetching…`
                // here is a lie the user can do nothing about — the catalog is
                // unreachable, or answered with an empty list — so say so and
                // give them the one thing that can change it.
                _nothing
            }
        }
    }
    
    @ViewBuilder
    private var _waiting: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView {
                ProgressView()
                Label(.localized("Fetching..."), systemImage: "")
            } description: {
                Text(.localized("Stuck? Check if you have any sources added."))
            }
        } else {
            ProgressView()
        }
    }
    
    /// The chip that is selected has no apps under it — which is not the same
    /// as the store having failed to answer.
    @ViewBuilder
    private var _empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(Color.ceresifyGold.opacity(0.7))
            
            Text(.localized("Nothing in this category yet"))
                .font(.subheadline)
                .foregroundStyle(Color.ceresifySubtitle)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 34)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var _nothing: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Color.ceresifyGold.opacity(0.7))
            
            Text(.localized("Nothing to show"))
                .font(.headline)
                .foregroundStyle(Color.ceresifyTitle)
            
            Text(.localized("The store didn't answer. Check your connection and try again."))
                .font(.subheadline)
                .foregroundStyle(Color.ceresifySubtitle)
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    if _isPaged { _pager.refresh() }
                    await viewModel.fetchSources(Array(_allSources), refresh: true)
                }
            } label: {
                Text(.localized("Try Again")).bg()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func _applyQuery() {
        guard _isPaged else { return }
        _pager.configure(_catalogURL)
        _pager.apply(_query)
    }
    
    private func _load() {
        isLoading = true
        
        Task {
            let loadedSources = object.compactMap { viewModel.sources[$0] }
            let loadedCategories = SourceAppsCategoryStrip.categories(from: loadedSources)
            
            _sources = loadedSources
            _categories = loadedCategories
            
            // A refresh can drop the category the filter was pinned to, which
            // would otherwise leave the list permanently empty. The paged
            // catalog keeps its own chips — this is looking at a list it has
            // nothing to do with.
            if
                !_isPaged,
                let selected = _selectedCategory,
                !loadedCategories.contains(where: { $0.name == selected })
            {
                _selectedCategory = nil
            }
            
            withAnimation(.easeIn(duration: 0.2)) {
                isLoading = false
            }
        }
    }
    
    struct SourceAppRoute: Identifiable, Hashable {
        let source: ASRepository
        let app: ASRepository.App
        let id: String = UUID().uuidString
    }
}

// MARK: - Extension: View (Sort)
extension SourceAppsView {
    @ViewBuilder
    private func _sortActions() -> some View {
        Section(.localized("Filter by")) {
            ForEach(SortOption.allCases, id: \.displayName) { opt in
                _sortButton(for: opt)
            }
        }
    }
    
    private func _sortButton(for option: SortOption) -> some View {
        Button {
            if _sortOption == option {
                _sortAscending.toggle()
            } else {
                _sortOption = option
                _sortAscending = true
            }
        } label: {
            HStack {
                Text(option.displayName)
                Spacer()
                if _sortOption == option {
                    Image(systemName: _sortAscending ? "chevron.up" : "chevron.down")
                }
            }
        }
    }
}

import SwiftUI

extension View {
    @ViewBuilder
    func navigationDestinationIfAvailable<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self
        }
    }
}
