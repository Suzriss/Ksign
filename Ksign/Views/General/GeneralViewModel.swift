//
//  GeneralViewModel.swift
//  Ksign
//
//  What the General page shows: the products from the admin panel.
//

import Foundation
import NimbleExtensions

/// Loads what the page shows: `/api/sign/products`, the store the admin panel
/// publishes. The device card the web page carries lives in Settings here, and
/// the sources the tab now lists come from Core Data.
///
/// The products come straight from the admin panel, so nothing here decides
/// what is on sale — the page only renders what the panel publishes, in the
/// order the panel gives it.
@MainActor
final class GeneralViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false
    
    private var _hasLoaded = false
    
    /// The Telegram account the website's order button writes to.
    static let telegramUser = "useceresify"
    private static let _orderText = "مرحبا اريد شراء هذا المنتج"
    
    struct Product: Identifiable, Hashable {
        let id: String
        let name: String
        let price: String?
        let details: String?
        let imageURL: URL?
        
        /// Same link the website's "اشترِ الآن" button opens.
        var orderURL: URL? {
            var components = URLComponents(string: "https://t.me/\(GeneralViewModel.telegramUser)")
            components?.queryItems = [
                URLQueryItem(name: "text", value: "\(GeneralViewModel._orderText) \(name)")
            ]
            return components?.url
        }
    }
    
    func load(force: Bool = false) async {
        guard force || !_hasLoaded else { return }
        _hasLoaded = true
        
        isLoading = true
        didFail = false
        
        defer { isLoading = false }
        
        do {
            let url = CeresifyAPI.baseURL.appendingPathComponent("api/sign/products")
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(_ProductsResponse.self, from: data)
            
            products = response.products
                .filter { $0.isActive ?? true }
                .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                .map { $0.product }
        } catch {
            didFail = true
            
            if products.isEmpty {
                _hasLoaded = false
            }
        }
    }
}

// MARK: - Extension: decoding
private extension GeneralViewModel {
    struct _ProductsResponse: Decodable {
        let products: [_Product]
    }
    
    struct _Product: Decodable {
        let _id: String
        let name: String?
        let imageUrl: String?
        let price: String?
        let description: String?
        let isActive: Bool?
        let order: Int?
        
        var product: Product {
            Product(
                id: _id,
                name: name?.nilIfBlank ?? .localized("Unknown"),
                price: price?.nilIfBlank,
                details: description?.nilIfBlank,
                imageURL: Self._url(imageUrl)
            )
        }
        
        /// Uploads come back as site-relative paths.
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
    }
}

// MARK: - Extension: String
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
