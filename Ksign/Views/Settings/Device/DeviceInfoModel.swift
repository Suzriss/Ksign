//
//  DeviceInfoModel.swift
//  Ksign
//
//  The device card the website's settings page shows, loaded from the same
//  endpoint.
//

import Foundation

/// Reads `/api/device/info/<udid>` — device name, UDID, subscription — for the
/// device this install registered.
///
/// A device the server has never seen still has a UDID worth showing: it is
/// exactly what the user is asked for when buying a subscription.
@MainActor
final class DeviceInfoModel: ObservableObject {
	struct Device: Hashable {
		let udid: String
		let name: String?
		let isSubscribed: Bool
		let expiry: Date?
	}
	
	@Published private(set) var device: Device?
	@Published private(set) var isLoading = false
	
	var isRegistered: Bool {
		CeresifyEnrollmentModel.storedUdid != nil
	}
	
	func load() async {
		guard let udid = CeresifyEnrollmentModel.storedUdid else {
			device = nil
			return
		}
		
		isLoading = true
		defer { isLoading = false }
		
		let url = CeresifyAPI.baseURL
			.appendingPathComponent("api/device/info")
			.appendingPathComponent(udid)
		
		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		
		guard
			let (data, response) = try? await URLSession.shared.data(for: request),
			let http = response as? HTTPURLResponse,
			(200..<300).contains(http.statusCode),
			let payload = try? JSONDecoder().decode(_Response.self, from: data),
			payload.ok == true,
			let raw = payload.device
		else {
			// Registered here but unknown to the server, or simply offline.
			device = Device(
				udid: udid,
				name: UserDefaults.standard.string(forKey: "Ceresify.deviceName")?.nilIfBlank,
				isSubscribed: false,
				expiry: nil
			)
			return
		}
		
		device = Device(
			udid: raw.udid ?? udid,
			name: raw.deviceName?.nilIfBlank,
			isSubscribed: raw.isSubscribed ?? false,
			expiry: raw.subscriptionExpiry.flatMap(Self._date(from:))
		)
	}
	
	// MARK: Decoding
	
	private struct _Response: Decodable {
		let ok: Bool?
		let device: _Device?
	}
	
	private struct _Device: Decodable {
		let udid: String?
		let deviceName: String?
		let isSubscribed: Bool?
		let subscriptionExpiry: String?
	}
	
	private static let _formatters: [ISO8601DateFormatter] = [
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
		for formatter in _formatters {
			if let date = formatter.date(from: string) {
				return date
			}
		}
		
		return nil
	}
}

// MARK: - Extension: String
private extension String {
	var nilIfBlank: String? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}
