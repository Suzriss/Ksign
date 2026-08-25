//
//  HomeFeaturedViewModel.swift
//  Ksign
//
//  The featured apps behind the Home tab.
//

import Foundation
import AltSourceKit
import NimbleExtensions

/// Where the web app and the store both live.
enum CeresifyAPI {
    static let baseURL = URL(string: "https://dev.ceresify.com")!
    
    /// The catalog is served only to requests carrying this key. A source URL
    /// copied out of the app is useless on its own, which is the point — the
    /// old link was passed around the moment it landed on someone's clipboard.
    static let catalogKeyHeader = "X-Ceresify-Key"
    static let catalogKey = "bb891c627e2583384c95b535e1fa5f81b18928380517396c"
    
    /// Whether a request is one of ours, and so should carry the key.
    static func isOurs(_ url: URL) -> Bool {
        url.host == baseURL.host
    }
}

/// Loads the same list the web app's main page shows: `/api/sign/featured`.
///
/// Each entry is also handed back as an `ASRepository.App` so the card can
/// reuse the store's download button, which walks Get → Sign → Install and
/// tracks progress against Core Data on its own.
@MainActor
final class HomeFeaturedViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false
    
    private var _hasLoaded = false
    
    struct Item: Identifiable, Hashable {
        let id: String
        let name: String
        let subtitle: String?
        let note: String?
        let details: String?
        let version: String?
        let size: Int64?
        let date: Date?
        let imageURL: URL?
        let iconURL: URL?
        let isAvailable: Bool
        /// Nil when the entry carries nothing installable, which is what the
        /// web page marks as "التطبيق غير متوفر".
        let app: ASRepository.App?
        /// Ceresify signs its own uploads by id; the rest are signed from the
        /// URL the download button already carries.
        let cloudSource: CeresifySignSource?
    }
    
    func load(force: Bool = false) async {
        guard force || !_hasLoaded else { return }
        _hasLoaded = true
        
        isLoading = true
        didFail = false
        
        defer { isLoading = false }
        
        do {
            let url = CeresifyAPI.baseURL.appendingPathComponent("api/sign/featured")
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(_Response.self, from: data)
            
            items = response.featured.map { $0.item }
        } catch {
            didFail = true
            
            // A failed refresh keeps whatever is already on screen: an empty
            // list would read as "nothing featured", which is a different thing.
            if items.isEmpty {
                _hasLoaded = false
            }
        }
    }
}

// MARK: - Extension: decoding
private extension HomeFeaturedViewModel {
    struct _Response: Decodable {
        let featured: [_Featured]
    }
    
    struct _Featured: Decodable {
        let id: String
        let appId: String?
        let bundleId: String?
        let name: String?
        let subtitle: String?
        let note: String?
        let description: String?
        let version: String?
        let size: Int64?
        let date: String?
        let imageUrl: String?
        let iconUrl: String?
        let found: Bool?
        
        var item: Item {
            Item(
                id: id,
                name: name ?? bundleId ?? .localized("Unknown"),
                subtitle: subtitle?.nilIfBlank,
                note: note?.nilIfBlank,
                details: description?.nilIfBlank,
                version: version?.nilIfBlank,
                size: size,
                date: date.flatMap(Self._date(from:)),
                imageURL: Self._url(imageUrl),
                iconURL: Self._url(iconUrl),
                isAvailable: found ?? true,
                app: (found ?? true) ? _app : nil,
                cloudSource: appId?.nilIfBlank.map { CeresifySignSource.appId($0) }
            )
        }
        
        /// Rebuilds the entry as a source app so the shared download button can
        /// take it. Going through the decoder keeps the one initialiser
        /// `ASRepository.App` actually has.
        private var _app: ASRepository.App? {
            let download = CeresifyAPI.baseURL
                .appendingPathComponent("api/sign/featured/\(id)/ipa")
            
            var payload: [String: Any] = [
                "bundleIdentifier": bundleId?.nilIfBlank ?? id,
                "name": name ?? bundleId ?? "",
                "downloadURL": download.absoluteString
            ]
            
            if let subtitle = subtitle?.nilIfBlank { payload["subtitle"] = subtitle }
            if let description = description?.nilIfBlank { payload["localizedDescription"] = description }
            if let version = version?.nilIfBlank { payload["version"] = version }
            if let size, size > 0 { payload["size"] = size }
            if let icon = Self._url(iconUrl) { payload["iconURL"] = icon.absoluteString }
            
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let app = try? JSONDecoder().decode(ASRepository.App.self, from: data)
            else {
                return nil
            }
            
            return app
        }
        
        /// Icons and artwork come back as site-relative paths as often as not.
        private static func _url(_ string: String?) -> URL? {
            guard
                let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
                !string.isEmpty
            else {
                return nil
            }
            
            if string.hasPrefix("http://") || string.hasPrefix("https://") {
                return URL(string: string)
            }
            
            return URL(string: string, relativeTo: CeresifyAPI.baseURL)?.absoluteURL
        }
        
        private static let _isoFormatters: [ISO8601DateFormatter] = [
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter
            }(),
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                return formatter
            }()
        ]
        
        private static func _date(from string: String) -> Date? {
            for formatter in _isoFormatters {
                if let date = formatter.date(from: string) {
                    return date
                }
            }
            
            return nil
        }
    }
}

// MARK: - Extension: String
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
