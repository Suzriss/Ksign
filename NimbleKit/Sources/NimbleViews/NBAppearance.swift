//
//  NBAppearance.swift
//  NimbleViews
//
//  The ground every navigation page is drawn on.
//

import SwiftUI

/// The colour pages are drawn on, carried down the view tree.
///
/// A background handed to a `NavigationStack` from the outside is painted over
/// by the stack's own opaque ground, so it never reaches the page — which is
/// why setting a colour repainted a UIKit table and left every SwiftUI page on
/// the system background. It has to be applied to the content *inside* the
/// stack, and an environment value is what lets an app say it once at the root
/// and have `NBNavigationView` and `NBList` pick it up wherever they are —
/// including inside a sheet or a pushed page, which are hosted on their own and
/// inherit nothing else.
///
/// Nil is the default and means "leave the system's own background alone", so
/// an app that never sets it is exactly as it was.
private struct NBBackgroundKey: EnvironmentKey {
	static let defaultValue: Color? = nil
}

public extension EnvironmentValues {
	var nbBackground: Color? {
		get { self[NBBackgroundKey.self] }
		set { self[NBBackgroundKey.self] = newValue }
	}
}

// MARK: - Modifier
/// Paints that ground under a page and takes the list's own background out of
/// the way so it shows through.
public struct NBAppearanceBackground: ViewModifier {
	@Environment(\.nbBackground) private var _background

	public init() {}

	public func body(content: Content) -> some View {
		// One shape whether or not a colour is set, on purpose. An `if let`
		// around the content puts it on a different branch the moment a colour
		// arrives, and to SwiftUI a different branch is a different view: the
		// whole page is thrown away and built again — its state, its tasks,
		// the store's table. On a fresh install the first colour lands a
		// moment after launch, so that rebuild happened in the middle of the
		// opening screen and read as an app stuck on the new colour. Nil is
		// handed down as the values that leave the system's own ground alone.
		content
			.scrollContentBackground(_background == nil ? .automatic : .hidden)
			.background((_background ?? .clear).ignoresSafeArea())
	}
}

public extension View {
	/// The app's own ground, under this page.
	func nbAppearanceBackground() -> some View {
		modifier(NBAppearanceBackground())
	}

	/// Sets the ground every page below this one is drawn on. Nil keeps the
	/// system's.
	func nbBackground(_ color: Color?) -> some View {
		environment(\.nbBackground, color)
	}
}
