//
//  FR.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation.NSURL
import UIKit.UIImage
import Zsign
import NimbleJSON
import AltSourceKit
import IDeviceSwift
import OSLog

enum FR {
	/// What to put in front of someone whose import just failed.
	///
	/// The old line told them to go and switch the extraction library in
	/// Settings; the app tries both by itself now, so the only thing left
	/// worth saying is what actually stopped it — a corrupt archive, a full
	/// disk and an IPA with nothing in it are three different problems and
	/// used to read as one.
	static func importFailureMessage(_ error: Error?) -> String {
		let lead = String.localized("Couldn't open this file. Both extraction libraries were tried.")
		
		guard let error else { return lead }
		
		let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		return detail.isEmpty ? lead : lead + "\n\n" + detail
	}
	
	static func handlePackageFile(
		_ ipa: URL,
		download: Download? = nil,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = AppFileHandler(file: ipa, download: download)
			
			do {
				try await handler.copy()
				try await handler.extract()
				try await handler.move()
				try await handler.addToDatabase()
                
                                try? await handler.clean()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func signPackageFile(
		_ app: AppInfoPresentable,
		using options: Options,
		icon: UIImage?,
		certificate: CertificatePair?,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = SigningHandler(app: app, options: options)
			if !options.onlyModify {
				handler.appCertificate = certificate
			}
			handler.appIcon = icon
			
			do {
				try await handler.copy()
				try await handler.modify()
                try? await handler.clean()
				
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func handleCertificateFiles(
		p12URL: URL,
		provisionURL: URL,
		p12Password: String,
		certificateName: String,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = CertificateFileHandler(
				key: p12URL,
				provision: provisionURL,
				password: p12Password,
				nickname: certificateName.isEmpty ? nil : certificateName
			)
			
			do {
				try await handler.copy()
				try await handler.addToDatabase()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	
	static func checkPasswordForCertificate(
		for key: URL,
		with password: String,
		using provision: URL
	) -> Bool {
		defer {
			password_check_fix_WHAT_THE_FUCK_free(provision.path)
		}
		
		password_check_fix_WHAT_THE_FUCK(provision.path)
		
		if (!p12_password_check(key.path, password)) {
			return false
		}
		
		return true
	}
	
	static func checkPasswordForCertificateData(
		p12Data: Data,
		provisionData: Data,
		password: String
	) -> Bool {
		let tempDir = FileManager.default.temporaryDirectory
		let tempP12 = tempDir.appendingPathComponent("temp_cert.p12")
		let tempProvision = tempDir.appendingPathComponent("temp_provision.mobileprovision")
		
		defer {
			try? FileManager.default.removeItem(at: tempP12)
			try? FileManager.default.removeItem(at: tempProvision)
		}
		
		do {
			try p12Data.write(to: tempP12)
			try provisionData.write(to: tempProvision)
			
			return checkPasswordForCertificate(for: tempP12, with: password, using: tempProvision)
		} catch {
			print("Error creating temporary files for password check: \(error)")
			return false
		}
	}
	
	static func movePairing(_ url: URL) {
		let fileManager = FileManager.default
		let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")

		try? fileManager.removeFileIfNeeded(at: dest)
		
		try? fileManager.copyItem(at: url, to: dest)
		
		HeartbeatManager.shared.start(true)
	}
	
	#if SERVER
	static func downloadSSLCertificates(
		from urlString: String,
		completion: @escaping (Bool) -> Void
	) {
		let generator = UINotificationFeedbackGenerator()
		generator.prepare()
		
		NBFetchService().fetch(from: urlString) { (result: Result<ServerPackModel, Error>) in
			switch result {
			case .success(let pack):
				do {
					let serverDir = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server")
					let pemURL = serverDir.appendingPathComponent("server.pem")
					let crtURL = serverDir.appendingPathComponent("server.crt")
					let commonNameURL = serverDir.appendingPathComponent("commonName.txt")
					
					try FileManager.default.createDirectoryIfNeeded(at: serverDir)
					try pack.key.write(to: pemURL, atomically: true, encoding: .utf8)
					// Leaf *and* the CA above it. The pack hands them over
					// separately, and writing only the leaf leaves the server
					// presenting a certificate whose issuer the device has
					// never heard of: the handshake fails, `itms-services://`
					// gives up without a word, and the installer sits on
					// `Ready` forever.
					try ServerInstaller.certificateChain(leaf: pack.cert, ca: pack.ca)
						.write(to: crtURL, atomically: true, encoding: .utf8)
					// The pack names the wildcard the certificate is issued to;
					// what gets written down has to be a host that resolves.
					let host = ServerInstaller.commonNameHost(pack.info.domains.commonName)
						?? pack.info.domains.commonName
					try host.write(to: commonNameURL, atomically: true, encoding: .utf8)
					
					generator.notificationOccurred(.success)
					completion(true)
				} catch {
					completion(false)
				}
			case .failure(_):
				completion(false)
			}
		}
	}
	#endif
	
	/// - Parameter silent: suppresses the alerts, for the built-in sources seeded
	///   at launch where there is no user action to report back to.
	/// - Parameter storeAs: the URL to write down, when what is fetched is not
	///   what should be stored. The shop's catalog is asked for one app rather
	///   than for all ten thousand of them — everything a source row needs (its
	///   name, its identifier, its icon) rides on any page — but the row has to
	///   hold the plain URL, since that is what the store reads from.
	static func handleSource(
		_ urlString: String,
		storeAs: String? = nil,
		silent: Bool = false,
		competion: @escaping () -> Void
	) {
		guard
			let url = URL(string: urlString),
			let stored = URL(string: storeAs ?? urlString)
		else {
			return
		}
		
		NBFetchService().fetch<ASRepository>(from: url) { (result: Result<ASRepository, Error>) in
			switch result {
			case .success(let data):
				let id = data.id ?? stored.absoluteString
				
				if !Storage.shared.sourceExists(id) {
					Storage.shared.addSource(stored, repository: data, id: id) { _ in
						competion()
					}
				} else if !silent {
					DispatchQueue.main.async {
						UIAlertController.showAlertWithOk(title: "Error", message: "Repository already added.")
					}
				}
			case .failure(let error):
				guard !silent else {
					Logger.misc.error("Failed to fetch source \(urlString): \(error)")
					return
				}
				DispatchQueue.main.async {
					UIAlertController.showAlertWithOk(title: "Error", message: error.localizedDescription)
				}
			}
		}
	}
}

private enum CertificateHandlerError: Error {
	case invalidCertificate
}
