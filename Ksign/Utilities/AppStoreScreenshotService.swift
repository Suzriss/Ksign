//
//  AppStoreScreenshotService.swift
//  Ksign
//
//  Screenshots for source apps, looked up from Apple by bundle identifier.
//

import Foundation
import OSLog

/// Sources rarely ship screenshots — the CheckOver catalog, for one, carries
/// only an icon — so we look them up from Apple's public iTunes endpoint using
/// the app's bundle identifier. Lookups happen lazily, per app detail screen,
/// and the result is memoised for the lifetime of the process.
actor AppStoreScreenshotService {
	static let shared = AppStoreScreenshotService()
	
	/// Cached per identifier. An empty array is a real answer ("Apple has none")
	/// and is cached too, so a miss is not retried on every visit.
	private var _cache: [String: [URL]] = [:]
	private var _inFlight: [String: Task<[URL], Never>] = [:]
	
	private init() {}
	
	func screenshots(forIdentifier identifier: String) async -> [URL] {
		if let cached = _cache[identifier] { return cached }
		if let running = _inFlight[identifier] { return await running.value }
		
		let task = Task<[URL], Never> { [identifier] in
			await Self._lookup(identifier: identifier)
		}
		_inFlight[identifier] = task
		
		let result = await task.value
		_cache[identifier] = result
		_inFlight[identifier] = nil
		
		return result
	}
	
	private static func _lookup(identifier: String) async -> [URL] {
		var components = URLComponents(string: "https://itunes.apple.com/lookup")
		components?.queryItems = [URLQueryItem(name: "bundleId", value: identifier)]
		
		guard let url = components?.url else { return [] }
		
		var request = URLRequest(url: url)
		request.timeoutInterval = 15
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			
			guard
				let http = response as? HTTPURLResponse,
				http.statusCode == 200
			else {
				return []
			}
			
			let decoded = try JSONDecoder().decode(_LookupResponse.self, from: data)
			
			guard let result = decoded.results.first else { return [] }
			
			// iPhone shots first; fall back to iPad for apps that ship only those.
			let strings = result.screenshotUrls.isEmpty
			? result.ipadScreenshotUrls
			: result.screenshotUrls
			
			return strings.compactMap(URL.init(string:))
		} catch {
			Logger.misc.error("Screenshot lookup failed for \(identifier): \(error)")
			return []
		}
	}
	
	private struct _LookupResponse: Decodable {
		let results: [Result]
		
		struct Result: Decodable {
			let screenshotUrls: [String]
			let ipadScreenshotUrls: [String]
			
			enum CodingKeys: String, CodingKey {
				case screenshotUrls, ipadScreenshotUrls
			}
			
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				self.screenshotUrls =
					try container.decodeIfPresent([String].self, forKey: .screenshotUrls) ?? []
				self.ipadScreenshotUrls =
					try container.decodeIfPresent([String].self, forKey: .ipadScreenshotUrls) ?? []
			}
		}
	}
}
