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
			.onAppear {
				// The profile is asked for once, at the very start, and never
				// again: a device that has registered is known to the server
				// for good, and its certificate is fetched in the background
				// by `CeresifyQuickEntry` — including on the launch after a
				// subscription is finally activated. Coming back to this
				// screen would only offer a second profile, which changes
				// nothing about an account that hasn't been issued one yet.
				//
				// Anyone who already has a certificate is left alone too.
				guard
					!_hasSeenEnrollment,
					CeresifyEnrollmentModel.storedUdid == nil,
					_certificates.isEmpty
				else {
					return
				}
				
				_isEnrollmentPresenting = true
			}
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
