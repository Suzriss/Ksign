//
//  SourceAppsTableView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit

// MARK: - Table
/// Reports its own layout passes so the header can be resized against the
/// table's real width — on rotation as well as first layout.
final class SourceAppsTableView: UITableView {
    var onLayout: ((UITableView) -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

// MARK: - Representable
struct SourceAppsTableRepresentableView: UIViewRepresentable {
    var sources: [ASRepository]
    var categories: [SourceAppsCategoryStrip.Category]
    @Binding var searchText: String
    @Binding var sortOption: SourceAppsView.SortOption
    @Binding var sortAscending: Bool
    @Binding var selectedCategory: String?
    var onSelect: (SourceAppsView.SourceAppRoute) -> Void
    
    /// News only makes sense when a single source is on screen — merged sources
    /// have no one banner to show.
    private var _news: [ASRepository.News]? {
        sources.count == 1 ? sources.first?.news : nil
    }
    
    private func _header(width: CGFloat) -> SourceAppsListHeaderView {
        SourceAppsListHeaderView(
            news: _news,
            categories: categories,
            width: width,
            selection: selectedCategory,
            onSelectCategory: { selectedCategory = $0 }
        )
    }
    
    func makeUIView(context: Context) -> UITableView {
        let tableView = SourceAppsTableView(frame: .zero, style: .plain)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AppCell")
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")
        
        if #available(iOS 17, *) {
            tableView.allowsSelection = true
        } else {
            tableView.allowsSelection = false
        }
        
        let header = UIHostingController(rootView: _header(width: tableView.bounds.width))
        header.view.translatesAutoresizingMaskIntoConstraints = true
        header.view.backgroundColor = .clear
        // Held by the coordinator: the table only retains the view, and a
        // released controller stops driving its SwiftUI updates.
        context.coordinator.headerController = header
        context.coordinator.makeHeader = { self._header(width: $0) }
        
        tableView.onLayout = { [weak coordinator = context.coordinator] table in
            coordinator?.layoutHeader(in: table)
        }
        
        tableView.alpha = 0
        
        UIView.transition(with: tableView,  duration: 0.5, options: [.transitionCrossDissolve], animations: {
            tableView.alpha = 1
        }, completion: nil)
        
        return tableView
    }
    
    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.uiTableView = tableView
        
        context.coordinator.makeHeader = { self._header(width: $0) }
        context.coordinator.layoutHeader(in: tableView, force: true)
        
        let sourcesChanged = context.coordinator.sources != sources
        let searchChanged = context.coordinator.searchText != searchText
        let sortOptionChanged = context.coordinator.sortOption != sortOption
        let sortDirectionChanged = context.coordinator.sortAscending != sortAscending
        let categoryChanged = context.coordinator.selectedCategory != selectedCategory
        
        context.coordinator.sources = sources
        context.coordinator.searchText = searchText
        context.coordinator.sortOption = sortOption
        context.coordinator.sortAscending = sortAscending
        context.coordinator.selectedCategory = selectedCategory
        
        if sourcesChanged || searchChanged || sortOptionChanged || sortDirectionChanged || categoryChanged {
            context.coordinator.invalidateCache()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            sources: sources,
            searchText: searchText,
            sortOption: sortOption,
            sortAscending: sortAscending,
            selectedCategory: selectedCategory,
            onSelect: onSelect
        )
    }
}

// MARK: - Representable Extension: Coordinator
extension SourceAppsTableRepresentableView { class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
    var sources: [ASRepository]
    var searchText: String
    var sortOption: SourceAppsView.SortOption
    var sortAscending: Bool
    var selectedCategory: String?
    let onSelect: (SourceAppsView.SourceAppRoute) -> Void
    
    private var _groupedAppsByNameFirstLetter: [String: [(source: ASRepository, app: ASRepository.App)]] = [:]
    private var _groupedAppsByDate: [String: [(source: ASRepository, app: ASRepository.App)]] = [:]
    private var _sortedSectionTitles: [String] = []
    
    private var _cachedSortedApps: [(source: ASRepository, app: ASRepository.App)] = []
    weak var uiTableView: UITableView?
    var headerController: UIHostingController<SourceAppsListHeaderView>?
    var makeHeader: ((CGFloat) -> SourceAppsListHeaderView)?
    private var _headerWidth: CGFloat = 0
    private var _headerHeight: CGFloat = 0
    
    /// Rebuilds the header for the table's current width and sizes it to the
    /// height its content asks for, dropping it when there is nothing to show.
    ///
    /// A table lays out on every scroll tick, so this only does the work when
    /// the width actually moved or the content behind it changed — reassigning
    /// the header on each pass would both cost a measure and loop.
    func layoutHeader(in tableView: UITableView, force: Bool = false) {
        guard
            let headerController,
            let makeHeader
        else {
            return
        }
        
        let width = tableView.bounds.width
        let widthChanged = width != _headerWidth
        
        guard
            width > 0,
            force || widthChanged
        else {
            return
        }
        
        _headerWidth = width
        headerController.rootView = makeHeader(width)
        
        let height = headerController.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        
        guard height > 0 else {
            _headerHeight = 0
            tableView.tableHeaderView = nil
            return
        }
        
        // Only hand the table a new header once its box has actually moved:
        // every assignment costs a layout pass.
        guard
            widthChanged ||
            height != _headerHeight ||
            tableView.tableHeaderView !== headerController.view
        else {
            return
        }
        
        _headerHeight = height
        headerController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = headerController.view
    }
    
    private var _allAppsWithSource: [(source: ASRepository, app: ASRepository.App)] {
        sources.flatMap { source in source.apps.map { (source: source, app: $0) } }
    }
    
    private var _sortedApps: [(source: ASRepository, app: ASRepository.App)] {
        if !_cachedSortedApps.isEmpty {
            return _cachedSortedApps
        }
        _cachedSortedApps = _calculateSortedApps()
        return _cachedSortedApps
    }
    
    init(
        sources: [ASRepository],
        searchText: String,
        sortOption: SourceAppsView.SortOption,
        sortAscending: Bool,
        selectedCategory: String?,
        onSelect: @escaping (SourceAppsView.SourceAppRoute) -> Void
    ) {
        self.sources = sources
        self.searchText = searchText
        self.sortOption = sortOption
        self.sortAscending = sortAscending
        self.selectedCategory = selectedCategory
        self.onSelect = onSelect
        super.init()
        
        if sortOption != .default {
            invalidateCache()
        }
    }
    
    private func _calculateSortedApps() -> [(source: ASRepository, app: ASRepository.App)] {
        let byCategory = selectedCategory.map { category in
            _allAppsWithSource.filter { $0.app.category == category }
        } ?? _allAppsWithSource
        
        let filtered = byCategory.filter {
            searchText.isEmpty ||
            ($0.app.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.app.description?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.app.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.app.localizedDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        
        switch sortOption {
        case .default:
            _groupedAppsByDate = [:]
            _groupedAppsByNameFirstLetter = [:]
            _sortedSectionTitles = []
            // Every category opens on what was updated most recently rather
            // than on whatever order the source happened to hand over. It stays
            // one flat section — the Date option is what breaks the list into
            // day headers.
            return filtered.sorted {
                let d1 = $0.app.currentDate?.date ?? .distantPast
                let d2 = $1.app.currentDate?.date ?? .distantPast
                return sortAscending ? (d1 > d2) : (d1 < d2)
            }
        case .date:
            let sorted = filtered.sorted {
                let d1 = $0.app.currentDate?.date ?? .distantPast
                let d2 = $1.app.currentDate?.date ?? .distantPast
                return sortAscending ? (d1 < d2) : (d1 > d2)
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            
            let grouped = Dictionary(grouping: sorted) {
                $0.app.currentDate?.date.stripTime() ?? .distantPast
            }
            
            let sortedDates = grouped.keys.sorted(by: { sortAscending ? $0 > $1 : $0 < $1 })
            
            _groupedAppsByDate = grouped.reduce(into: [:]) { result, pair in
                let key = formatter.string(from: pair.key)
                result[key] = pair.value
            }
            
            _sortedSectionTitles = sortedDates.map { formatter.string(from: $0) }
            return sorted
        case .name:
            let sorted = filtered.sorted {
                let n1 = $0.app.name ?? ""
                let n2 = $1.app.name ?? ""
                let comparison = n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
                return sortAscending ? comparison : !comparison
            }
            _groupedAppsByNameFirstLetter = Dictionary(grouping: sorted) {
                let first = $0.app.name?.trimmingCharacters(in: .whitespacesAndNewlines).first?.uppercased() ?? "#"
                return first.range(of: "[A-Z]", options: .regularExpression) != nil ? first : "#"
            }
            _sortedSectionTitles = _groupedAppsByNameFirstLetter.keys.sorted(by: {
                if $0 == "#" { return false }
                if $1 == "#" { return true }
                return sortAscending ? $0 < $1 : $0 > $1
            })
            return sorted
        }
    }
    
    func invalidateCache() {
        _cachedSortedApps = _calculateSortedApps()
        if let tableView = uiTableView {
            UIView.transition(with: tableView, duration: 0.3, options: [.transitionCrossDissolve], animations: {
                tableView.reloadData()
            })
        }
    }
    
    // MARK: TableView
    
    func numberOfSections(in tableView: UITableView) -> Int {
        switch sortOption {
        case .default: 1
        case .name, .date: _sortedSectionTitles.count
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sortOption {
        case .default: _sortedApps.count
        case .name: _groupedAppsByNameFirstLetter[_sortedSectionTitles[section]]?.count ?? 0
        case .date: _groupedAppsByDate[_sortedSectionTitles[section]]?.count ?? 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AppCell", for: indexPath)
        let entry: (source: ASRepository, app: ASRepository.App)
        switch sortOption {
        case .default: entry = _sortedApps[indexPath.row]
        case .name: entry = _groupedAppsByNameFirstLetter[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
        case .date: entry = _groupedAppsByDate[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
        }

        cell.contentConfiguration = UIHostingConfiguration {
            SourceAppsCellView(source: entry.source, app: entry.app)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if #available(iOS 17, *) {
            tableView.deselectRow(at: indexPath, animated: true)
            
            let entry: (source: ASRepository, app: ASRepository.App)
            switch sortOption {
            case .default: entry = _sortedApps[indexPath.row]
            case .name: entry = _groupedAppsByNameFirstLetter[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
            case .date: entry = _groupedAppsByDate[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
            }
            
            onSelect(SourceAppsView.SourceAppRoute(source: entry.source, app: entry.app))
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader")
        let title: String
        
        switch sortOption {
        case .default: title = .localized("%lld Apps", arguments: _sortedApps.count)
        case .name, .date: title = _sortedSectionTitles[section]
        }
        
        headerView?.contentConfiguration = UIHostingConfiguration {
            HStack {
                Text(verbatim: title)
                Spacer()
            }
            .font(.headline)
            .padding(.vertical, 2)
        }
        
        return headerView
    }
    
    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        sortOption == .name ? _sortedSectionTitles : nil
    }
    
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        _sortedSectionTitles.firstIndex(of: title) ?? 0
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let entry: (source: ASRepository, app: ASRepository.App)
        switch sortOption {
        case .default: entry = _sortedApps[indexPath.row]
        case .name: entry = _groupedAppsByNameFirstLetter[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
        case .date: entry = _groupedAppsByDate[_sortedSectionTitles[indexPath.section]]?[indexPath.row] ?? _sortedApps[indexPath.row]
        }
        
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil
        ) { _ in
            let downloadsMenu = UIMenu(
                title: .localized("Previous Versions"),
                image: UIImage(systemName: "square.and.arrow.down.on.square"),
                children: self._contextActions(for: entry.app, with: { version in
                    if let url = version {
                        _ = DownloadManager.shared.startDownload(
                            from: url,
                            id: entry.app.currentUniqueId
                        )
                    }
                }, image: UIImage(systemName: "arrow.down"))
            )
            
            return UIMenu(children: [downloadsMenu])
        }
    }
    
    // MARK: Actions
    
    private func _contextActions(
        for app: ASRepository.App,
        with action: @escaping (URL?) -> Void,
        image: UIImage?
    ) -> [UIAction] {
        if let versions = app.versions, !versions.isEmpty {
            return versions.map { version in
                UIAction(
                    title: version.version,
                    image: image
                ) { _ in
                    action(version.downloadURL)
                }
            }
        } else {
            return [
                UIAction(
                    title: app.currentVersion ?? "",
                    image: image
                ) { _ in
                    action(app.currentDownloadUrl)
                }
            ]
        }
    }
}}
