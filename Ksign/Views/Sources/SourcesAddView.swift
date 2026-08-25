//
//  SourcesAddView.swift
//  Feather
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesAddView: View {
	@Environment(\.dismiss) var dismiss
	
	@State private var _sourceURL = ""
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Add Source"), displayMode: .inline) {
			Form {
				Section {
					TextField(.localized("Source Repo URL"), text: $_sourceURL)
						.keyboardType(.URL)
				} footer: {
					Text(.localized("Enter a URL to start validation."))
				}
			}
			.toolbar {
				NBToolbarButton(role: .cancel)
				
				NBToolbarButton(
					.localized("Save"),
					style: .text,
					placement: .confirmationAction,
					isDisabled: _sourceURL.isEmpty
				) {
					FR.handleSource(_sourceURL) {
						dismiss()
					}
				}
			}
		}
	}
}
