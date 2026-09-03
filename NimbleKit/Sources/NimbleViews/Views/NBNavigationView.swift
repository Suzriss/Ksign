//
//  NavigationViewWrapper.swift
//  Stars
//
//  Created by samara on 7.04.2025.
//

import SwiftUI

public struct NBNavigationView<Content>: View where Content: View {
	private var _title: String
	private var _mode: NavigationBarItem.TitleDisplayMode
	private var _content: Content
	
	public init(
		_ title: String,
		displayMode: NavigationBarItem.TitleDisplayMode = .automatic,
		@ViewBuilder content: () -> Content
	) {
		self._title = title
		self._mode = displayMode
		self._content = content()
	}
	
	public var body: some View {
		NavigationStack {
			_content
				.navigationTitle(_title)
				.navigationBarTitleDisplayMode(_mode)
				// Inside the stack rather than around it: a `NavigationStack`
				// draws its own opaque ground, so a background applied from
				// the outside never reaches the page.
				.nbAppearanceBackground()
		}
	}
}
