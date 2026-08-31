//
//  CeresifyThumbnailView.swift
//  Ksign
//
//  Drawing a small image from a source, including the ones iOS can't decode.
//

import SwiftUI
import NukeUI

/// A thumbnail that copes with the formats the shop actually uploads.
///
/// Category art comes in as whatever the admin panel was handed, and a fair
/// amount of it is SVG — which iOS decodes for nobody, so those categories
/// came through blank. Ceresify already rasterizes images for the website
/// (`/api/thumb`), and sharp reads SVG, so an SVG is fetched through that with
/// `fit=contain`: the drawing lands whole inside the box on a transparent
/// ground rather than being cropped into.
///
/// Everything else is loaded straight, which keeps the extra hop off the
/// formats that never needed it.
struct CeresifyThumbnailView: View {
	let url: URL?
	/// The side of the square the image is drawn in.
	var size: CGFloat = 22
	/// Drawn when there is no image, or none that loads.
	var placeholder: String?
	
	var body: some View {
		Group {
			if let url = Self.decodable(url, size: size) {
				LazyImage(url: url) { state in
					if let image = state.image {
						image
							.resizable()
							.scaledToFit()
					} else {
						_placeholderView
					}
				}
			} else {
				_placeholderView
			}
		}
		.frame(width: size, height: size)
	}
	
	@ViewBuilder
	private var _placeholderView: some View {
		if let placeholder, !placeholder.isEmpty {
			Text(verbatim: placeholder)
				.font(.system(size: size * 0.82))
				.minimumScaleFactor(0.5)
		} else {
			Color.clear
		}
	}
	
	/// The URL to actually fetch: the original, or the server's raster of it.
	///
	/// Sized in pixels for the densest screen the app runs on, so the same
	/// cached raster serves every device instead of one per scale.
	static func decodable(_ url: URL?, size: CGFloat) -> URL? {
		guard let url else { return nil }
		guard url.pathExtension.lowercased() == "svg" else { return url }
		
		let pixels = min(512, Int((size * 3).rounded()))
		
		var components = URLComponents(
			url: CeresifyAPI.baseURL.appendingPathComponent("api/thumb"),
			resolvingAgainstBaseURL: false
		)
		components?.queryItems = [
			URLQueryItem(name: "url", value: url.absoluteString),
			URLQueryItem(name: "w", value: String(pixels)),
			URLQueryItem(name: "fit", value: "contain")
		]
		
		return components?.url ?? url
	}
}
