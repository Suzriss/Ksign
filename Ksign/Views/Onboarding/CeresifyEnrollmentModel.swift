//
//  CeresifyEnrollmentModel.swift
//  Ksign
//
//  Registering the device with Ceresify and pulling its certificate.
//

import Foundation
import SwiftUI
import NimbleExtensions

/// Drives the same registration the website does, from inside the app.
///
/// Apple only hands a device's UDID to a Profile Service, and only Safari can
/// install one, so the profile is opened outside the app and the result is
/// waited on here. This walks the same path the website's start page does:
/// `/api/device/nekoo-enroll?token=` opens the session and redirects to the
/// nekoo profile, and `/api/device/resolve?token=` reports the UDID back once
/// the profile phones home. Once the UDID lands, the account's certificate is
/// fetched and imported, which is what the user would otherwise be doing by
/// hand with two files and a password.
///
/// Every endpoint it touches already existed for the website — nothing here
/// changes what subscribers get.
@MainActor
final class CeresifyEnrollmentModel: ObservableObject {
    enum Step: Equatable {
        case intro
        /// Profile handed to Safari; waiting for the device to report in.
        case waiting
        case fetchingCertificate
        case installed
        /// Registered, but the account carries no certificate yet.
        case noCertificate(isSubscribed: Bool)
        case failed(String)
    }
    
    @Published private(set) var step: Step = .intro
    
    /// Kept so a later launch can go straight for the certificate instead of
    /// asking the user to install the profile a second time. Plain defaults
    /// rather than `@AppStorage`, which only tracks changes inside a view.
    private enum _Keys {
        static let udid = "Ceresify.udid"
        static let deviceName = "Ceresify.deviceName"
        /// The website keeps the same token around so a user who wanders off
        /// mid-install can come back to a screen that still resolves.
        static let enrollToken = "Ceresify.enrollToken"
    }
    
    private var _enrollToken: String?
    private var _pollTask: Task<Void, Never>?
    
    private static let _pollInterval: Duration = .seconds(3)
    private static let _pollTimeout: TimeInterval = 10 * 60
    
    /// Readable from anywhere: the cloud signer needs it as much as this
    /// screen does.
    nonisolated static var storedUdid: String? {
        UserDefaults.standard.string(forKey: _Keys.udid)?.nilIfEmpty
    }
    
    var storedUdid: String? {
        Self.storedUdid
    }
    
    var deviceName: String? {
        UserDefaults.standard.string(forKey: _Keys.deviceName)?.nilIfEmpty
    }
    
    // MARK: Registration
    
    /// Hands the profile to Safari and starts waiting for the device to report.
    func register() {
        let token = Self._makeEnrollToken()
        _enrollToken = token
        UserDefaults.standard.set(token, forKey: _Keys.enrollToken)
        
        var components = URLComponents(
            url: CeresifyAPI.baseURL.appendingPathComponent("api/device/nekoo-enroll"),
            resolvingAgainstBaseURL: false
        )
        // `from=settings` is what makes the callback finish on the server's
        // "تم تسجيل جهازك بنجاح" page instead of bouncing Safari into the
        // website's start flow — the app is the thing to come back to.
        components?.queryItems = [
            URLQueryItem(name: "from", value: "settings"),
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let url = components?.url else {
            step = .failed(.localized("Couldn't reach the server."))
            return
        }
        
        // The server answers with a redirect to the nekoo profile, which only
        // Safari can install.
        UIApplication.open(url)
        step = .waiting
        _startPolling(token: token)
    }
    
    /// Called when the app comes back to the front: the user may have installed
    /// the profile while this screen sat in the background.
    func resumeIfPending() {
        guard step == .waiting || step == .intro else { return }
        
        guard
            storedUdid == nil,
            let token = _enrollToken ?? UserDefaults.standard.string(forKey: _Keys.enrollToken)?.nilIfEmpty
        else {
            return
        }
        
        _enrollToken = token
        step = .waiting
        _startPolling(token: token)
    }
    
    /// Picks up where a previous launch left off: the device is known, so only
    /// the certificate is missing.
    func fetchCertificateForStoredDevice() {
        guard let udid = storedUdid else { return }
        Task { await _fetchCertificate(udid: udid) }
    }
    
    func cancel() {
        _pollTask?.cancel()
        _pollTask = nil
        
        if step == .waiting {
            step = .intro
        }
    }
    
    // MARK: Polling
    
    private func _startPolling(token: String) {
        _pollTask?.cancel()
        
        _pollTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self._pollTimeout)
            
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: Self._pollInterval)
                
                if Task.isCancelled { return }
                
                guard let result = await Self._resolve(token: token) else { continue }
                
                await self?._deviceDidRegister(udid: result.udid, deviceName: result.deviceName)
                return
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if self?.step == .waiting {
                    self?.step = .failed(.localized("Registration timed out. Try again."))
                }
            }
        }
    }
    
    private func _deviceDidRegister(udid: String, deviceName: String?) async {
        UserDefaults.standard.removeObject(forKey: _Keys.enrollToken)
        UserDefaults.standard.set(udid, forKey: _Keys.udid)
        UserDefaults.standard.set(deviceName ?? "", forKey: _Keys.deviceName)
        await _fetchCertificate(udid: udid)
    }
    
    // MARK: Certificate
    
    private func _fetchCertificate(udid: String) async {
        step = .fetchingCertificate
        
        do {
            let info = try await Self._certificateInfo(udid: udid)
            
            guard info.hasCert else {
                step = .noCertificate(isSubscribed: info.subscribed)
                return
            }
            
            let p12 = try await Self._download(kind: "p12", udid: udid, filename: "ceresify.p12")
            let provision = try await Self._download(
                kind: "mobileprovision",
                udid: udid,
                filename: "ceresify.mobileprovision"
            )
            
            guard FR.checkPasswordForCertificate(for: p12, with: info.password, using: provision) else {
                step = .failed(.localized("The certificate's password was rejected."))
                return
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                FR.handleCertificateFiles(
                    p12URL: p12,
                    provisionURL: provision,
                    p12Password: info.password,
                    certificateName: "Ceresify"
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            step = .installed
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
    
    // MARK: Requests
    
    private struct _PollResult {
        let udid: String
        let deviceName: String?
    }
    
    private struct _ResolveResponse: Decodable {
        let ok: Bool?
        let udid: String?
        let deviceName: String?
    }
    
    private struct _CertificateInfo: Decodable {
        let hasCert: Bool
        let password: String
        let subscribed: Bool
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hasCert = try container.decodeIfPresent(Bool.self, forKey: .hasCert) ?? false
            self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
            self.subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
        }
        
        enum CodingKeys: String, CodingKey {
            case hasCert, password, subscribed
        }
    }
    
    private static func _resolve(token: String) async -> _PollResult? {
        var components = URLComponents(
            url: CeresifyAPI.baseURL.appendingPathComponent("api/device/resolve"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        
        guard let url = components?.url else { return nil }
        
        // The answer flips from `{"ok":false}` to the UDID the moment the
        // profile reports in, so a plain miss is not an error.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let response = try? JSONDecoder().decode(_ResolveResponse.self, from: data),
            response.ok == true,
            let udid = response.udid,
            !udid.isEmpty
        else {
            return nil
        }
        
        return _PollResult(udid: udid, deviceName: response.deviceName)
    }
    
    private static func _certificateInfo(udid: String) async throws -> _CertificateInfo {
        var components = URLComponents(
            url: CeresifyAPI.baseURL.appendingPathComponent("api/device/my-cert/info"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "udid", value: udid)]
        
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(_CertificateInfo.self, from: data)
    }
    
    private static func _download(kind: String, udid: String, filename: String) async throws -> URL {
        var components = URLComponents(
            url: CeresifyAPI.baseURL
                .appendingPathComponent("api/device/my-cert")
                .appendingPathComponent(kind),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "udid", value: udid)]
        
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if
            let http = response as? HTTPURLResponse,
            !(200..<300).contains(http.statusCode)
        {
            throw URLError(.resourceUnavailable)
        }
        
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ceresify-enrollment", isDirectory: true)
        
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let file = destination.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        
        return file
    }
    
    /// The website hands nekoo a 32-character hex token; the server matches on
    /// exactly that shape when the profile comes back.
    private static func _makeEnrollToken() -> String {
        (0..<16)
            .map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }
            .joined()
    }
}

// MARK: - Extension: String
private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
