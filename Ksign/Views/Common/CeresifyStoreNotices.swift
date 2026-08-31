//
//  CeresifyStoreNotices.swift
//  Ksign
//
//  The two lines that ride above the store: the shop's moving label, and the
//  word that there is no connection.
//

import SwiftUI
import NukeUI
import NimbleExtensions

/// The label the shop can run across the top of the store.
///
/// It scrolls by moving two copies of the same text past each other, so the
/// message reads continuously instead of snapping back at the end of a pass.
/// A message short enough to fit stands still — sliding it would be motion for
/// nothing.
struct CeresifyMarqueeView: View {
	let text: String
	/// Seconds for one full pass; larger is slower.
	let speed: Double
	
	@State private var _offset: CGFloat = 0
	@State private var _textWidth: CGFloat = 0
	@State private var _containerWidth: CGFloat = 0
	
	@Environment(\.layoutDirection) private var _layoutDirection
	
	private var _shouldScroll: Bool {
		_textWidth > _containerWidth && _containerWidth > 0
	}
	
	/// The gap between the two copies, so the message doesn't run into itself.
	private let _spacing: CGFloat = 44
	private let _height: CGFloat = 34
	
	var body: some View {
		// A ZStack rather than a GeometryReader around the content: the reader
		// pins whatever it holds to the top of its box, which left the text
		// riding above the middle of the pill instead of sitting in it.
		ZStack {
			HStack(spacing: _spacing) {
				_label
				
				if _shouldScroll {
					_label
				}
			}
			.offset(x: _shouldScroll ? _offset : 0)
			.frame(
				maxWidth: .infinity,
				alignment: _shouldScroll ? .leading : .center
			)
		}
		.frame(maxWidth: .infinity)
		.frame(height: _height)
		.background {
			Capsule(style: .continuous)
				.fill(Color.ceresifyGold.opacity(0.12))
		}
		.clipShape(Capsule(style: .continuous))
		.background {
			// Measured off a shape behind the pill rather than around it, so
			// the reader never gets a say in how the content is laid out.
			GeometryReader { proxy in
				Color.clear
					.onAppear {
						_containerWidth = proxy.size.width
						_start()
					}
					.onChange(of: proxy.size.width) { newValue in
						_containerWidth = newValue
						_start()
					}
			}
		}
		.padding(.horizontal, 21)
	}
	
	private var _label: some View {
		Text(verbatim: text)
			.font(.footnote.weight(.semibold))
			.lineLimit(1)
			.fixedSize()
			.foregroundStyle(Color.ceresifyGold)
			.background {
				GeometryReader { proxy in
					Color.clear
						.onAppear {
							_textWidth = proxy.size.width
							_start()
						}
						.onChange(of: proxy.size.width) { newValue in
							_textWidth = newValue
							_start()
						}
				}
			}
	}
	
	private func _start() {
		guard _shouldScroll else {
			_offset = 0
			return
		}
		
		let distance = _textWidth + _spacing
		// In Arabic the page reads right to left, so the label has to travel
		// the other way or it would run backwards against the text.
		let target = _layoutDirection == .rightToLeft ? distance : -distance
		
		_offset = 0
		
		withAnimation(.linear(duration: max(4, speed)).repeatForever(autoreverses: false)) {
			_offset = target
		}
	}
}

/// Says the store is working from what it already had, and what the shop wants
/// said about it.
struct CeresifyOfflineBar: View {
	let message: String
	
	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "wifi.slash")
				.font(.footnote.weight(.semibold))
			
			Text(verbatim: message)
				.font(.footnote)
				.lineLimit(2)
			
			Spacer(minLength: 0)
		}
		.foregroundStyle(Color.ceresifySubtitle)
		.padding(.horizontal, 14)
		.padding(.vertical, 9)
		.background {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.fill(Color(uiColor: .secondarySystemBackground))
		}
		.padding(.horizontal, 21)
	}
}

/// Both notices in the order the store shows them, for the pages that want the
/// pair without repeating the conditions.
struct CeresifyStoreNoticesView: View {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	/// The category chip the list is filtered to, so a label the shop pinned
	/// to certain categories only turns up in those.
	var selectedCategory: String?
	
	private var _isOffline: Bool {
		_config.isReachable == false
	}
	
	private var _hasMarquee: Bool {
		_config.config.marquee.runs(in: selectedCategory)
	}
	
	var body: some View {
		VStack(spacing: 8) {
			if _isOffline {
				CeresifyOfflineBar(
					message: _config.text(
						_config.config.strings.offline,
						fallback: .localized("No connection — showing what was loaded last.")
					)
				)
			}
			
			if _hasMarquee {
				CeresifyMarqueeView(
					text: _config.config.marquee.text,
					speed: _config.config.marquee.speed
				)
				.id(_config.config.marquee.text)
			}
		}
		// Nothing to say means nothing on screen, not a gap above the list.
		.padding(.vertical, _isOffline || _hasMarquee ? 8 : 0)
	}
}

// MARK: - Store logo
/// The shop's own mark, at the top of the Home tab.
///
/// Nothing at all until a logo is set, so a shop that never uploads one keeps
/// the page it already had. The URL carries the moment it was last changed, so
/// replacing the image replaces what is on screen instead of the cached copy
/// of the old one.
struct CeresifyStoreLogoView: View {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	var height: CGFloat = 96
	
	private var _url: URL? {
		let value = _config.config.theme.logoURL
		return value.isEmpty ? nil : URL(string: value)
	}
	
	var body: some View {
		if let url = _url {
			LazyImage(url: url) { state in
				if let image = state.image {
					image
						.resizable()
						.scaledToFit()
				}
			}
			.frame(maxWidth: .infinity)
			.frame(height: height)
			.padding(.bottom, 2)
		}
	}
}
