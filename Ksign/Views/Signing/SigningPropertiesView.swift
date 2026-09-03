//
//  SigningAppPropertiesView.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningPropertiesView: View {
	@Environment(\.dismiss) var dismiss
	
	@State private var text: String = ""
	@State private var _buildNumber: String = ""
	
	var saveButtonDisabled: Bool {
		text == initialValue && _buildNumber == (initialBuildNumber ?? "")
	}
	
	var title: String
	var initialValue: String
	/// The build number the page opens on — what the bundle carries now, or
	/// what was picked for it earlier in this sheet.
	var initialBuildNumber: String? = nil
	@Binding var bindingValue: String?
	/// Where the build number goes. Only the Identifier page is handed one;
	/// the rest of the pages edit their one field and nothing else.
	var buildNumber: Binding<String?>? = nil
	
	// MARK: Body
	var body: some View {
		NBList(title) {
			TextField(initialValue, text: $text)
				.textInputAutocapitalization(.none)
			
			if buildNumber != nil {
				Section {
					HStack {
						TextField(initialBuildNumber ?? "1", text: $_buildNumber)
							.keyboardType(.numbersAndPunctuation)
							.autocorrectionDisabled()
						
						Stepper(
							String.localized("Build number"),
							onIncrement: { _step(by: 1) },
							onDecrement: { _step(by: -1) }
						)
						.labelsHidden()
					}
				} header: {
					Text(.localized("Build number"))
				} footer: {
					Text(.localized("What iOS compares to decide whether an install is an update. Raise it to install over a copy that is already there."))
				}
			}
		}
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .topBarTrailing,
				isDisabled: saveButtonDisabled
			) {
				if !saveButtonDisabled {
					_save()
					dismiss()
				}
			}
		}
		.onAppear {
			text = initialValue
			_buildNumber = initialBuildNumber ?? ""
		}
	}
	
	/// Only what actually changed is written back: writing the identifier it
	/// already had would make an untouched field look like a choice.
	private func _save() {
		if text != initialValue {
			bindingValue = text
		}
		
		let trimmed = _buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
		
		if trimmed != (initialBuildNumber ?? "") {
			buildNumber?.wrappedValue = trimmed.isEmpty ? nil : trimmed
		}
	}
	
	/// Moves the build number up or down by one.
	///
	/// A dotted number (`1.2.3`) moves on its last part, so it stays the
	/// shape it was; anything that isn't a number at all starts from one.
	private func _step(by delta: Int) {
		let current = _buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
		var parts = current.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
		
		guard
			let last = parts.last,
			let value = Int(last)
		else {
			_buildNumber = String(max(1, 1 + delta))
			return
		}
		
		parts[parts.count - 1] = String(max(0, value + delta))
		_buildNumber = parts.joined(separator: ".")
	}
}
