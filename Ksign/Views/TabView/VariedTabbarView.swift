//
//  VariedTabbarView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import UIKit

struct VariedTabbarView: View {
	init() {}
	
	var body: some View {
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
