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
		if let background = Color.ceresifyBackground {
			content
				.scrollContentBackground(.hidden)
				.background(background.ignoresSafeArea())
		} else {
			content
		}
	}
}

extension View {
	/// The shop's ground, under whatever this page draws.
	func ceresifyStoreBackground() -> some View {
		modifier(CeresifyStoreBackgroundModifier())
	}
}
