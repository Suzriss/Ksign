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
            if !hasLoadedOnce, viewModel.isFinished {
                _load()
                hasLoadedOnce = true
            }
            _sortOption = SortOption(rawValue: _sortOptionRawValue) ?? .default
        }
        .onChange(of: viewModel.isFinished) { _ in
            _load()
        }
        .onChange(of: _sortOption) { newValue in
            _sortOptionRawValue = newValue.rawValue
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
            if
                let _sources,
                !_sources.isEmpty
            {
                // The banner and the category strip ride inside the list's
                // header, so the page reads banner → categories → apps and
                // scrolls as one piece.
                SourceAppsTableRepresentableView(
                    sources: _sources,
                    categories: _categories,
                    searchText: $_searchText,
                    sortOption: $_sortOption,
                    sortAscending: $_sortAscending,
                    selectedCategory: $_selectedCategory,
                    onSelect: {self._selectedRoute = $0}
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                if #available(iOS 17, *) {
                    ContentUnavailableView {
                        ProgressView()
                        Label(.localized("Fetching..."), systemImage: "")
                    } description: {
                        Text(.localized("Stuck? Check if you have any sources added."))
                    }
                }
                else { ProgressView() }
            }
        }
    }
    
    private func _load() {
        isLoading = true
        
        Task {
            let loadedSources = object.compactMap { viewModel.sources[$0] }
            let loadedCategories = SourceAppsCategoryStrip.categories(from: loadedSources)
            
            _sources = loadedSources
            _categories = loadedCategories
            
            // A refresh can drop the category the filter was pinned to, which
            // would otherwise leave the list permanently empty.
            if
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
