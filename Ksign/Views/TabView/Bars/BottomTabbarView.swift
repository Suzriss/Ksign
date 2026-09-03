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
/// Drawn to UIKit's own measurements — a 49pt row over the home indicator, a
/// hairline separator, `.bar` material behind it, 25pt symbols above 10pt
/// labels — so it reads as the system bar rather than a lookalike, down to the
/// symbol bouncing as a tab is picked.
///
/// Tabs are kept alive behind one another rather than swapped in and out,
/// which is what a real tab bar does: leaving a tab and coming back keeps its
/// scroll position and its navigation stack.
///
/// Kept alive, but only once they have been opened. Building all five up front
/// meant every launch paid for the store's ten-thousand-row table, the featured
/// list and the products list before the first tab could be drawn, which is
/// what left the app sitting on `Fetching…` for the best part of a minute on an
/// iPad. A tab is built the first time it is picked and stays built after that.
struct BottomTabbarView: View {
	@AppStorage("Feather.selectedTab") private var _selectedTabRawValue: String = TabEnum.home.rawValue
	@State private var _selectedTab: TabEnum = .home
	/// The tabs that have been opened at least once this launch.
	@State private var _built: Set<TabEnum> = [.home]
	
	/// Watched so a repaint from the panel reaches this bar. Nothing else here
	/// reads it — the colours below come off `CeresifyPalette`, which SwiftUI
	/// has no way of noticing on its own.
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	/// UIKit's compact tab bar height, which is what everything else on screen
	/// is spaced against.
	private let _barHeight: CGFloat = 49
	
	var body: some View {
		ZStack {
			ForEach(TabEnum.defaultTabs.filter(_built.contains), id: \.hashValue) { tab in
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
			
			_built.insert(_selectedTab)
		}
		.onChange(of: _selectedTab) { newValue in
			_selectedTabRawValue = newValue.rawValue
			_built.insert(newValue)
		}
	}
	
	private var _bar: some View {
		HStack(spacing: 0) {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				_item(for: tab)
			}
		}
		.frame(height: _barHeight)
		.frame(maxWidth: .infinity)
		// The material has to reach past the inset and under the home
		// indicator, or content scrolls through a clear strip below the bar.
		//
		// The shop's ground when it has picked one, and the system material
		// otherwise — this bar is drawn by hand, so unlike `UITabBar` it gets
		// nothing from the appearance proxy `FeatherApp` sets.
		.background {
			Group {
				if let background = Color.ceresifyBackground {
					background
				} else {
					Rectangle().fill(.bar)
				}
			}
			.ignoresSafeArea(edges: .bottom)
		}
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
			VStack(spacing: 2) {
				_icon(for: tab, isSelected: isSelected)
				
				Text(verbatim: tab.title)
					.font(.system(size: 10, weight: .medium))
					.lineLimit(1)
					.minimumScaleFactor(0.85)
			}
			// The picked tab in the store's accent and the rest in its type
			// colour dimmed — the same pairing `UITabBar` is given, so the two
			// bars can't drift apart.
			.foregroundStyle(
				isSelected
				? AnyShapeStyle(Color.ceresifyAccent)
				: AnyShapeStyle(Color.ceresifyGold.opacity(0.55))
			)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(TabbarItemButtonStyle())
		.accessibilityLabel(Text(verbatim: tab.title))
		.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
	}
	
	@ViewBuilder
	private func _icon(for tab: TabEnum, isSelected: Bool) -> some View {
		let image = Image(systemName: tab.icon)
			.font(.system(size: 22, weight: .regular))
			.frame(height: 25)
		
		if #available(iOS 17, *) {
			image.symbolEffect(.bounce, value: isSelected)
		} else {
			image
		}
	}
}

/// The system bar dims a tab on touch-down rather than tinting it, so the
/// press reads the same way here.
private struct TabbarItemButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.opacity(configuration.isPressed ? 0.45 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
	}
}
