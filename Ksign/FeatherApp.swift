//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import OSLog
import IDeviceSwift
import NimbleJSON

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	let heartbeat = HeartbeatManager.shared
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var accentColorManager = AccentColorManager.shared
    @StateObject var extractManager = ExtractManager.shared
	@StateObject var logsManager = LogsManager.shared
	@StateObject var languageManager = LanguageManager.shared
	let storage = Storage.shared

	var body: some Scene {
		WindowGroup {
			VStack {
                ExtractHeaderView(extractManager: extractManager)
                    .transition(.move(edge: .top).combined(with: .opacity))
				DownloadHeaderView(downloadManager: downloadManager)
					.transition(.move(edge: .top).combined(with: .opacity))
				VariedTabbarView()
					.environment(\.managedObjectContext, storage.context)
					.onOpenURL(perform: _handleURL)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
			.animation(.smooth, value: downloadManager.manualDownloads.description)
            .animation(.smooth, value: extractManager.extractItems.description)
			// The store's own palette: gold type throughout, with app names and
			// their descriptions opting back out to white.
			.foregroundStyle(Color.ceresifyGold)
			.tint(Color.ceresifyGold)
			// Gold only carries on a dark ground, and Settings no longer offers
			// an appearance switch to get back out of a white one.
			.preferredColorScheme(.dark)
			// Rebuilt when the language changes, so a pick in Preferences shows
			// up without waiting for the app to be reopened.
			.environment(\.locale, languageManager.locale)
			.environment(\.layoutDirection, languageManager.layoutDirection)
			.id(languageManager.code)
			.onReceive(accentColorManager.objectWillChange) { _ in
				accentColorManager.updateGlobalTintColor()
			}
			.onAppear {
				accentColorManager.updateGlobalTintColor()
				_applyDarkAppearance()
				if logsManager.isCapturing { logsManager.startCapture() }
			}
		}
	}
	
	/// UIKit is presented outside SwiftUI's environment — alerts, document
	/// pickers, the installer's own screens — so the windows are told directly.
	private func _applyDarkAppearance() {
		_applyNavigationBarAppearance()
		
		DispatchQueue.main.async {
			UIApplication.shared.connectedScenes
				.compactMap { $0 as? UIWindowScene }
				.flatMap { $0.windows }
				.forEach { $0.overrideUserInterfaceStyle = .dark }
		}
	}
	
	/// A page's own title is drawn by `UINavigationBar`, which sits outside the
	/// SwiftUI hierarchy the gold `foregroundStyle` colours — so the bar is told
	/// the same palette directly. App names and their descriptions are drawn by
	/// SwiftUI and stay white.
	private func _applyNavigationBarAppearance() {
		let gold = UIColor.ceresifyGold
		let titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: gold]
		
		// The two backgrounds the system already uses: a material once the list
		// is scrolled under the bar, and nothing at all while a large title is
		// still at rest. Only the type colour changes.
		let scrolled = UINavigationBarAppearance()
		scrolled.configureWithDefaultBackground()
		scrolled.titleTextAttributes = titleAttributes
		scrolled.largeTitleTextAttributes = titleAttributes
		
		let atRest = UINavigationBarAppearance()
		atRest.configureWithTransparentBackground()
		atRest.titleTextAttributes = titleAttributes
		atRest.largeTitleTextAttributes = titleAttributes
		
		let bar = UINavigationBar.appearance()
		bar.standardAppearance = scrolled
		bar.compactAppearance = scrolled
		bar.scrollEdgeAppearance = atRest
		bar.compactScrollEdgeAppearance = atRest
		bar.tintColor = gold
	}
	
	private func _handleURL(_ url: URL) {
		if url.scheme == "ksign" {
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
			}
			
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(from: downloadURL, id: "FeatherManualDownload_\(UUID().uuidString)")
			}
		} else {
			if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
				if FileManager.default.isFileFromFileProvider(at: url) {
					guard url.startAccessingSecurityScopedResource() else { return }
					FR.handlePackageFile(url) { _ in }
				} else {
					FR.handlePackageFile(url) { _ in }
				}
				
				return
			}
			
            if url.pathExtension == "ksign" {
                UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Ksign certificate file (.ksign) is now unsupported from v1.5.1, please refer to use .p12 and .mobileprovision instead."))
            }
		}
	}
	
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        _installCatalogKey()
        _createPipeline()
        _createSourcesDirectory()
        _migrateSourcesIfNeeded()
        
        _clean()
        _cleanSignerContents()
        
        _copyServerCertificates()
        _addDefaultCertificates()

#if SERVER
        // fallback just in case xd
        _downloadSSLCertificates()
#endif
        return true
    }
    
    /// Signs every fetch aimed at Ceresify with the catalog key. Third-party
    /// sources keep going out bare — the key is ours to spend, not theirs to
    /// receive. Installed before the first fetch of the launch.
    private func _installCatalogKey() {
        NBFetchService.headerProvider = { url in
            guard CeresifyAPI.isOurs(url) else { return [:] }
            return [CeresifyAPI.catalogKeyHeader: CeresifyAPI.catalogKey]
        }
    }

    /// Bumped whenever the shipped source list changes, so existing installs
    /// re-seed instead of keeping whatever the previous build stored.
    private static let _sourcesMigrationKey = "ceresify.sourcesMigration.v2"

    /// Clears every stored source and seeds the CheckOver catalog. Older builds
    /// seeded four third-party sources (Nyasami, SideStore, LiveContainer,
    /// crystall1ne) which stay in Core Data forever otherwise, so the wipe is
    /// what actually moves upgraders onto the single Ceresify catalog.
    ///
    /// v2 re-runs it: the catalog moved off the path that leaked, and an
    /// install still holding the old one shows an empty store.
    private func _migrateSourcesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self._sourcesMigrationKey) else { return }

        Storage.shared.removeAllSources()
        Storage.shared.addBuiltInSources()

        defaults.set(true, forKey: Self._sourcesMigrationKey)
        defaults.set(true, forKey: "hasInitializedBuiltInSources")
    }
    
    private func _createPipeline() {
        DataLoader.sharedUrlCache.diskCapacity = 0
        
        let pipeline = ImagePipeline {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()
            let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache") // disk cache
            let imageCache = Nuke.ImageCache() // memory cache
            dataCache?.sizeLimit = 500 * 1024 * 1024
            imageCache.costLimit = 100 * 1024 * 1024
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = dataLoader
            $0.dataCachePolicy = .automatic
            $0.isStoringPreviewsInMemoryCache = false
        }
        
        ImagePipeline.shared = pipeline
    }
    
    private func _createSourcesDirectory() {
        let fileManager = FileManager.default
        
        let appDirectory = URL.documentsDirectory.appendingPathComponent("App")
        try? fileManager.createDirectoryIfNeeded(at: appDirectory)
        
        let directories = ["Signed", "Unsigned", "Archives", "Server", "Tweaks"].map {
            appDirectory.appendingPathComponent($0)
        }
        
        for url in directories {
            try? fileManager.createDirectoryIfNeeded(at: url)
        }
    }
    
    private func _clean() {
        let fileManager = FileManager.default
        let tmpDirectory = fileManager.temporaryDirectory
        
        if let files = try? fileManager.contentsOfDirectory(atPath: tmpDirectory.path()) {
            for file in files {
                try? fileManager.removeItem(atPath: tmpDirectory.appendingPathComponent(file).path())
            }
        }
    }
    
    /// Empties the Signer tab on every launch.
    ///
    /// A build sitting in that tab is held twice on disk — the downloaded `.ipa`
    /// and the uncompressed copy it was unpacked into — and nothing reclaimed it
    /// unless the app was actually installed, so the two steps of a single
    /// install could leave half a gigabyte behind indefinitely. Downloading and
    /// signing is the cheap part to repeat; the certificates and the store are
    /// what would actually hurt to lose, and those stay.
    ///
    /// Off for anyone who turned `Keep apps after signing` on.
    private func _cleanSignerContents() {
        guard !UserDefaults.standard.bool(forKey: AppFeaturesView.keepSignerAppsKey) else { return }
        Storage.shared.clearSignerContents()
    }
    
    private func _copyServerCertificates() {
        let fileManager = FileManager.default
        let serverDirectory = URL.documentsDirectory.appendingPathComponent("App/Server")
        
        try? fileManager.createDirectoryIfNeeded(at: serverDirectory)
        
        let filesToCopy = ["server.crt", "server.pem", "commonName.txt"]
        
        for fileName in filesToCopy {
            guard let bundleURL = Bundle.main.url(forResource: fileName.components(separatedBy: ".").first!, withExtension: fileName.components(separatedBy: ".").last!) else {
                print("File \(fileName) not found in app bundle")
                continue
            }
            
            let destinationURL = serverDirectory.appendingPathComponent(fileName)
            
            try? fileManager.removeItem(at: destinationURL)
            
            do {
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            } catch {
                print("Error copying \(fileName): \(error)")
            }
        }
    }
    
    private func _addDefaultCertificates() {
            guard
                UserDefaults.standard.bool(forKey: "feather.didImportDefaultCertificates") == false,
                let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
            else {
                return
            }
            
            do {
                let folderContents = try FileManager.default.contentsOfDirectory(
                    at: signingAssetsURL,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                
                for folderURL in folderContents {
                    guard folderURL.hasDirectoryPath else { continue }
                    
                    let certName = folderURL.lastPathComponent
                    
                    let p12Url = folderURL.appendingPathComponent("cert.p12")
                    let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
                    let passwordUrl = folderURL.appendingPathComponent("cert.txt")
                    
                    guard
                        FileManager.default.fileExists(atPath: p12Url.path),
                        FileManager.default.fileExists(atPath: provisionUrl.path),
                        FileManager.default.fileExists(atPath: passwordUrl.path)
                    else {
                        Logger.misc.warning("Skipping \(certName): missing required files")
                        continue
                    }
                    
                    let password = try String(contentsOf: passwordUrl, encoding: .utf8)
                    
                    FR.handleCertificateFiles(
                        p12URL: p12Url,
                        provisionURL: provisionUrl,
                        p12Password: password,
                        certificateName: certName,
                    ) { _ in
                        
                    }
                }
                UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
            } catch {
                Logger.misc.error("Failed to list signing-assets: \(error)")
            }
        }

#if SERVER
    private func _downloadSSLCertificates() {
        let serverURL = "https://backloop.dev/pack.json"
        
        FR.downloadSSLCertificates(from: serverURL) { success in
            if success {
                print("SSL certificates downloaded successfully")
            } else {
                print("Failed to download SSL certificates")
            }
        }
    }
#endif
}
