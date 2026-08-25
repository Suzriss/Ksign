//
//  GeneralViewModel.swift
//  Ksign
//
//  What the web app's General page shows: the products from the admin panel,
//  and the device's own subscription card.
//

import Foundation
import NimbleExtensions

/// Loads the two things `general.html` loads: `/api/sign/products` for the
/// store, and `/api/device/info/<udid>` for the card at the top.
///
/// The products come straight from the admin panel, so nothing here decides
/// what is on sale — the page only renders what the panel publishes, in the
/// order the panel gives it.
@MainActor
final class GeneralViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var device: Device?
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
    
    struct Device: Hashable {
        let udid: String
        let name: String?
        let isSubscribed: Bool
        let expiry: Date?
    }
    
    func load(force: Bool = false) async {
        guard force || !_hasLoaded else { return }
        _hasLoaded = true
        
        isLoading = true
        didFail = false
        
        defer { isLoading = false }
        
        // The card is a nice-to-have; a device that never registered simply
        // doesn't have one, which is not a failure of the page.
        await _loadDevice()
        
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
    
    private func _loadDevice() async {
        guard let udid = CeresifyEnrollmentModel.storedUdid else {
            device = nil
            return
        }
        
        let url = CeresifyAPI.baseURL
            .appendingPathComponent("api/device/info")
            .appendingPathComponent(udid)
        
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(_DeviceResponse.self, from: data),
            payload.ok == true,
            let raw = payload.device
        else {
            // Registered here but unknown to the server: still show the UDID,
            // which is what the user needs when asking for a subscription.
            device = Device(udid: udid, name: nil, isSubscribed: false, expiry: nil)
            return
        }
        
        device = Device(
            udid: raw.udid ?? udid,
            name: raw.deviceName,
            isSubscribed: raw.isSubscribed ?? false,
            expiry: raw.subscriptionExpiry.flatMap(Self._date(from:))
        )
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
    
    struct _DeviceResponse: Decodable {
        let ok: Bool?
        let device: _Device?
    }
    
    struct _Device: Decodable {
        let udid: String?
        let deviceName: String?
        let isSubscribed: Bool?
        let subscriptionExpiry: String?
    }
}

// MARK: - Extension: String
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
