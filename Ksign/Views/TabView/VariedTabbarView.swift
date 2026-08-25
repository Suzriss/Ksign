//
//  VariedTabbarView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import UIKit

struct VariedTabbarView: View {
	/// Cleared only once the user has been through registration, so a launch
	/// with no certificate offers it instead of leaving them to find it.
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
				// Anyone who already has a certificate is left alone.
				if !_hasSeenEnrollment, _certificates.isEmpty {
					_isEnrollmentPresenting = true
				}
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
