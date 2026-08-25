//
//  CeresifyCloudSigner.swift
//  Ksign
//
//  Signing a Ceresify build on the server instead of on the device.
//

import Foundation
import AltSourceKit
import NimbleExtensions

/// What the server needs to find the build it is being asked to sign.
enum CeresifySignSource: Hashable {
    /// One of the apps uploaded to Ceresify — the server already holds the file.
    case appId(String)
    /// Anything the server can fetch itself, which is how the CheckOver
    /// catalog is signed: the download URL points back at Ceresify.
    case ipaURL(URL)
}

enum CeresifySignError: LocalizedError {
    case notRegistered
    case needsSubscription(String)
    case server(String)
    
    var errorDescription: String? {
        switch self {
        case .notRegistered:
            return .localized("Register your device first, then try again.")
        case .needsSubscription(let message), .server(let message):
            return message
        }
    }
}

/// Hands a build to Ceresify to be signed with the account's certificate and
/// installed straight from the manifest it returns.
///
/// Builds the user brought themselves are never sent anywhere — those stay on
/// the device and go through the local signer, same as before. Only what
/// Ceresify already hosts is signed in the cloud.
enum CeresifyCloudSigner {
    /// The cloud path applies to builds that live on Ceresify. A source app
    /// carrying a download URL anywhere else is somebody else's, so it stays
    /// local.
    static func source(for app: ASRepository.App) -> CeresifySignSource? {
        guard
            let url = app.currentDownloadUrl,
            let host = url.host,
            host == CeresifyAPI.baseURL.host
        else {
            return nil
        }
        
        return .ipaURL(url)
    }
    
    /// Returns the `itms-services` URL iOS installs from.
    static func sign(_ source: CeresifySignSource) async throws -> URL {
        guard let udid = CeresifyEnrollmentModel.storedUdid else {
            throw CeresifySignError.notRegistered
        }
        
        var fields = ["udid": udid]
        
        switch source {
        case .appId(let id):    fields["appId"] = id
        case .ipaURL(let url):  fields["ipaUrl"] = url.absoluteString
        }
        
        var request = URLRequest(url: CeresifyAPI.baseURL.appendingPathComponent("api/sign/"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self._formBody(fields)
        // The server fetches and signs the build inside the request, which for
        // a large app is minutes rather than seconds.
        request.timeoutInterval = 600
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = try? JSONDecoder().decode(_Response.self, from: data)
        
        if
            let http = response as? HTTPURLResponse,
            !(200..<300).contains(http.statusCode)
        {
            let message = payload?.message ?? payload?.error ?? .localized("Signing failed.")
            
            if payload?.needsSubscription == true {
                throw CeresifySignError.needsSubscription(message)
            }
            
            throw CeresifySignError.server(message)
        }
        
        guard
            let payload,
            payload.ok == true,
            let install = payload.installUrl,
            let url = URL(string: install)
        else {
            throw CeresifySignError.server(payload?.error ?? .localized("Signing failed."))
        }
        
        return url
    }
    
    private struct _Response: Decodable {
        let ok: Bool?
        let installUrl: String?
        let error: String?
        let message: String?
        let needsSubscription: Bool?
    }
    
    private static func _formBody(_ fields: [String: String]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        
        return fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}
