//
//  VariedTabbarView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import UIKit

struct VariedTabbarView: View {
	/// Set the moment the device registers, so the profile is offered exactly
	/// once and the store never asks for it again.
	@AppStorage("Ceresify.hasSeenEnrollment") private var _hasSeenEnrollment: Bool = false
	
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: []
	) private var _certificates: FetchedResults<CertificatePair>
	
	@State private var _isEnrollmentPresenting = false
	
	init() {}
	
	var body: some View {
		_tabs
			.fullScreenCover(isPresented: $_isEnrollmentPresenting) {
				CeresifyEnrollmentView()
			}
			.onAppear(perform: _offerProfileIfNeeded)
			// The catalog is asked for the moment the store is up, not when
			// the Apps tab is first opened: by the time it is, the stored
			// copy is drawn and the fresh one is usually already here.
			.task {
				await SourcesViewModel.shared.fetchSources(Storage.shared.getSources())
			}
			// The first answer from the server is what settles the gate, and
			// the gate is what decides whether this view stays in the tree at
			// all — so the offer waits for it and is reconsidered when it
			// lands.
			.onChange(of: _config.isReachable) { _ in _offerProfileIfNeeded() }
			.onChange(of: _config.gate) { gate in
				// A gate that has since closed takes this whole view with it.
				// Anything it is still presenting would be left behind with
				// nothing underneath, so it comes down first.
				if gate != .open { _isEnrollmentPresenting = false }
			}
	}
	
	/// Offers the registration profile, once, and only once it is safe to.
	///
	/// The profile is asked for once at the very start and never again: a
	/// device that has registered is known to the server for good, and its
	/// certificate is fetched in the background by `CeresifyQuickEntry` —
	/// including on the launch after a subscription is finally activated.
	/// Coming back to this screen would only offer a second profile, which
	/// changes nothing about an account that hasn't been issued one yet.
	/// Anyone who already has a certificate is left alone too.
	///
	/// What it also waits for is the config's first answer. A launch starts
	/// with whatever config was stored, which on a fresh install is nothing at
	/// all — so the gate reads `open`, this view is built, and the profile is
	/// offered. Moments later the server answers, the gate can close, and this
	/// view is taken out of the tree while it is in the middle of presenting a
	/// full-screen cover. UIKit is left holding a presentation with no
	/// presenter: a black screen that no gesture dismisses and only a relaunch
	/// clears — which is exactly the first launch of a fresh install, and
	/// exactly why the second one was fine.
	private func _offerProfileIfNeeded() {
		guard
			_config.isReachable != nil,
			_config.gate == .open,
			!_isEnrollmentPresenting,
			!_hasSeenEnrollment,
			CeresifyEnrollmentModel.storedUdid == nil,
			_certificates.isEmpty
		else {
			return
		}
		
		_isEnrollmentPresenting = true
	}
	
	@ViewBuilder
	private var _tabs: some View {
		// iPad gets the hand-drawn bar: from iPadOS 18 on, the system puts
		// TabView's own bar at the top of the window.
		if UIDevice.current.userInterfaceIdiom == .pad {
			BottomTabbarView()
		} else if #available(iOS 18, *) {
			ExtendedTabbarView()
		} else {
			TabbarView()
		}
	}
}
