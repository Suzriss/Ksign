//
//  CeresifyGateView.swift
//  Ksign
//
//  What the app shows before the store: the opening screen, and the three
//  reasons it may not open at all.
//

import SwiftUI
import NukeUI
import NimbleExtensions

/// Wraps the whole app.
///
/// A launch goes: the opening screen (if the shop set one) → whatever the
/// server says about this device → the store. Maintenance, a ban and the
/// certificate requirement are all answered by the same call, so any of them
/// takes hold on the next launch without a new build.
///
/// The config is read from its stored copy before the first frame, so nothing
/// here waits on the network to decide what to draw — an unreachable server
/// leaves the store open on the last answer it gave.
struct CeresifyGateView<Content: View>: View {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	@Environment(\.scenePhase) private var _scenePhase
	
	@State private var _isOpening: Bool
	/// So the opening screen is a launch's worth of screen, not something that
	/// comes back every time the config is fetched again.
	@State private var _hasShownOpening = false
	@State private var _isEnrollmentPresenting = false

	/// A launch that opened on nothing and is waiting to be told what the
	/// store looks like, as opposed to one showing the shop's own screen.
	private let _isWaitingOnFirstAnswer: Bool

	private let _content: Content

	init(@ViewBuilder content: () -> Content) {
		self._content = content()

		// A fresh install has no stored answer, so it opens on an empty store
		// in colours it hasn't been given yet and waits — up to the request's
		// own twelve seconds — for the server to say what any of it should
		// look like. Nothing moved on screen for that whole stretch, which is
		// why it read as a hang and why closing and reopening "fixed" it: the
		// second launch had the answer on disk. That wait is the one that gets
		// a screen, whether or not the shop asked for a splash.
		let waiting = !CeresifyConfigManager.shared.hasStoredConfig
		self._isWaitingOnFirstAnswer = waiting

		// Decided from the stored config so the screen is either there from
		// the first frame or never appears at all — no flash either way.
		__isOpening = State(
			initialValue: waiting || CeresifyConfigManager.shared.config.splash.enabled
		)
	}
	
	var body: some View {
		ZStack {
			switch _config.gate {
			case .open:
				_content
			case .maintenance(let title, let message):
				_stop(icon: "wrench.and.screwdriver.fill", title: title, message: message)
			case .banned(let reason):
				_stop(
					icon: "hand.raised.fill",
					title: .localized("Your device is blocked"),
					message: reason.isEmpty
					? .localized("Get in touch if you think this is a mistake.")
					: reason
				)
			case .notOurs(let title, let message):
				_stop(
					icon: "person.badge.key.fill",
					title: title,
					message: message,
					// Nothing to offer a device the server has never heard of —
					// only one that could still go and register itself.
					actionTitle: _config.device.known
					? nil
					: .localized("Register this device")
				) {
					_isEnrollmentPresenting = true
				}
			}
			
			if _isOpening {
				CeresifyOpeningView(
					splash: _config.config.splash,
					// Only a launch that is actually waiting says so. The
					// shop's own screen is branding, and captioning it with
					// the app's errand would be the app talking over it.
					status: _isWaitingOnFirstAnswer && !_config.config.splash.enabled
					? String.localized("Checking your device…")
					: nil
				)
				.transition(.opacity)
				.zIndex(1)
			}
		}
		.animation(.smooth(duration: 0.35), value: _isOpening)
		.animation(.smooth, value: _config.gate)
		.sheet(isPresented: $_isEnrollmentPresenting) {
			CeresifyEnrollmentView()
		}
		.task {
			// A copy signed for one subscriber names that device in its own
			// profile, so there is nothing to install and nothing to ask:
			// take the UDID and carry on.
			CeresifyDeviceIdentity.adoptProvisionedUdidIfNeeded()
			
			// The device's certificate, brought up to date without a screen —
			// the profile was installed once, and nothing since then needs the
			// user's hands. Off on its own: the opening screen waits for the
			// config, not for a certificate nobody is looking at.
			Task { await CeresifyQuickEntry.refresh() }
			
			let openedAt = Date()

			await _config.load()

			// `load()` returns straight away when another one is already in
			// flight, so the screen waits on the answer itself rather than on
			// the call — and gives up after the request's own timeout, since
			// an unreachable server must not hold the door shut.
			let ceiling = openedAt.addingTimeInterval(12)

			while _config.isReachable == nil, Date() < ceiling {
				try? await Task.sleep(for: .milliseconds(80))
			}

			// The stored config decided whether to open on this screen, so a
			// screen the shop has only just switched on wasn't known about a
			// moment ago. Showing it now means it appears on the launch it was
			// enabled rather than the one after.
			if !_isOpening, _config.config.splash.enabled, !_hasShownOpening {
				_isOpening = true
			}

			guard _isOpening else { return }

			_hasShownOpening = true

			if _config.config.splash.enabled {
				// The shop's screen is shown for as long as the shop asked
				// for, on top of whatever the answer took.
				let seconds = max(0.6, min(_config.config.splash.seconds, 10))
				try? await Task.sleep(for: .seconds(seconds))
			} else {
				// A waiting screen with nothing behind it comes down the
				// moment the wait is over — held only long enough that an
				// answer arriving instantly doesn't read as a blink.
				let shown = Date().timeIntervalSince(openedAt)
				if shown < 0.9 { try? await Task.sleep(for: .seconds(0.9 - shown)) }
			}

			_isOpening = false
		}
		.onChange(of: _scenePhase) { phase in
			// Coming back to the front is the moment a ban or a maintenance
			// lock should be noticed — the app may have sat in the background
			// for days.
			guard phase == .active else { return }
			
			Task {
				await _config.load()
				// A notice sent while the app sat in the background arrives
				// the moment it is looked at again, not on the next cold launch.
				await CeresifyNoticeDelivery.deliverPending()
			}
		}
	}
	
	/// The full-screen refusal, in the same shape for all three reasons.
	///
	/// Only one of them has anything to offer — a device with no certificate
	/// can go and register — so the button is optional and the other two get
	/// the message alone.
	@ViewBuilder
	private func _stop(
		icon: String,
		title: String,
		message: String,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) -> some View {
		ZStack {
			Color(uiColor: CeresifyPalette.background ?? .systemBackground)
				.ignoresSafeArea()
			
			VStack(spacing: 14) {
				Image(systemName: icon)
					.font(.system(size: 46))
					.foregroundStyle(Color.ceresifyGold)
				
				Text(verbatim: title)
					.font(.title2.bold())
					.foregroundStyle(Color.ceresifyTitle)
				
				Text(verbatim: message)
					.font(.subheadline)
					.foregroundStyle(Color.ceresifySubtitle)
					.multilineTextAlignment(.center)
				
				if let actionTitle, let action {
					Button(action: action) {
						Text(verbatim: actionTitle).bg()
					}
					.padding(.top, 6)
				}
			}
			.padding(.horizontal, 34)
		}
	}
}

// MARK: - Opening screen
/// The screen the shop can put in front of the store, with its own artwork and
/// wording.
struct CeresifyOpeningView: View {
	let splash: CeresifyConfig.Splash
	/// What the app is busy with, on a launch that is waiting rather than
	/// being shown the shop's own screen. Nil says nothing at all.
	var status: String?

	@State private var _hasAppeared = false
	/// The slow breath under the artwork. The screen used to hold a still
	/// image over a still spinner, which on the launch that actually waits is
	/// indistinguishable from an app that has stopped.
	@State private var _isBreathing = false

	var body: some View {
		ZStack {
			Color(uiColor: CeresifyPalette.background ?? .systemBackground)
				.ignoresSafeArea()

			VStack(spacing: 16) {
				_artwork
					.scaleEffect(_isBreathing ? 1.04 : 0.97)

				if !splash.title.isEmpty {
					Text(verbatim: splash.title)
						.font(.title.bold())
						.foregroundStyle(Color.ceresifyGold)
				}

				if !splash.subtitle.isEmpty {
					Text(verbatim: splash.subtitle)
						.font(.subheadline)
						.foregroundStyle(Color.ceresifySubtitle)
						.multilineTextAlignment(.center)
				}

				_WaitingBarView()
					.padding(.top, 8)

				if let status, !status.isEmpty {
					Text(verbatim: status)
						.font(.footnote)
						.foregroundStyle(Color.ceresifySubtitle)
						.multilineTextAlignment(.center)
				}
			}
			.padding(.horizontal, 34)
			.opacity(_hasAppeared ? 1 : 0)
			.scaleEffect(_hasAppeared ? 1 : 0.94)
		}
		.onAppear {
			withAnimation(.smooth(duration: 0.45)) { _hasAppeared = true }
			withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
				_isBreathing = true
			}
		}
	}

	/// The shop's own artwork if it set any — the opening screen's image, or
	/// failing that the store's logo — and a plain mark otherwise.
	private var _artworkURL: URL? {
		for candidate in [splash.imageURL, CeresifyConfigManager.shared.config.theme.logoURL] {
			if !candidate.isEmpty, let url = URL(string: candidate) { return url }
		}
		
		return nil
	}
	
	@ViewBuilder
	private var _artwork: some View {
		if let url = _artworkURL {
			LazyImage(url: url) { state in
				if let image = state.image {
					image
						.resizable()
						.scaledToFit()
				}
			}
			.frame(maxWidth: 220, maxHeight: 220)
		} else {
			Image(systemName: "bag.fill")
				.font(.system(size: 62))
				.foregroundStyle(Color.ceresifyGold)
		}
	}
}

// MARK: - Waiting bar
/// A gold segment shuttling along its track.
///
/// Indeterminate on purpose: the app is waiting on an answer, and there is no
/// honest fraction of it to draw.
private struct _WaitingBarView: View {
	private let _width: CGFloat = 190
	private let _segment: CGFloat = 62

	@State private var _isRunning = false

	var body: some View {
		Capsule()
			.fill(Color.ceresifyGold.opacity(0.16))
			.frame(width: _width, height: 4)
			.overlay(alignment: .leading) {
				Capsule()
					.fill(Color.ceresifyGold)
					.frame(width: _segment, height: 4)
					// Offset rather than laid out, so the travel is the same
					// in both reading directions.
					.offset(x: _isRunning ? _width - _segment : 0)
			}
			.clipShape(Capsule())
			.onAppear {
				withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
					_isRunning = true
				}
			}
	}
}
