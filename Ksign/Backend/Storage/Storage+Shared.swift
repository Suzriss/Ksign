//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData

// MARK: - Class extension: Apps (Shared)
extension Storage {
	func getUuidDirectory(for app: AppInfoPresentable) -> URL? {
		guard let uuid = app.uuid else { return nil }
		return app.isSigned
		? FileManager.default.signed(uuid)
		: FileManager.default.unsigned(uuid)
	}
	
	func getAppDirectory(for app: AppInfoPresentable) -> URL? {
		guard let url = getUuidDirectory(for: app) else { return nil }
		return FileManager.default.getPath(in: url, for: "app")
	}
	
	func deleteApp(for app: AppInfoPresentable) {
		do {
			if let url = getUuidDirectory(for: app) {
				try? FileManager.default.removeItem(at: url)
			}
			if let object = app as? NSManagedObject {
				context.delete(object)
			}
			saveContext()
		}
	}
	
	/// Most recently signed build carrying this bundle identifier, if any.
	///
	/// Matching is by identifier because nothing links a signed build back to the
	/// source entry it came from. Signing options that rewrite the identifier
	/// (PPQ protection, a custom identifier) therefore break the match — those
	/// builds stay reachable from the Library as before.
	func latestSigned(forIdentifier identifier: String) -> Signed? {
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.predicate = NSPredicate(format: "identifier == %@", identifier)
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
		request.fetchLimit = 1
		return (try? context.fetch(request))?.first
	}
	
	/// Most recently imported (unsigned) build carrying this bundle identifier.
	func latestImported(forIdentifier identifier: String) -> Imported? {
		let request: NSFetchRequest<Imported> = Imported.fetchRequest()
		request.predicate = NSPredicate(format: "identifier == %@", identifier)
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
		request.fetchLimit = 1
		return (try? context.fetch(request))?.first
	}
	
	/// Clears out everything left behind once an app is on the device: the build
	/// that was installed, any unsigned copy it was signed from, and the archive
	/// the download left on disk. Only call this after an install actually
	/// succeeded — it is not recoverable without downloading again.
	func cleanUpAfterInstall(for app: AppInfoPresentable) {
		let identifier = app.identifier
		
		deleteApp(for: app)
		
		if let identifier {
			if
				let imported = latestImported(forIdentifier: identifier),
				imported.uuid != app.uuid
			{
				deleteApp(for: imported)
			}
			
			if
				app.isSigned == false,
				let signed = latestSigned(forIdentifier: identifier)
			{
				deleteApp(for: signed)
			}
		}
		
		removeDownloadedArchives()
	}
	
	/// Drops the `.ipa` files the downloader parked on disk. They are only ever
	/// an intermediate step towards an imported app, so nothing references them
	/// once the install is done.
	func removeDownloadedArchives() {
		let fileManager = FileManager.default
		
		let directories = [
			fileManager.temporaryDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true),
			URL.documentsDirectory.appendingPathComponent("Downloads")
		]
		
		for directory in directories {
			guard
				let contents = try? fileManager.contentsOfDirectory(
					at: directory,
					includingPropertiesForKeys: nil
				)
			else {
				continue
			}
			
			for url in contents where ["ipa", "tipa"].contains(url.pathExtension.lowercased()) {
				try? fileManager.removeItem(at: url)
			}
		}
	}
	
	/// Everything the Signer tab is holding: the builds waiting to be signed,
	/// the ones already signed, and the archives they were unpacked from.
	///
	/// Every app in that tab is kept twice over — the downloaded `.ipa` plus the
	/// uncompressed copy it was unpacked into — so a handful of them is enough to
	/// reach several hundred megabytes that nothing ever reclaims. They are only
	/// ever a step on the way to an install, so clearing them costs a re-download
	/// and nothing else.
	///
	/// Certificates, sources and settings are deliberately untouched: the store
	/// stays usable exactly as it was.
	func clearSignerContents() {
		let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
		let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
		
		let signed = (try? context.fetch(signedRequest)) ?? []
		let imported = (try? context.fetch(importedRequest)) ?? []
		
		for object in signed { context.delete(object) }
		for object in imported { context.delete(object) }
		
		// Saved here rather than through `saveContext()`, which hops to the main
		// queue — at launch this runs before the Signer tab reads the context,
		// and it has to be consistent by the time it does.
		try? context.save()
		
		let fileManager = FileManager.default
		try? fileManager.removeFileIfNeeded(at: fileManager.signed)
		try? fileManager.removeFileIfNeeded(at: fileManager.unsigned)
		
		removeDownloadedArchives()
	}
	
	/// What `clearSignerContents()` would reclaim, for the confirmation to show
	/// before anything is deleted.
	func signerContentsSize() -> Int64 {
		let fileManager = FileManager.default
		
		return [
			fileManager.signed,
			fileManager.unsigned,
			fileManager.temporaryDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true),
			URL.documentsDirectory.appendingPathComponent("Downloads")
		].reduce(Int64(0)) { $0 + fileManager.directorySize(at: $1) }
	}
	
	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? {
		if let signed = app as? Signed {
			return signed.certificate
		}
		return nil
	}
}

// MARK: - Helpers
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var archive: Bool = false
	var signAndInstall: Bool = false
	
	var id: String {
		base.uuid ?? UUID().uuidString
	}
}

protocol AppInfoPresentable {
	var name: String? { get }
	var version: String? { get }
	var identifier: String? { get }
	var date: Date? { get }
	var icon: String? { get }
	var uuid: String? { get }
	/// Where the build was downloaded from, when it came from a source.
	///
	/// A bundle identifier does not name one app: a store lists several builds
	/// of the same app under it — YouTube, YouTube Reborn, YTLite — and they
	/// only differ by the URL they came from. Both entities already store this;
	/// the protocol carries it so a signed build keeps the imported one's.
	var source: URL? { get }
	var isSigned: Bool { get }
	
}

extension Signed: AppInfoPresentable {
	var isSigned: Bool { true }
}

extension Imported: AppInfoPresentable {
	var isSigned: Bool { false }
}
