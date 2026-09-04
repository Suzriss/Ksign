//
//  Server+Compute.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import UIKit.UIGraphicsImageRenderer

extension ServerInstaller {
	var plistEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).plist"
		comps.port = port
		return comps.url!
	}

	var payloadEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).ipa"
		comps.port = port
		return comps.url!
	}
	
	var pageEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/install"
		comps.port = port
		return comps.url!
	}
	
	/// The manifest, written somewhere iOS will actually fetch it from.
	///
	/// iOS fetches the manifest itself and only over https it trusts, and the
	/// certificate this device serves cannot be that: backloop.dev publishes
	/// its private key on purpose, so every certificate it issues gets revoked
	/// within days of being issued. The manifest is therefore the one piece
	/// held elsewhere — on Ceresify's own certificate, which is an ordinary
	/// trusted one. The build never leaves the device; what goes up is a
	/// sentence naming where it already is, and the server only writes that
	/// sentence for an address on the device itself.
	///
	/// This used to be `api.palera.in`, which meant the name and identifier of
	/// every app anyone installed went to a service that had no reason to see
	/// them.
	var externalServerLink: String {
		var comps = URLComponents(
			url: CeresifyAPI.baseURL.appendingPathComponent("api/genplist"),
			resolvingAgainstBaseURL: false
		)!
		
		comps.queryItems = [
			URLQueryItem(name: "bundleid", value: app.identifier ?? ""),
			URLQueryItem(name: "name", value: app.name ?? app.identifier ?? ""),
			URLQueryItem(name: "version", value: app.version ?? "1.0"),
			URLQueryItem(name: "fetchurl", value: payloadEndpoint.absoluteString),
		]
		
		// Encoded whole: it goes in as the value of another URL's `url=`, and
		// its own separators would cut that query short.
		return comps.url?.absoluteString
			.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
	}

	var iTunesLink: String {
		_iTunesLink(with: plistEndpoint.absoluteString)
	}
	
	var iTunesLinkExternal: String {
		_iTunesLink(with: externalServerLink)
	}
	
	private func _iTunesLink(with url: String) -> String {
		return "itms-services://?action=download-manifest&url=\(url)"
	}

	var displayImageSmallEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app57x57.png"
		comps.port = port
		return comps.url!
	}

	var displayImageLargeEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app512x512.png"
		comps.port = port
		return comps.url!
	}
	
	var displayImageSmallData: Data {
		_createIcon(57)
	}
	
	var displayImageLargeData: Data {
		_createIcon(512)
	}
	
	private func _createIcon(_ r: CGFloat) -> Data {
		let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
		let image = renderer.image { ctx in
			UIColor.accent.setFill()
			ctx.fill(.init(x: 0, y: 0, width: r, height: r))
		}
		return image.pngData()!
	}

	/// The page Safari is sent to, whose only job is to follow the install
	/// link itself.
	///
	/// Since iOS 18 a sideloaded app has no entitlement for
	/// `itms-services://`: `UIApplication.open` returns having done nothing
	/// whatsoever, which is why the installer used to sit on `Ready` for
	/// good. Safari is still allowed to open it, so the link is handed to a
	/// page this device serves and Safari follows it from there.
	///
	/// The manifest that page points at is this device's own whenever the
	/// server is https and the certificate is one iOS accepts; the plain-http
	/// mode has the manifest held on Ceresify instead, which needs no
	/// certificate from this device at all.
	var html: String {
		let link = ServerInstaller.getServerMethod() == 1
		? iTunesLinkExternal
		: iTunesLink
		
		return """
		<html style="background-color: black;">
		<script type="text/javascript">window.location="\(link)"</script>
		</html>
		"""
	}

	/// The manifest `itms-services://` asks for.
	///
	/// Every value here is a plain `String`: a `nil` anywhere in this
	/// dictionary is not a property-list type, so serialising it fails, the
	/// device is handed an empty file, and nothing at all comes up.
	var installManifest: [String: Any] {[
		"items": [[
			"assets": [
				[
					"kind": "software-package",
					"url": payloadEndpoint.absoluteString,
				],
				// Served from this device, by the two routes that were already
				// there for it. The icon used to be fetched from a GitHub path
				// that has since gone — a 404 in the middle of an install that
				// has no business reaching the network at all.
				[
					"kind": "display-image",
					"url": displayImageSmallEndpoint.absoluteString,
				],
				[
					"kind": "full-size-image",
					"url": displayImageLargeEndpoint.absoluteString,
				],
			],
			"metadata": [
				"bundle-identifier": app.identifier ?? Bundle.main.bundleIdentifier ?? "",
				"bundle-version": app.version ?? "1.0",
				"kind": "software",
				"title": app.name ?? app.identifier ?? "",
			],
		],],
	]}

	var installManifestData: Data {
		(try? PropertyListSerialization.data(
			fromPropertyList: installManifest,
			format: .xml,
			options: .zero
		)) ?? .init()
	}
}
