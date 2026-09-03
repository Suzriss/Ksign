//
//  CeresifyStoreBackground.swift
//  Ksign
//
//  The ground the shop picked, under every page rather than under the store
//  alone.
//

import SwiftUI

/// Paints a tab on the background the admin panel chose.
///
/// `FeatherApp` hands the colour to the UIKit appearance proxies, which is what
/// the store's own list — a real `UITableView` — is drawn on. Nothing in
/// SwiftUI reads those proxies, so Home, General, the Signer and Settings kept
/// the system's grouped background and the store was the only page that ever
/// changed colour. This puts the same ground under the SwiftUI pages, and
/// takes the `List` and `Form` backgrounds out of the way so it shows through.
///
/// Nothing happens at all while no colour is set, which leaves every page on
/// the system background exactly as it shipped.
struct CeresifyStoreBackgroundModifier: ViewModifier {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	func body(content: Content) -> some View {
		// Never an `if let` around the content: this wraps a whole tab, and a
		// branch swap when the colour goes from nothing to something rebuilds
		// the tab from scratch — the same tree throw-away `FeatherApp` stopped
		// doing on a repaint, and the reason a fresh install sat on the shop's
		// colour after the first config landed. Nil becomes the values that
		// leave the system background exactly as it was.
		let background = Color.ceresifyBackground
		
		content
			.scrollContentBackground(background == nil ? .automatic : .hidden)
			.background((background ?? .clear).ignoresSafeArea())
	}
}

extension View {
	/// The shop's ground, under whatever this page draws.
	func ceresifyStoreBackground() -> some View {
		modifier(CeresifyStoreBackgroundModifier())
	}
}
