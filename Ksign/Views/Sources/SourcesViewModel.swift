//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON
import CryptoKit

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	/// The language the held repositories were fetched in, so a change in
	/// Preferences is known to need a new fetch.
	private var _fetchedLanguage: String?
	
	/// Asks a Ceresify source for the language the app is set to.
	///
	/// An AltStore source is one file with one description per app, so the
	/// language has to be chosen when it is fetched rather than when it is
	/// shown. Only Ceresify's own host understands the parameter — anyone
	/// else's source is requested exactly as it was added.
	private static func _localized(_ url: URL) -> URL {
		guard
			url.host == CeresifyAPI.baseURL.host,
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return url
		}
		
		var items = components.queryItems ?? []
		items.removeAll { $0.name == "lang" }
		items.append(URLQueryItem(name: "lang", value: LanguageManager.shared.effectiveCode))
		components.queryItems = items
		
		return components.url ?? url
	}
	
	var isFinished = true
	/// Whether a fetch is running right now, published on the main actor.
	///
	/// `isFinished` is written from whatever thread starts a fetch, so it can't
	/// be published — and a view watching it saw the flip only by accident,
	/// whenever something else redrew it. That is what left the store on
	/// `Fetching…` for good when the catalog came back empty: nothing ever told
	/// it the wait was over.
	@Published private(set) var isFetching = false
	@Published var sources: [AltSource: ASRepository] = [:]
	/// Moves on every write to `sources`, so a page can follow what is held
	/// without comparing ten thousand apps to find out whether anything did.
	@Published private(set) var revision = 0
	
	/// Takes a plain array rather than the fetch request's own results: the
	/// store asks for the shop's catalog alone, which is a filtered slice of
	/// what Core Data hands back.
	///
	/// The copy stored on the last run is put up first, so the store opens on
	/// it while the fresh one is fetched — and when the server says the stored
	/// one is still current, that is the whole trip.
	func fetchSources(_ sources: [AltSource], refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		
		// The shop's own catalog is not fetched here any more. It is ten
		// thousand apps and six megabytes, and pulling all of it before a
		// single row could be drawn is what left the store empty on a weak
		// signal — `CatalogPager` asks it for twenty-five apps at a time
		// instead. Everyone else's source is still one file, fetched whole.
		let sources = sources.filter { source in
			source.sourceURL.map { !CeresifyAPI.isOurs($0) } ?? true
		}
		
		// What is held was fetched in one language. Picking another in
		// Preferences has to go back to the server for it — the descriptions
		// are part of the payload, not something the app can translate.
		let language = LanguageManager.shared.effectiveCode
		let languageChanged = _fetchedLanguage != nil && _fetchedLanguage != language
		let mustRefetch = refresh || languageChanged
		
		let held = self.sources
		
		// check if sources to be fetched are the same as before, if yes, return
		// also skip check if refresh is true
		if !mustRefetch, sources.allSatisfy({ held[$0] != nil }) { return }
		
		_fetchedLanguage = language
		
		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		defer { isFinished = true }
		
		let requests = sources.compactMap { source in
			source.sourceURL.map { (source: source, url: Self._localized($0)) }
		}
		
		// What was loaded last, straight off the disk: the store opens on it
		// while the fresh copy is on its way, instead of on a spinner for the
		// whole of the round trip. A language change skips it — the stored
		// copy is in the language that was just left.
		if !languageChanged {
			var cached = [AltSource: ASRepository]()
			
			for request in requests where held[request.source] == nil {
				if let repo = SourceCache.load(request.url) {
					cached[request.source] = repo
				}
			}
			
			if !cached.isEmpty {
				await MainActor.run {
					for (source, repo) in cached where self.sources[source] == nil {
						self.sources[source] = repo
					}
					self.revision += 1
				}
			}
		}
		
		await MainActor.run {
			self.isFetching = true
			// A source that has been removed goes; the rest stay on screen
			// until their fresh copy lands, rather than blinking out to a
			// spinner on every refresh.
			self.sources = self.sources.filter { entry in sources.contains(entry.key) }
		}
		
		defer {
			Task { @MainActor in self.isFetching = false }
		}
		
		for startIndex in stride(from: 0, to: requests.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, requests.count)
			let batch = requests[startIndex..<endIndex]
			let shown = self.sources
			
			let batchResults = await withTaskGroup(of: (AltSource, ASRepository?).self, returning: [AltSource: ASRepository].self) { group in
				for request in batch {
					// Only a copy that is actually on screen is worth a
					// "not modified" — a stored one that failed to decode is
					// nothing to fall back on.
					let hasCopy = !languageChanged && shown[request.source] != nil
					
					group.addTask {
						(request.source, await Self._fetch(request.url, revalidating: hasCopy))
					}
				}
				
				var results = [AltSource: ASRepository]()
				for await (source, repo) in group {
					if let repo {
						results[source] = repo
					}
				}
				return results
			}
			
			guard !batchResults.isEmpty else { continue }
			
			await MainActor.run {
				for (source, repo) in batchResults {
					self.sources[source] = repo
				}
				self.revision += 1
			}
		}
	}
	
	/// The session the catalog comes down on.
	///
	/// The catalog is megabytes, and most of the people opening the store are
	/// on a bar or two of signal: the shared session gave up after a minute
	/// of silence and never tried again, which is the "nothing to show"
	/// screen most subscribers were meeting. This one waits for a connection
	/// to come back, allows a trickle five minutes to finish, and keeps no
	/// cache of its own — the store keeps that.
	private static let _session: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.waitsForConnectivity = true
		configuration.timeoutIntervalForRequest = 45
		configuration.timeoutIntervalForResource = 300
		configuration.urlCache = nil
		return URLSession(configuration: configuration)
	}()
	
	/// One trip for one source. Nil means "keep what you have": a failure, or
	/// the server saying the stored copy is still the current one.
	private static func _fetch(_ url: URL, revalidating: Bool) async -> ASRepository? {
		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		
		for (field, value) in NBFetchService.headerProvider?(url) ?? [:] {
			request.setValue(value, forHTTPHeaderField: field)
		}
		
		if revalidating, let tag = SourceCache.etag(for: url) {
			request.setValue(tag, forHTTPHeaderField: "If-None-Match")
		}
		
		var attempt: (Data, URLResponse)?
		
		// A dropped connection gets one more go after a breath, rather than
		// the whole store being written off on the first hiccup.
		for delay in [0, 2] {
			if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
			if Task.isCancelled { return nil }
			
			attempt = try? await _session.data(for: request)
			if attempt != nil { break }
		}
		
		guard
			let (data, response) = attempt,
			let http = response as? HTTPURLResponse
		else {
			return nil
		}
		
		// The catalog hasn't moved since it was stored: nothing to decode
		// and nothing to swap in.
		guard http.statusCode != 304 else { return nil }
		guard (200..<300).contains(http.statusCode) else { return nil }
		
		guard let repo = try? JSONDecoder().decode(ASRepository.self, from: data) else {
			return nil
		}
		
		SourceCache.store(data, etag: http.value(forHTTPHeaderField: "ETag"), for: url)
		return repo
	}
}

// MARK: - Cache
/// The last copy of each source, kept on disk so the store opens on it.
///
/// Raw bytes rather than a decoded model: `ASRepository` only decodes, and the
/// bytes are what the server's `ETag` describes. Keyed by the full URL — the
/// language rides in it, so each language keeps a copy of its own.
enum SourceCache {
	private static var _directory: URL {
		let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		let directory = base.appendingPathComponent("SourceCache", isDirectory: true)
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
	
	private static func _file(for url: URL, suffix: String) -> URL {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		let name = digest.map { String(format: "%02x", $0) }.joined()
		return _directory.appendingPathComponent(name + suffix)
	}
	
	static func load(_ url: URL) -> ASRepository? {
		guard let data = rawData(for: url) else { return nil }
		return try? JSONDecoder().decode(ASRepository.self, from: data)
	}
	
	/// The stored bytes themselves, for a caller that reads more out of them
	/// than the repository — the paged catalog also stores how many apps the
	/// page it came from was one of.
	static func rawData(for url: URL) -> Data? {
		try? Data(contentsOf: _file(for: url, suffix: ".json"))
	}
	
	/// The tag to revalidate this URL with, and only when the copy it
	/// describes is still here.
	///
	/// The bytes and the tag are two files, and iOS empties the caches
	/// directory whenever it likes — one of them can go without the other, and
	/// a device short on space loses the big one first. A tag on its own asks
	/// the server "still the same?", is told "yes, 304", and leaves the store
	/// with nothing to draw and nothing on the way: an empty store that stays
	/// empty through relaunches and through updates, because nothing in a new
	/// build clears the caches directory. So the tag is only handed out when
	/// the copy it belongs to can actually be read.
	static func etag(for url: URL) -> String? {
		guard
			FileManager.default.fileExists(atPath: _file(for: url, suffix: ".json").path),
			let tag = try? String(contentsOf: _file(for: url, suffix: ".etag"), encoding: .utf8)
		else {
			return nil
		}
		let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
	
	static func store(_ data: Data, etag: String?, for url: URL) {
		let tagFile = _file(for: url, suffix: ".etag")
		
		// The tag describes the bytes, so it is only worth keeping if the bytes
		// were kept. A full disk fails this write silently, and a tag left
		// behind from a copy that was never written is what turns the next
		// launch into a 304 with nothing behind it.
		do {
			try data.write(to: _file(for: url, suffix: ".json"), options: .atomic)
		} catch {
			try? FileManager.default.removeItem(at: tagFile)
			return
		}
		
		if let etag, !etag.isEmpty {
			try? etag.write(to: tagFile, atomically: true, encoding: .utf8)
		} else {
			try? FileManager.default.removeItem(at: tagFile)
		}
	}
	
	/// Drops what is held for a URL, bytes and tag together.
	static func forget(_ url: URL) {
		try? FileManager.default.removeItem(at: _file(for: url, suffix: ".json"))
		try? FileManager.default.removeItem(at: _file(for: url, suffix: ".etag"))
	}
}
