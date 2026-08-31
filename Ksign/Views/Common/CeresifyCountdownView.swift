//
//  CeresifyCountdownView.swift
//  Ksign
//
//  A countdown the shop puts on an app's page from the admin panel.
//

import SwiftUI
import Combine
import NimbleExtensions

/// Counts down to the moment the shop set, on every app's page or on one
/// app's alone.
///
/// It ticks off a timer rather than a `Text(timerInterval:)` so the four units
/// stay laid out as boxes — the same reading as the countdowns on the website —
/// and it takes itself off the page the second it reaches zero.
struct CeresifyCountdownView: View {
	let countdown: CeresifyConfig.Countdown
	
	@State private var _remaining: TimeInterval = 0
	
	private let _tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
	
	var body: some View {
		if _remaining > 0 {
			VStack(alignment: .leading, spacing: 10) {
				if !countdown.title.isEmpty {
					Text(verbatim: countdown.title)
						.font(.headline)
						.foregroundStyle(Color.ceresifyGold)
				}
				
				HStack(spacing: 8) {
					_box(_days, .localized("Days"))
					_box(_hours, .localized("Hours"))
					_box(_minutes, .localized("Minutes"))
					_box(_seconds, .localized("Seconds"))
				}
				
				if !countdown.message.isEmpty {
					Text(verbatim: countdown.message)
						.font(.footnote)
						.foregroundStyle(Color.ceresifySubtitle)
				}
			}
			.padding(14)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(Color(uiColor: .secondarySystemBackground))
			}
			.overlay {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.strokeBorder(Color.ceresifyGold.opacity(0.28), lineWidth: 1)
			}
			.onAppear(perform: _update)
			.onReceive(_tick) { _ in _update() }
			.transition(.opacity)
		} else {
			// Nothing at all once it runs out, and nothing while the first
			// tick is still pending.
			Color.clear
				.frame(height: 0)
				.onAppear(perform: _update)
				.onReceive(_tick) { _ in _update() }
		}
	}
	
	private var _days: Int { Int(_remaining) / 86_400 }
	private var _hours: Int { (Int(_remaining) % 86_400) / 3_600 }
	private var _minutes: Int { (Int(_remaining) % 3_600) / 60 }
	private var _seconds: Int { Int(_remaining) % 60 }
	
	private func _update() {
		guard let endsAt = countdown.endsAt else {
			_remaining = 0
			return
		}
		
		_remaining = max(0, endsAt.timeIntervalSinceNow)
	}
	
	@ViewBuilder
	private func _box(_ value: Int, _ caption: String) -> some View {
		VStack(spacing: 2) {
			Text(verbatim: String(format: "%02d", value))
				.font(.title3.bold())
				.monospacedDigit()
				.contentTransition(.numericText())
				.foregroundStyle(Color.ceresifyTitle)
			
			Text(verbatim: caption)
				.font(.caption2)
				.foregroundStyle(Color.ceresifySubtitle)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 8)
		.background {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Color(uiColor: .tertiarySystemBackground))
		}
	}
}

/// Every countdown the shop put on this page, stacked.
///
/// The page says where it is and, on an app's own page, which app — and the
/// config decides from there, so a page carries a countdown without knowing
/// anything about the ones it isn't showing.
struct CeresifyCountdownStack: View {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	let placement: CeresifyConfig.Placement
	/// Nil anywhere that isn't one app's own page.
	var bundleIdentifier: String?
	
	var body: some View {
		let countdowns = _config.countdowns(on: placement, bundleIdentifier: bundleIdentifier)
		
		if !countdowns.isEmpty {
			VStack(spacing: 10) {
				ForEach(countdowns) { countdown in
					CeresifyCountdownView(countdown: countdown)
				}
			}
		}
	}
}
