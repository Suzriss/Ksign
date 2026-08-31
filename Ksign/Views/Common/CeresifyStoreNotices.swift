//
//  CeresifyStoreNotices.swift
//  Ksign
//
//  The two lines that ride above the store: the shop's moving label, and the
//  word that there is no connection.
//

import SwiftUI
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
	
	var body: some View {
		GeometryReader { proxy in
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
			.onAppear {
				_containerWidth = proxy.size.width
				_start()
			}
			.onChange(of: proxy.size.width) { newValue in
				_containerWidth = newValue
				_start()
			}
		}
		.frame(height: 34)
		.background {
			Capsule(style: .continuous)
				.fill(Color.ceresifyGold.opacity(0.12))
		}
		.padding(.horizontal, 21)
		.clipped()
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
						.onAppear { _textWidth = proxy.size.width }
						.onChange(of: proxy.size.width) { newValue in _textWidth = newValue }
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
	
	private var _isOffline: Bool {
		_config.isReachable == false
	}
	
	private var _hasMarquee: Bool {
		_config.config.marquee.enabled && !_config.config.marquee.text.isEmpty
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
