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
    /// The rows the Settings page links out to. Empty keeps the ones the app
    /// shipped with, so a shop that never fills this in loses nothing.
    var accounts: [Account] = []
    /// What the shop has to say to this device, newest first.
    var notifications: [Notification] = []
    /// The sheets the shop wants shown over the store.
    var popups: [Popup] = []
    /// Where each build is signed — on the server, or on the device.
    var signing = Signing()
    /// The rating box: whether it is offered at all, and whether it is asked
    /// for rather than waited for.
    var review = Review()
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
        accounts = (try? container.decodeIfPresent([Account].self, forKey: .accounts)) ?? []
        notifications = (try? container.decodeIfPresent([Notification].self, forKey: .notifications)) ?? []
        popups = (try? container.decodeIfPresent([Popup].self, forKey: .popups)) ?? []
        signing = (try? container.decodeIfPresent(Signing.self, forKey: .signing)) ?? Signing()
        review = (try? container.decodeIfPresent(Review.self, forKey: .review)) ?? Review()
        requireCertificate = container.flag(.requireCertificate)
        requireCertificateMessage = container.string(.requireCertificateMessage)
    }
    
    enum CodingKeys: String, CodingKey {
        case theme, splash, strings, maintenance, marquee, countdowns
        case accounts, notifications, popups
        case signing, review
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
    
    /// One of the store's own accounts, as the Settings page lists it.
    struct Account: Decodable, Equatable, Identifiable {
        var id = ""
        var title = ""
        /// A name, not an SF Symbol: the panel picks from a short list and the
        /// app decides what to draw for it, so a symbol renamed in a future
        /// iOS can't leave an empty square in the list.
        var icon = "link"
        var color = ""
        var url = ""
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            title = container.string(.title)
            icon = {
                let value = container.string(.icon)
                return value.isEmpty ? "link" : value
            }()
            color = container.string(.color)
            url = container.string(.url)
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, icon, color, url
        }
    }
    
    /// Something the shop wants said to this device.
    ///
    /// There is no APNs here — the app is signed with a certificate that isn't
    /// ours, so Apple never hands it a token — so a notice rides down with the
    /// config instead and is raised locally the first time it is seen.
    struct Notification: Decodable, Equatable, Identifiable {
        var id = ""
        var title = ""
        var message = ""
        var url = ""
        var createdAt: Date?
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            title = container.string(.title)
            message = container.string(.message)
            url = container.string(.url)
            createdAt = CeresifyConfig._date(from: container.string(.createdAt))
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, message, url, createdAt
        }
    }
    
    /// A sheet shown over the store, a set number of times per device.
    struct Popup: Decodable, Equatable, Identifiable {
        var id = ""
        var title = ""
        var message = ""
        var imageURL = ""
        var buttonText = ""
        var buttonURL = ""
        /// How many times one device sees it. Zero means without limit.
        var maxShows = 1
        var endsAt: Date?
        /// `auto`, `left` or `right` — where the dismiss button sits.
        var closeSide = "auto"
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            title = container.string(.title)
            message = container.string(.message)
            imageURL = container.string(.imageURL)
            buttonText = container.string(.buttonText)
            buttonURL = container.string(.buttonURL)
            maxShows = (try? container.decodeIfPresent(Int.self, forKey: .maxShows)) ?? 1
            closeSide = {
                let value = container.string(.closeSide)
                return ["auto", "left", "right"].contains(value) ? value : "auto"
            }()
            endsAt = CeresifyConfig._date(from: container.string(.endsAt))
        }
        
        /// Whether it still has anything to say, given how often this device
        /// has already seen it.
        func isDue(shown: Int) -> Bool {
            if let endsAt, endsAt <= Date() { return false }
            guard maxShows > 0 else { return true }
            return shown < maxShows
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, message, imageURL, buttonText, buttonURL
            case maxShows, endsAt, closeSide
        }
    }
    
    /// Where a build is signed.
    ///
    /// The server signs with the account's own certificate and hands back an
    /// install link, which is the fast path and the only one that works with
    /// no certificate on the device. The device signs locally, which is slower
    /// and needs the whole IPA down first — but it is the only place the
    /// signer's own options (tweaks, dylibs, the property toggles) can be
    /// applied at all.
    struct Signing: Decodable, Equatable {
        enum Place: String, Equatable {
            case server
            case device
        }
        
        /// `auto`, `server` or `device`.
        var mode = "auto"
        /// Anything bigger than this signs on the device whatever the mode
        /// says. Zero means no limit.
        var localAboveMB: Double = 0
        /// The apps the shop has decided about one by one.
        var rules: [Rule] = []
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = {
                let value = container.string(.mode)
                return ["auto", "server", "device"].contains(value) ? value : "auto"
            }()
            localAboveMB = (try? container.decodeIfPresent(Double.self, forKey: .localAboveMB)) ?? 0
            rules = (try? container.decodeIfPresent([Rule].self, forKey: .rules)) ?? []
        }
        
        enum CodingKeys: String, CodingKey {
            case mode, localAboveMB, rules
        }
        
        struct Rule: Decodable, Equatable {
            var bundleIdentifier = ""
            /// `server` or `device`.
            var mode = "server"
            
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bundleIdentifier = container.string(.bundleIdentifier)
                mode = container.string(.mode) == "device" ? "device" : "server"
            }
            
            enum CodingKeys: String, CodingKey {
                case bundleIdentifier = "bundleId"
                case mode
            }
        }
        
        /// Where this build belongs.
        ///
        /// A rule written for the app itself wins outright — it is the most
        /// specific thing the shop said. The size limit comes next, because it
        /// exists precisely to override the general answer for the builds that
        /// are too big to push through the server. `isOurs` is only consulted
        /// by `auto`: a shop that has explicitly said "server" means the
        /// server, and it can fetch a build from anywhere.
        func place(bundleIdentifier: String?, sizeBytes: Int64?, isOurs: Bool) -> Place {
            if
                let bundleIdentifier,
                !bundleIdentifier.isEmpty,
                let rule = rules.first(where: { $0.bundleIdentifier == bundleIdentifier })
            {
                return rule.mode == "device" ? .device : .server
            }
            
            if
                localAboveMB > 0,
                let sizeBytes,
                Double(sizeBytes) > localAboveMB * 1_000_000
            {
                return .device
            }
            
            switch mode {
            case Place.server.rawValue: return .server
            case Place.device.rawValue: return .device
            default:                    return isOurs ? .server : .device
            }
        }
    }
    
    /// The box that asks what the user makes of the app.
    ///
    /// It is the same box wherever it appears — Settings, or over the store on
    /// a launch — and what it collects goes to `/api/reviews`, which holds it
    /// for the panel to approve.
    struct Review: Decodable, Equatable {
        /// The row in Settings.
        var enabled = false
        /// Raised by itself when the app is opened.
        var showOnLaunch = false
        /// No way past it but to answer.
        var requireAnswer = false
        /// How many launches it is raised on. Zero is without limit; a device
        /// that has already sent one is never asked again either way.
        var maxShows = 1
        var title = ""
        var message = ""
        var placeholder = ""
        var buttonText = ""
        var thanks = ""
        /// Whether the server has a rating from this device. Nil from a
        /// server that doesn't say — or for a device it has never seen —
        /// in which case the device's own record is all there is.
        var answered: Bool? = nil
        
        init() {}
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = container.flag(.enabled)
            showOnLaunch = container.flag(.showOnLaunch)
            requireAnswer = container.flag(.requireAnswer)
            maxShows = (try? container.decodeIfPresent(Int.self, forKey: .maxShows)) ?? 1
            title = container.string(.title)
            message = container.string(.message)
            placeholder = container.string(.placeholder)
            buttonText = container.string(.buttonText)
            thanks = container.string(.thanks)
            answered = try? container.decodeIfPresent(Bool.self, forKey: .answered)
        }
        
        enum CodingKeys: String, CodingKey {
            case enabled, showOnLaunch, requireAnswer, maxShows
            case title, message, placeholder, buttonText, thanks
            case answered
        }
    }
    
    /// The server writes ISO 8601; `Date.ISO8601FormatStyle` only takes one
    /// shape at a time, so both are tried rather than losing a countdown to a
    /// fractional second.
    static func _date(from string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        
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
    /// Whether this launch started already knowing what to draw.
    ///
    /// A fresh install doesn't: it opens on nothing, and every answer about
    /// the store — its colours, whether it opens at all — is still in the
    /// post. That is the one launch with a wait worth putting a screen in
    /// front of, and it is over as soon as the first answer lands.
    let hasStoredConfig: Bool

    private static let _cacheKey = "Ceresify.appConfig"
    /// The notices this device has already been shown, so one raised on a
    /// launch isn't raised again on the next.
    private static let _seenKey = "Ceresify.seenNotifications"
    /// How many times each popup has been put in front of this device.
    private static let _popupShowsKey = "Ceresify.popupShows"
    private var _isLoading = false
    
    private init() {
        let stored = UserDefaults.standard.data(forKey: Self._cacheKey)
            .flatMap { try? JSONDecoder().decode(_CeresifyConfigResponse.self, from: $0) }

        hasStoredConfig = stored?.config != nil
        config = stored?.config ?? CeresifyConfig()
        device = stored?.device ?? CeresifyDeviceStatus()

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
            
            _syncReviewState()
            
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
    
    // MARK: Notices
    
    /// The notices the shop has sent this device, newest first.
    var notifications: [CeresifyConfig.Notification] {
        config.notifications
    }
    
    private var _seenIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self._seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self._seenKey) }
    }
    
    /// How many of them have never been opened.
    var unreadNotificationCount: Int {
        let seen = _seenIdentifiers
        return config.notifications.filter { !seen.contains($0.id) }.count
    }
    
    func isUnread(_ notification: CeresifyConfig.Notification) -> Bool {
        !_seenIdentifiers.contains(notification.id)
    }
    
    /// The ones that have never been raised on this device, so the inbox can
    /// show them and iOS can be asked to put them on the lock screen once.
    ///
    /// Marking is separate from reading: a notice is only counted as delivered
    /// once it has actually been handed to the notification centre.
    func undeliveredNotifications() -> [CeresifyConfig.Notification] {
        let delivered = Set(UserDefaults.standard.stringArray(forKey: Self._seenKey + ".delivered") ?? [])
        return config.notifications.filter { !delivered.contains($0.id) }
    }
    
    func markDelivered(_ notifications: [CeresifyConfig.Notification]) {
        let key = Self._seenKey + ".delivered"
        var delivered = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        delivered.formUnion(notifications.map(\.id))
        UserDefaults.standard.set(Array(delivered), forKey: key)
    }
    
    func markRead(_ notification: CeresifyConfig.Notification) {
        guard isUnread(notification) else { return }
        
        var seen = _seenIdentifiers
        seen.insert(notification.id)
        _seenIdentifiers = seen
        objectWillChange.send()
    }
    
    func markAllRead() {
        _seenIdentifiers = Set(config.notifications.map(\.id))
        objectWillChange.send()
    }
    
    // MARK: Popups
    
    private var _popupShows: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: Self._popupShowsKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self._popupShowsKey) }
    }
    
    /// The next sheet owed to this device, if there is one.
    ///
    /// One at a time: two stacked over the store would be a wall rather than a
    /// notice, and the second is still owed on the next launch.
    var duePopup: CeresifyConfig.Popup? {
        let shows = _popupShows
        return config.popups.first { $0.isDue(shown: shows[$0.id] ?? 0) }
    }
    
    func markPopupShown(_ popup: CeresifyConfig.Popup) {
        var shows = _popupShows
        shows[popup.id] = (shows[popup.id] ?? 0) + 1
        _popupShows = shows
        objectWillChange.send()
    }
    
    // MARK: Rating
    
    private static let _reviewSentKey = "Ceresify.reviewSent"
    private static let _reviewShowsKey = "Ceresify.reviewShows"
    
    /// Whether this device has already had its say.
    ///
    /// Kept on the device, because the box has to be gone from the first
    /// frame of the next launch — well before any answer could come back.
    /// The server keeps the same fact against the device's UDID, and every
    /// config it sends brings it down again, so a reinstall doesn't get asked
    /// twice and the panel can ask one device again.
    var hasSentReview: Bool {
        UserDefaults.standard.bool(forKey: Self._reviewSentKey)
    }
    
    func markReviewSent() {
        UserDefaults.standard.set(true, forKey: Self._reviewSentKey)
        objectWillChange.send()
    }
    
    /// Brings the device's record into line with the server's.
    ///
    /// Only for a device the server knows: an unregistered one has nothing
    /// the server could hold a rating against, so its own record stands. A
    /// record the panel has cleared also clears the count of showings — a
    /// box that had used up its showings is owed them again.
    private func _syncReviewState() {
        guard device.known, let answered = config.review.answered else { return }
        guard answered != hasSentReview else { return }
        
        UserDefaults.standard.set(answered, forKey: Self._reviewSentKey)
        
        if !answered {
            _reviewShows = 0
        }
        
        objectWillChange.send()
    }
    
    private var _reviewShows: Int {
        get { UserDefaults.standard.integer(forKey: Self._reviewShowsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self._reviewShowsKey) }
    }
    
    /// Whether the box is owed a showing over the store right now.
    var isReviewDue: Bool {
        let review = config.review
        
        guard review.enabled, review.showOnLaunch, !hasSentReview else { return false }
        guard review.maxShows > 0 else { return true }
        
        return _reviewShows < review.maxShows
    }
    
    func markReviewShown() {
        _reviewShows += 1
        objectWillChange.send()
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
