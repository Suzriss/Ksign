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

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	private let _dataService = NBFetchService()
	
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
	@Published var sources: [AltSource: ASRepository] = [:]
	
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		
		// What is held was fetched in one language. Picking another in
		// Preferences has to go back to the server for it — the descriptions
		// are part of the payload, not something the app can translate.
		let language = LanguageManager.shared.effectiveCode
		let languageChanged = _fetchedLanguage != nil && _fetchedLanguage != language
		let mustRefetch = refresh || languageChanged
		
		// check if sources to be fetched are the same as before, if yes, return
		// also skip check if refresh is true
		if !mustRefetch, sources.allSatisfy({ self.sources[$0] != nil }) { return }
		
		_fetchedLanguage = language
		
		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		defer { isFinished = true }
		
		await MainActor.run {
			self.sources = [:]
		}
		
		let sourcesArray = Array(sources)
		
		for startIndex in stride(from: 0, to: sourcesArray.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, sourcesArray.count)
			let batch = sourcesArray[startIndex..<endIndex]
			
			let batchResults = await withTaskGroup(of: (AltSource, ASRepository?).self, returning: [AltSource: ASRepository].self) { group in
				for source in batch {
					group.addTask {
						guard let url = source.sourceURL.map(Self._localized) else {
							return (source, nil)
						}
						
						return await withCheckedContinuation { continuation in
							self._dataService.fetch(from: url) { (result: RepositoryDataHandler) in
								switch result {
								case .success(let repo):
									continuation.resume(returning: (source, repo))
								case .failure(_):
									continuation.resume(returning: (source, nil))
								}
							}
						}
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
			
			await MainActor.run {
				for (source, repo) in batchResults {
					self.sources[source] = repo
				}
			}
		}
	}
}
