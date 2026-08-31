//
//  Color+ceresify.swift
//  Ksign
//
//  The store's own palette: gold type on a dark ground, the same pairing the
//  website uses — unless the shop has picked otherwise.
//

import SwiftUI
import UIKit

public extension Color {
	/// The app's type colour — everything reads gold unless a view opts out.
	///
	/// Computed rather than stored: the shop can repaint the store from the
	/// admin panel, and `CeresifyPalette` holds whatever the last config said.
	static var ceresifyGold: Color { Color(uiColor: .ceresifyGold) }
	
	/// App names and their descriptions stay white so a list of apps reads as
	/// content rather than as more chrome.
	static var ceresifyTitle: Color { Color(uiColor: CeresifyPalette.title) }
	static var ceresifySubtitle: Color { Color(uiColor: CeresifyPalette.subtitle) }
	
	/// What the store is drawn on. Nil for as long as nobody has picked one,
	/// which leaves every list on the system's own grouped background.
	static var ceresifyBackground: Color? {
		CeresifyPalette.background.map(Color.init(uiColor:))
	}
}

public extension UIColor {
	static var ceresifyGold: UIColor { CeresifyPalette.gold }
	static var ceresifyAccent: UIColor { CeresifyPalette.accent }
}
