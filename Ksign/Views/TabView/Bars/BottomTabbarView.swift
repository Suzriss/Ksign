//
//  BottomTabbarView.swift
//  Ksign
//
//  A tab bar that stays at the bottom, on every idiom.
//

import SwiftUI
import UIKit

/// iPadOS 18 moved `TabView`'s bar to the top of the window and gives no
/// supported way to put it back, so the bar is drawn here instead of handed to
/// the system.
///
/// Tabs are all kept alive behind one another rather than swapped in and out,
/// which is what a real tab bar does: leaving a tab and coming back keeps its
/// scroll position and its navigation stack.
struct BottomTabbarView: View {
	@AppStorage("Feather.selectedTab") private var _selectedTabRawValue: String = TabEnum.appstore.rawValue
	@State private var _selectedTab: TabEnum = .appstore
	
	var body: some View {
		ZStack {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				TabEnum.view(for: tab)
					.opacity(tab == _selectedTab ? 1 : 0)
					.allowsHitTesting(tab == _selectedTab)
					.accessibilityHidden(tab != _selectedTab)
			}
		}
		// An inset rather than an overlay: the tab views keep a safe area that
		// accounts for the bar, so lists scroll clear of it on their own.
		.safeAreaInset(edge: .bottom, spacing: 0) {
			_bar
		}
		.onAppear {
			if let stored = TabEnum(rawValue: _selectedTabRawValue),
			   TabEnum.defaultTabs.contains(stored) {
				_selectedTab = stored
			}
		}
		.onChange(of: _selectedTab) { newValue in
			_selectedTabRawValue = newValue.rawValue
		}
	}
	
	private var _bar: some View {
		HStack(alignment: .top, spacing: 0) {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				_item(for: tab)
			}
		}
		.padding(.top, 8)
		.padding(.horizontal, 8)
		.background(.bar)
		.overlay(alignment: .top) {
			Divider()
		}
	}
	
	private func _item(for tab: TabEnum) -> some View {
		let isSelected = tab == _selectedTab
		
		return Button {
			guard !isSelected else { return }
			UISelectionFeedbackGenerator().selectionChanged()
			_selectedTab = tab
		} label: {
			VStack(spacing: 3) {
				Image(systemName: tab.icon)
					.font(.system(size: 19, weight: .regular))
					.frame(height: 22)
				
				Text(tab.title)
					.font(.system(size: 10, weight: .medium))
					.lineLimit(1)
			}
			.foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(Text(verbatim: tab.title))
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
	}
}
