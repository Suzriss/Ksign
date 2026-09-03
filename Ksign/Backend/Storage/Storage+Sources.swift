//
//  Storage+Sources.swift
//  Feather
//
//  Created by samara on 12.04.2025.
//

import CoreData
import AltSourceKit

// MARK: - Class extension: Sources
extension Storage {
	/// Retrieve sources in an array, we don't normally need this in swiftUI but we have it for the copy sources action
	func getSources() -> [AltSource] {
		let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
		return (try? context.fetch(request)) ?? []
	}
	
	func addSource(
		_ url: URL,
		name: String? = "Unknown",
		identifier: String,
		iconURL: URL? = nil,
		deferSave: Bool = false,
		isBuiltIn: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		if sourceExists(identifier) {
			completion(nil)
			print("ignoring \(identifier)")
			return
		}
		
		let new = AltSource(context: context)
		new.name = name
		new.date = Date()
		new.identifier = identifier
		new.sourceURL = url
		new.iconURL = iconURL
		new.setValue(isBuiltIn, forKey: "isBuiltIn")
		
		do {
			if !deferSave {
				try context.save()
			}
			completion(nil)
		} catch {
			completion(error)
		}
	}
	
	func addSource(
		_ url: URL,
		repository: ASRepository,
		id: String = "",
		deferSave: Bool = false,
		isBuiltIn: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		addSource(
			url,
			name: repository.name,
			identifier: !id.isEmpty
						? id
						: (repository.id ?? url.absoluteString),
			iconURL: repository.currentIconURL,
			deferSave: deferSave,
			isBuiltIn: isBuiltIn,
			completion: completion
		)
	}

	func addSources(
		repos: [URL: ASRepository],
		completion: @escaping (Error?) -> Void
	) {
		for (url, repo) in repos {
			addSource(
				url,
				repository: repo,
				deferSave: true,
				completion: { error in
					if let error {
						completion(error)
					}
				}
			)
		}
		
        saveContext()
        completion(nil)
	}


	/// The only source shipped with the app: Ceresify's CheckOver catalog.
	/// Everything the store lists comes from here, so this stays a single entry.
	///
	/// The old `/api/check0ver-repo/repo.json` path is gone — it leaked, and it
	/// answers nobody now. This one is gated on `CeresifyAPI.catalogKey`, so the
	/// URL alone opens nothing: without the header it answers 404 like any path
	/// that was never there.
	static let builtInSourceURLs = [
		"https://dev.ceresify.com/api/c0store-9f3a1d7c/repo.json"
	]

	func addBuiltInSources() {
		for urlString in Self.builtInSourceURLs {
			// Seeded off a single-app page, not off the whole catalog. Creating
			// the row only needs the source's name, identifier and icon, and
			// they ride on any page — but this used to pull all six megabytes
			// to read three fields, and when that failed on a weak signal the
			// row was never written, the migration had already marked itself
			// done, and the store asked for nothing ever again.
			FR.handleSource(
				Self.seedURL(for: urlString),
				storeAs: urlString,
				silent: true
			) { }
		}
	}
	
	/// The cheapest request that still describes a source: one app.
	static func seedURL(for urlString: String) -> String {
		guard
			let url = URL(string: urlString),
			CeresifyAPI.isOurs(url),
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return urlString
		}
		
		var items = components.queryItems?.filter { $0.name != "page" && $0.name != "perPage" } ?? []
		items.append(URLQueryItem(name: "page", value: "1"))
		items.append(URLQueryItem(name: "perPage", value: "1"))
		components.queryItems = items
		
		return components.url?.absoluteString ?? urlString
	}

	/// Drops every stored source. Used by the one-time migration that moves
	/// existing installs off the sources older builds seeded.
	func removeAllSources() {
		for source in getSources() {
			context.delete(source)
		}

		if context.hasChanges {
			try? context.save()
		}
	}

	func deleteSource(for source: AltSource) {
		context.delete(source)
		saveContext()
	}

	func sourceExists(_ identifier: String) -> Bool {
		let fetchRequest: NSFetchRequest<AltSource> = AltSource.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)

		do {
			let count = try context.count(for: fetchRequest)
			return count > 0
		} catch {
			print("Error checking if repository exists: \(error)")
			return false
		}
	}
}
