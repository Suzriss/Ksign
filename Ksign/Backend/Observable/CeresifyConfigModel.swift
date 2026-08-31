//
//  CeresifyConfigModel.swift
//  Ksign
//
//  What the store looks like and who it lets in, decided on the server.
//

import Foundation
import SwiftUI
import UIKit
import NimbleExtensions

/// Everything the admin panel can change about the app without a new build.
///
/// Every field has an empty default that means "leave it as the app already
/// has it", so a server that answers nothing — or doesn't answer at all —
/// leaves the store exactly as it shipped.
struct CeresifyConfig: Decodable, Equatable {
    var theme = Theme()
    var splash = Splash()
    var strings = Strings()
    var maintenance = Maintenance()
    var marquee = Marquee()
    var countdowns: [Countdown] = []
    /// Only devices carrying one of our certificates get past the gate.
    var requireCertificate = false
    var requireCertificateMessage = ""
    
    init() {}
    
    /// Written out rather than synthesized: a synthesized `init(from:)` throws
    /// on a key that isn't there instead of falling back to the property's
    /// default, which would mean one field added to the server — or one older
    /// copy read back off disk — losing the whole config.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? Theme()
        splash = (try? container.decodeIfPresent(Splash.self, forKey: .splash)) ?? Splash()
        strings = (try? container.decodeIfPresent(Strings.self, forKey: .strings)) ?? Strings()
        maintenance = (try? container.decodeIfPresent(Maintenance.self, forKey: .maintenance)) ?? Maintenance()
        marquee = (try? container.decodeIfPresent(Marquee.self, forKey: .marquee)) ?? Marquee()
        countdowns = (try? container.decodeIfPresent([Countdown].self, forKey: .countdowns)) ?? []
        requireCertificate = container.flag(.requireCertificate)
        requireCertificateMessage = container.string(.requireCertificateMessage)
    }
    
    enum CodingKeys: String, CodingKey {
        case theme, splash, strings, maintenance, marquee, countdowns
        case requireCertificate, requireCertificateMessage
    }
    
    struct Theme: Decodable, Equatable {
        var background = ""
        var text = ""
        var title = ""
        var subtitle = ""
        var accent = ""
        var logoURL = ""
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            background = container.string(.background)
            text = container.string(.text)
            title = container.string(.title)
            subtitle = container.string(.subtitle)
            accent = container.string(.accent)
            logoURL = container.string(.logoURL)
        }
        
        enum CodingKeys: String, CodingKey {
            case background, text, title, subtitle, accent, logoURL
        }
    }
    
    struct Splash: Decodable, Equatable {
        var enabled = false
        var imageURL = ""
        var title = ""
        var subtitle = ""
        var seconds: Double = 2
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = container.flag(.enabled)
            imageURL = container.string(.imageURL)
            title = container.string(.title)
            subtitle = container.string(.subtitle)
            seconds = (try? container.decodeIfPresent(Double.self, forKey: .seconds)) ?? 2
        }
        
        enum CodingKeys: String, CodingKey {
            case enabled, imageURL, title, subtitle, seconds
        }
    }
    
    /// The words on the store's own controls. Empty keeps the shipped string,
    /// which is the one that is actually translated into nine languages.
    struct Strings: Decodable, Equatable {
        var get = ""
        var sign = ""
        var install = ""
        var downloading = ""
        var offline = ""
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            get = container.string(.get)
            sign = container.string(.sign)
            install = container.string(.install)
            downloading = container.string(.downloading)
            offline = container.string(.offline)
        }
        
        enum CodingKeys: String, CodingKey {
            case get, sign, install, downloading, offline
        }
    }
    
    struct Maintenance: Decodable, Equatable {
        var enabled = false
        var title = ""
        var message = ""
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = container.flag(.enabled)
            title = container.string(.title)
            message = container.string(.message)
        }
        
        enum CodingKeys: String, CodingKey {
            case enabled, title, message
        }
    }
    
    struct Marquee: Decodable, Equatable {
        var enabled = false
        var text = ""
        /// Seconds for one full pass; larger is slower.
        var speed: Double = 14
        /// The categories it runs in. Empty means the whole store.
        var categories: [String] = []
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = container.flag(.enabled)
            text = container.string(.text)
            speed = (try? container.decodeIfPresent(Double.self, forKey: .speed)) ?? 14
            categories = (try? container.decodeIfPresent([String].self, forKey: .categories)) ?? []
        }
        
        /// Whether it belongs above a store list filtered to this category.
        ///
        /// A label pinned to categories has nothing to say on `All`, where no
        /// category is chosen — so it stays off there rather than following
        /// the user everywhere.
        func runs(in category: String?) -> Bool {
            guard enabled, !text.isEmpty else { return false }
            guard !categories.isEmpty else { return true }
            guard let category else { return false }
            
            return categories.contains(category)
        }
        
        enum CodingKeys: String, CodingKey {
            case enabled, text, speed, categories
        }
    }
    
    /// Where in the app something the shop set is shown.
    ///
    /// `appPages` and `app` both land on an app's own page — the first on
    /// every one of them, the second on a named app's alone.
    enum Placement: String {
        case appPages = "all"
        case app
        case general
        case home
        case store
    }
    
    /// A countdown shown either on every app's page or on one app's alone.
    struct Countdown: Decodable, Equatable, Identifiable {
        var id = ""
        var title = ""
        var message = ""
        var endsAt: Date?
        /// `all` or `app`.
        var scope = "all"
        var bundleIdentifier = ""
        
        enum CodingKeys: String, CodingKey {
            case id, title, message, endsAt, scope
            case bundleIdentifier = "bundleId"
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
            self.scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? "all"
            self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
            
            let raw = try container.decodeIfPresent(String.self, forKey: .endsAt)
            self.endsAt = raw.flatMap(CeresifyConfig._date(from:))
        }
        
        /// Whether this one belongs on the page being drawn.
        ///
        /// `bundleIdentifier` is the app that page is about, and is nil
        /// everywhere else — which is what keeps a countdown set for one app
        /// off the General and Home tabs.
        func applies(on placement: Placement, bundleIdentifier: String? = nil) -> Bool {
            guard let endsAt, endsAt > Date() else { return false }
            
            switch scope {
            case Placement.app.rawValue:
                return placement == .appPages
                    && !self.bundleIdentifier.isEmpty
                    && self.bundleIdentifier == bundleIdentifier
            default:
                return scope == placement.rawValue
            }
        }
    }
    
    /// The server writes ISO 8601; `Date.ISO8601FormatStyle` only takes one
    /// shape at a time, so both are tried rather than losing a countdown to a
    /// fractional second.
    static func _date(from string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

/// What the server knows about this device, answered alongside the config.
struct CeresifyDeviceStatus: Decodable, Equatable {
    var known = false
    var banned = false
    var banReason = ""
    var hasCert = false
    var subscribed = false
    
    init() {}
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        known = container.flag(.known)
        banned = container.flag(.banned)
        banReason = container.string(.banReason)
        hasCert = container.flag(.hasCert)
        subscribed = container.flag(.subscribed)
    }
    
    enum CodingKeys: String, CodingKey {
        case known, banned, banReason, hasCert, subscribed
    }
}

// MARK: - Extension: KeyedDecodingContainer
/// A missing or mistyped field falls back to the empty value rather than
/// throwing — one field the server hasn't shipped yet must not cost the store
/// its whole config.
private extension KeyedDecodingContainer {
    func string(_ key: Key) -> String {
        (try? decodeIfPresent(String.self, forKey: key)) ?? ""
    }
    
    func flag(_ key: Key) -> Bool {
        (try? decodeIfPresent(Bool.self, forKey: key)) ?? false
    }
}

private struct _CeresifyConfigResponse: Decodable {
    let ok: Bool?
    let config: CeresifyConfig?
    let device: CeresifyDeviceStatus?
}

/// Holds the config for the whole app and keeps the last answer on disk.
///
/// The stored copy is read back synchronously at startup, so the first frame is
/// already drawn in the colours the shop last chose rather than flashing the
/// defaults — and a launch with no signal keeps working from it.
/// Not actor-isolated: every view in the store reads a colour or a string off
/// it from inside a plain `body`, and the only place anything is written is
/// `load()`, which is pinned to the main actor.
final class CeresifyConfigManager: ObservableObject {
    static let shared = CeresifyConfigManager()
    
    @Published private(set) var config = CeresifyConfig()
    @Published private(set) var device = CeresifyDeviceStatus()
    /// Nil until the first answer of the launch, then whether it arrived.
    @Published private(set) var isReachable: Bool?
    /// Bumped whenever a fetch lands, so views holding no other state redraw.
    @Published private(set) var revision = 0
    
    private static let _cacheKey = "Ceresify.appConfig"
    private var _isLoading = false
    
    private init() {
        if
            let data = UserDefaults.standard.data(forKey: Self._cacheKey),
            let stored = try? JSONDecoder().decode(_CeresifyConfigResponse.self, from: data)
        {
            config = stored.config ?? CeresifyConfig()
            device = stored.device ?? CeresifyDeviceStatus()
        }
        
        CeresifyPalette.apply(config.theme)
    }
    
    /// Asks the server what the store should look like right now.
    ///
    /// Called at launch and every time the app comes back to the front, which
    /// is what makes maintenance and a ban take hold without a reinstall.
    @MainActor
    func load() async {
        guard !_isLoading else { return }
        _isLoading = true
        defer { _isLoading = false }
        
        var components = URLComponents(
            url: CeresifyAPI.baseURL.appendingPathComponent("api/app-config"),
            resolvingAgainstBaseURL: false
        )
        
        if let udid = CeresifyEnrollmentModel.storedUdid {
            components?.queryItems = [URLQueryItem(name: "udid", value: udid)]
        }
        
        guard let url = components?.url else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue(CeresifyAPI.catalogKey, forHTTPHeaderField: CeresifyAPI.catalogKeyHeader)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Reachability is about the network, not about the answer: a
            // server that hasn't got this endpoint yet is still reachable, and
            // saying otherwise would put an offline notice in front of every
            // user of the store.
            isReachable = true
            
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let payload = try? JSONDecoder().decode(_CeresifyConfigResponse.self, from: data),
                let loaded = payload.config
            else {
                return
            }
            
            let changed = loaded != config
            
            config = loaded
            device = payload.device ?? CeresifyDeviceStatus()
            
            // Only a real change bumps the revision: the app rebuilds its tree
            // on it, and doing that on every trip to the foreground would
            // throw away wherever the user had navigated to.
            if changed {
                revision += 1
                CeresifyPalette.apply(config.theme)
            }
            
            UserDefaults.standard.set(data, forKey: Self._cacheKey)
        } catch {
            // The stored copy stays on screen — a dropped connection is not a
            // reason to throw the shop's colours away.
            isReachable = false
        }
    }
    
    // MARK: Reading
    
    /// A string the panel overrode, or the app's own translated one.
    func text(_ override: String, fallback: String) -> String {
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
    
    /// The countdowns belonging on the given page, soonest ending first.
    func countdowns(
        on placement: CeresifyConfig.Placement,
        bundleIdentifier: String? = nil
    ) -> [CeresifyConfig.Countdown] {
        config.countdowns
            .filter { $0.applies(on: placement, bundleIdentifier: bundleIdentifier) }
            .sorted { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
    }
    
    /// Why the store should refuse to open, if it should.
    enum Gate: Equatable {
        case open
        case maintenance(title: String, message: String)
        case banned(reason: String)
        /// The device isn't one of ours — either the server has never seen it,
        /// or it carries no certificate from us.
        case notOurs(title: String, message: String)
    }
    
    var gate: Gate {
        if config.maintenance.enabled {
            return .maintenance(
                title: text(config.maintenance.title, fallback: .localized("Under maintenance")),
                message: text(
                    config.maintenance.message,
                    fallback: .localized("The store is closed for a moment. Try again shortly.")
                )
            )
        }
        
        if device.banned {
            return .banned(reason: device.banReason)
        }
        
        // Only worth refusing once the server has actually said so about this
        // device — an unreachable server must not lock anybody out.
        guard config.requireCertificate, isReachable == true else {
            return .open
        }
        
        // A copy signed for one subscriber already knows whose device it is,
        // so the question the app asks itself here is simply whether the
        // server knows that UDID. It doesn't: nothing on the device can fix
        // that, so the shop's own wording is what gets shown.
        if !device.known {
            return .notOurs(
                title: .localized("This device isn't registered"),
                message: text(
                    config.requireCertificateMessage,
                    fallback: .localized("This copy wasn't issued to this device. Get in touch to have it registered.")
                )
            )
        }
        
        if !device.hasCert {
            return .notOurs(
                title: .localized("Members only"),
                message: text(
                    config.requireCertificateMessage,
                    fallback: .localized("Register your device to open the store.")
                )
            )
        }
        
        return .open
    }
}

// MARK: - Palette
/// The colours the store draws with, held outside SwiftUI so `Color.ceresifyGold`
/// and the UIKit bars can read them from anywhere.
///
/// Written only from the main thread, when a config lands.
enum CeresifyPalette {
    /// What the app shipped with: gold type on a dark ground.
    static let defaultGold = UIColor(red: 0xF4 / 255, green: 0xC7 / 255, blue: 0x73 / 255, alpha: 1)
    static let defaultTitle = UIColor.white
    static let defaultSubtitle = UIColor.white.withAlphaComponent(0.72)
    
    static var gold = defaultGold
    static var title = defaultTitle
    static var subtitle = defaultSubtitle
    static var accent = defaultGold
    /// Nil keeps the system's own grouped background, which is what every list
    /// in the app is drawn on.
    static var background: UIColor?
    
    static func apply(_ theme: CeresifyConfig.Theme) {
        gold = UIColor(hexString: theme.text) ?? defaultGold
        title = UIColor(hexString: theme.title) ?? defaultTitle
        subtitle = UIColor(hexString: theme.subtitle) ?? defaultSubtitle
        accent = UIColor(hexString: theme.accent) ?? gold
        background = UIColor(hexString: theme.background)
    }
}

// MARK: - Extension: UIColor
extension UIColor {
    /// `#RRGGBB` or `#RRGGBBAA`, with or without the hash. Anything else is
    /// nil, which every caller reads as "keep the shipped colour".
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        
        guard
            hex.count == 6 || hex.count == 8,
            let value = UInt64(hex, radix: 16)
        else {
            return nil
        }
        
        let hasAlpha = hex.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
