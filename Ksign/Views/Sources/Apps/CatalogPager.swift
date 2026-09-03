//
//  CatalogPager.swift
//  Ksign
//
//  The shop's catalog, read a page at a time.
//

import Foundation
import AltSourceKit
import NimbleJSON

/// Walks the shop's catalog twenty-five apps at a time.
///
/// The catalog is ten thousand apps and six megabytes of JSON. Asking for all
/// of it at once is what left most subscribers looking at "nothing to show":
/// on a bar or two of signal the request never finished, and the one that did
/// still had to decode the lot before a single row could be drawn.
///
/// So the store asks for a page instead — a category, a search, an order and a
/// page number — and the server answers with the same AltStore shape it always
/// did, carrying only the apps for that page. Scrolling to the end asks for the
/// next one. Twenty-five apps is about twenty kilobytes.
@MainActor
final class CatalogPager: ObservableObject {
    /// One instance for the whole app: the store keeps what it has read across
    /// tab switches, and the launch can prime the first page before the Apps
    /// tab is ever opened.
    static let shared = CatalogPager()
    
    static let perPage = 25
    
    /// What is being asked for. A change to any of it starts again from the
    /// first page.
    struct Query: Equatable {
        var category: String?
        var search: String = ""
        var sort: SourceAppsView.SortOption = .default
        var ascending: Bool = true
        var language: String = ""
    }
    
    /// The catalog as far as it has been read: the source's own details, its
    /// banners and its categories, with the apps of every page read so far.
    ///
    /// Kept even when a page comes back empty — an empty category still has to
    /// draw the strip that got the user into it, or there is no way back out.
    @Published private(set) var repository: ASRepository?
    @Published private(set) var categories: [SourceAppsCategoryStrip.Category] = []
    /// The first page is on its way and there is nothing to show yet.
    @Published private(set) var isLoading = false
    /// A further page is on its way, under what is already on screen.
    @Published private(set) var isLoadingMore = false
    /// The last attempt brought nothing at all — the store is unreachable,
    /// rather than empty.
    @Published private(set) var didFail = false
    /// How many apps the whole query has, which is what the list's header says.
    @Published private(set) var total = 0
    @Published private(set) var hasMore = false
    
    private(set) var url: URL?
    private var _query = Query()
    private var _page = 0
    private var _task: Task<Void, Never>?
    /// Which question the answer coming back belongs to. A cancelled read
    /// still resumes once to unwind itself, and without this it would clear
    /// the flags — and the reference — of the read that replaced it.
    private var _generation = 0
    
    private init() {
        url = Storage.builtInSourceURLs.first.flatMap(URL.init(string:))
    }
    
    // MARK: Asking
    
    /// Points the pager at the catalog it should read. Anything already read
    /// from a different URL is dropped.
    func configure(_ url: URL?) {
        guard let url, url != self.url else { return }
        
        self.url = url
        _task?.cancel()
        _task = nil
        repository = nil
        _page = 0
    }
    
    /// Reads the first page unless something has already been read.
    func start(_ query: Query) {
        guard repository == nil, _task == nil else { return }
        _query = query
        _reload()
    }
    
    /// Puts a new question — a category, a search, an order — and starts again
    /// from the first page. Does nothing when nothing has actually changed.
    func apply(_ query: Query) {
        if query == _query {
            // The same question: only worth asking again if nothing came of it
            // and nothing is in the air.
            guard repository == nil, _task == nil else { return }
        }
        
        _query = query
        _reload()
    }
    
    /// The refresh button: the same question, asked again from the top.
    func refresh() {
        _reload(force: true)
    }
    
    /// The list is near its end, so fetch what comes after it.
    func loadMore() {
        guard
            hasMore,
            !isLoading,
            !isLoadingMore,
            _task == nil
        else {
            return
        }
        
        let generation = _generation
        _task = Task { await _load(page: _page + 1, force: false, generation: generation) }
    }
    
    private func _reload(force: Bool = false) {
        _task?.cancel()
        _generation += 1
        
        // Said here rather than inside the task: the task's first line doesn't
        // run until the next turn of the loop, and for that one frame the store
        // would be neither loading nor holding anything — which draws the
        // "didn't answer" screen over a store that is answering fine.
        isLoading = true
        didFail = false
        
        let generation = _generation
        _task = Task { await _load(page: 1, force: force, generation: generation) }
    }
    
    // MARK: Fetching
    
    private func _load(page: Int, force: Bool, generation: Int) async {
        guard let pageURL = _url(for: page) else {
            isLoading = false
            _task = nil
            return
        }
        
        let isFirst = page == 1
        
        if isFirst {
            isLoading = true
            didFail = false
            
            // The copy stored the last time this exact page was asked for, so
            // the store opens on apps instead of on a spinner — and still has
            // something to show when the answer never comes.
            if !force, let stored = SourceCache.rawData(for: pageURL) {
                _accept(stored, page: 1)
                isLoading = repository == nil
            }
        } else {
            isLoadingMore = true
        }
        
        defer {
            // A read that has already been replaced unwinds quietly: the flags
            // and the task reference belong to whatever replaced it.
            if generation == _generation {
                isLoading = false
                isLoadingMore = false
                _task = nil
            }
        }
        
        // A weak signal drops the first request often enough that giving up on
        // it is what the store's empty screen actually was. One more go, after
        // a breath.
        var attempt: (Data, URLResponse)?
        
        for delay in [0, 2] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if Task.isCancelled { return }
            
            attempt = try? await Self._session.data(for: _request(pageURL, revalidating: isFirst && !force))
            if attempt != nil { break }
        }
        
        guard !Task.isCancelled, generation == _generation else { return }
        
        guard
            let (data, response) = attempt,
            let http = response as? HTTPURLResponse
        else {
            didFail = repository == nil
            return
        }
        
        // The stored copy of this page is still the current one.
        if http.statusCode == 304 {
            hasMore = _hasMoreFromStore(pageURL) ?? hasMore
            return
        }
        
        guard (200..<300).contains(http.statusCode) else {
            didFail = repository == nil
            return
        }
        
        _accept(data, page: page)
        
        // Only a page that stands on its own gets stored: a search is typed
        // once and would fill the cache with answers nobody asks for twice.
        if isFirst, _query.search.isEmpty {
            SourceCache.store(data, etag: http.value(forHTTPHeaderField: "ETag"), for: pageURL)
        }
    }
    
    /// Takes a page's bytes and folds them into what is on screen.
    private func _accept(_ data: Data, page: Int) {
        let meta = try? JSONDecoder().decode(_PageMeta.self, from: data)
        // A page with no apps at all — an empty category — doesn't decode as a
        // repository: the format insists a source has apps. That is a fine
        // answer here, so it is read for its numbers and its shell is kept.
        let repo = try? JSONDecoder().decode(ASRepository.self, from: data)
        
        if page == 1 {
            if let repo {
                repository = repo
                categories = SourceAppsCategoryStrip.declared(in: repo)
                    ?? SourceAppsCategoryStrip.categories(from: [repo])
            } else {
                // Keep the banner and the strip, drop the rows: the way back
                // out of an empty category is the strip itself.
                repository?.apps = []
            }
        } else if let repo {
            repository?.apps.append(contentsOf: repo.apps)
        }
        
        _page = page
        total = meta?.totalApps ?? repository?.apps.count ?? 0
        hasMore = meta?.hasMore ?? false
        didFail = false
    }
    
    private func _hasMoreFromStore(_ url: URL) -> Bool? {
        guard let data = SourceCache.rawData(for: url) else { return nil }
        return (try? JSONDecoder().decode(_PageMeta.self, from: data))?.hasMore
    }
    
    private func _request(_ url: URL, revalidating: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        for (field, value) in NBFetchService.headerProvider?(url) ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        if revalidating, let tag = SourceCache.etag(for: url) {
            request.setValue(tag, forHTTPHeaderField: "If-None-Match")
        }
        
        return request
    }
    
    /// The catalog's URL carrying the page being asked for.
    private func _url(for page: Int) -> URL? {
        guard
            let url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        
        var items = components.queryItems?.filter {
            !["lang", "page", "perPage", "category", "q", "sort", "asc"].contains($0.name)
        } ?? []
        
        items.append(URLQueryItem(name: "lang", value: _query.language))
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "perPage", value: String(Self.perPage)))
        items.append(URLQueryItem(name: "sort", value: _query.sort.rawValue))
        items.append(URLQueryItem(name: "asc", value: _query.ascending ? "1" : "0"))
        
        if let category = _query.category, !category.isEmpty {
            items.append(URLQueryItem(name: "category", value: category))
        }
        
        let search = _query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            items.append(URLQueryItem(name: "q", value: search))
        }
        
        components.queryItems = items
        return components.url
    }
    
    /// Its own session, for the same reason the whole-source fetch has one: the
    /// shared one gives up after a minute of silence and never tries again.
    private static let _session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    
    /// The numbers the catalog adds to the AltStore shape so the list knows
    /// where it is.
    private struct _PageMeta: Decodable {
        var page: Int?
        var perPage: Int?
        var totalApps: Int?
        var hasMore: Bool?
    }
}
