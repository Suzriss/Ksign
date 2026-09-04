//
//  Server+TLS.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork

// MARK: - Class extension: TLS/Setup
extension ServerInstaller {
	// MARK: Setup
	private static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()
	
	static func setupApp(port: Int) throws -> Application {
		let app = Application(env)
		app.threadPool = .init(numberOfThreads: 1)
		
		if ServerInstaller.getServerMethod() != 1 {
			if let tls = try Self.tls() {
				app.http.server.configuration.tlsConfiguration = tls
			}
		}
		
		app.http.server.configuration.hostname = Self.sni
		app.http.server.configuration.tcpNoDelay = true
		app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false
		
		return app
	}
	
	// MARK: Files/IP
	/// The name the install manifest is served under.
	///
	/// Worked out on every read rather than held for the life of the process:
	/// the certificates are fetched at launch and can land after the first
	/// screen is up, and a name settled before them would stay wrong until the
	/// app was relaunched.
	static var sni: String {
		let localhost = "127.0.0.1"
		
		if getServerMethod() == 1 {
			return !ServerInstaller.getIPFix()
			? (getLocalAddress() ?? localhost)
			: localhost
		} else {
			return readCommonName() ?? localhost
		}
	}
	
	/// Whether there is anything to serve the manifest over https with.
	///
	/// `itms-services://` will only fetch a manifest over https, so without
	/// these the link opens nothing whatsoever — no error, no prompt, nothing —
	/// and the installer sits on `Ready` until it is dismissed.
	static var hasTLSMaterial: Bool {
		getUrl("server", ext: "crt") != nil
		&& getUrl("server", ext: "pem") != nil
		&& readCommonName() != nil
	}
	
	/// The leaf followed by every certificate above it, as one PEM file.
	///
	/// A TLS server has to hand over the chain, not just its own certificate:
	/// `*.backloop.dev` is issued by an intermediate no device carries, so a
	/// leaf on its own cannot be verified. iOS says nothing about it — the
	/// manifest fetch behind `itms-services://` just never happens, and the
	/// installer waits on `Ready` until it is dismissed.
	static func certificateChain(leaf: String, ca: String) -> String {
		[leaf, ca]
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")
			+ "\n"
	}
	
	static func tls() throws -> TLSConfiguration? {
		guard
			let crt = getUrl("server", ext: "crt"),
			let pem = getUrl("server", ext: "pem")
		else {
			return nil
		}
		
		return try TLSConfiguration.makeServerConfiguration(
			certificateChain: NIOSSLCertificate.fromPEMFile(crt.path).map {
				NIOSSLCertificateSource.certificate($0)
			},
			privateKey: .privateKey(
				try NIOSSLPrivateKey(file: pem.path, format: .pem)
			)
		)
	}
	
	static func readCommonName() -> String? {
		guard
			let url = getUrl("commonName", ext: "txt"),
			let name = try? String(contentsOf: url, encoding: .utf8)
		else {
			return nil
		}
		
		return commonNameHost(name)
	}
	
	/// Turns the name a certificate is issued to into a name that can actually
	/// be reached.
	///
	/// The pack is issued to `*.backloop.dev`, and that wildcard is what both
	/// the build and `pack.json` wrote down — but a wildcard is not a host.
	/// Nothing resolves it, so the manifest URL named a machine the device
	/// could never reach, `itms-services://` quietly opened nothing at all, and
	/// every install ended staring at `Ready`. Every label under the wildcard
	/// points back at this device and is covered by the same certificate, so
	/// the star is given one.
	static func commonNameHost(_ commonName: String) -> String? {
		let trimmed = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
		
		guard !trimmed.isEmpty else { return nil }
		guard trimmed.hasPrefix("*.") else { return trimmed }
		
		return "ksign" + trimmed.dropFirst()
	}
}

extension ServerInstaller {
	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default
		
		let serverURL = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server").appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: serverURL.path) {
			return serverURL
		}
		
		let documentsURL = URL.documentsDirectory.appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: documentsURL.path) {
			return documentsURL
		}
		
		let oldServerURL = URL.documentsDirectory.appendingPathComponent("Server").appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: oldServerURL.path) {
			return oldServerURL
		}
		
		return Bundle.main.url(forResource: name, withExtension: ext)
	}
	
	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				
				if addrFamily == UInt8(AF_INET) {
					
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
									   &hostname, socklen_t(hostname.count),
									   nil, socklen_t(0), NI_NUMERICHOST) == 0 {
							address = String(cString: hostname)
						}
						
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}
		
		return address
	}
}
