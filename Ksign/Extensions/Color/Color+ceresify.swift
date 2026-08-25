//
//  Color+ceresify.swift
//  Ksign
//
//  The store's own palette: gold type on a dark ground, the same pairing the
//  website uses.
//

import SwiftUI
import UIKit

public extension Color {
	/// The app's type colour — everything reads gold unless a view opts out.
	static let ceresifyGold = Color(uiColor: .ceresifyGold)
	
	/// App names and their descriptions stay white so a list of apps reads as
	/// content rather than as more chrome.
	static let ceresifyTitle = Color.white
	static let ceresifySubtitle = Color.white.opacity(0.72)
}

public extension UIColor {
	static let ceresifyGold = UIColor(
		red: 0xF4 / 255,
		green: 0xC7 / 255,
		blue: 0x73 / 255,
		alpha: 1.0
	)
}
