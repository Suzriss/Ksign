//
//  CloudSignOptionsView.swift
//  Ksign
//
//  Changing a store build — its name, icon, version, identifier — before
//  Ceresify signs it.
//

import SwiftUI
import PhotosUI
import AltSourceKit
import NimbleViews
import NimbleExtensions
import NukeUI

/// The sheet behind a store app's `Options`, and the duplicate that comes with
/// it.
///
/// Ceresify signs its own builds on the server, so unlike the local signer
/// nothing here is applied on the device: the fields ride along with the sign
/// request and the server rewrites the IPA before signing it. A field left
/// empty is not sent at all, which is what keeps an untouched sheet identical
/// to tapping `Get`.
///
/// A duplicate is the same build signed under an identifier of its own. iOS
/// tells apps apart by that identifier alone, so a copy that keeps the
/// original's would replace it rather than sit beside it — the server invents
/// one when the field is left empty.
struct CloudSignOptionsView: View {
	@Environment(\.dismiss) private var _dismiss
	
	let app: ASRepository.App
	let source: CeresifySignSource
	
	@State private var _name = ""
	@State private var _version = ""
	@State private var _identifier = ""
	@State private var _duplicate = false
	@State private var _icon: UIImage?
	
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _selectedPhoto: PhotosPickerItem?
	@State private var _isEnrollmentPresenting = false
	@State private var _isSigning = false
	@State private var _error: String?
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Signing options"), displayMode: .inline) {
			Form {
				_customization()
				_duplication()
				
				if let error = _error {
					Section {
						Text(verbatim: error)
							.font(.subheadline)
							.foregroundStyle(.red)
					}
				}
			}
			.disabled(_isSigning)
			.safeAreaInset(edge: .bottom) {
				Button {
					_sign()
				} label: {
					NBSheetButton(
						title: _isSigning
						? .localized("Signing")
						: (_duplicate ? .localized("Duplicate & Install") : .localized("Sign & Install"))
					)
				}
				.disabled(_isSigning)
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
				
				if _isSigning {
					ToolbarItem(placement: .topBarTrailing) {
						ProgressView()
					}
				}
			}
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.image],
					onDocumentsPicked: { urls in
						guard let url = urls.first else { return }
						_icon = UIImage.fromFile(url)?.resizeToSquare()
					}
				)
			}
			.sheet(isPresented: $_isEnrollmentPresenting) {
				CeresifyEnrollmentView()
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }
				
				Task {
					if
						let data = try? await newValue.loadTransferable(type: Data.self),
						let image = UIImage(data: data)?.resizeToSquare()
					{
						_icon = image
					}
				}
			}
			.animation(.smooth, value: _isSigning)
		}
	}
}

// MARK: - Extension: View
extension CloudSignOptionsView {
	@ViewBuilder
	private func _customization() -> some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Choose from Files")) { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos")) { _isImagePickerPresenting = true }
				
				if _icon != nil {
					Divider()
					Button(.localized("Reset"), role: .destructive) { _icon = nil }
				}
			} label: {
				HStack(spacing: 12) {
					_iconView()
					
					Text(.localized("App Icon"))
						.foregroundStyle(.primary)
					
					Spacer()
				}
			}
			
			_field(
				.localized("Name"),
				placeholder: app.currentName,
				text: $_name
			)
			
			_field(
				.localized("Identifier"),
				placeholder: _duplicate
				? .localized("Picked for you")
				: (app.id ?? .localized("Unknown")),
				text: $_identifier
			)
			
			_field(
				.localized("Version"),
				placeholder: app.currentVersion ?? .localized("Unknown"),
				text: $_version
			)
		} footer: {
			Text(.localized("Anything left empty stays as the app already has it."))
		}
	}
	
	@ViewBuilder
	private func _duplication() -> some View {
		Section {
			Toggle(.localized("Duplicate"), isOn: $_duplicate)
		} footer: {
			Text(.localized("Installs a second copy under its own identifier, so it sits beside the app you already have instead of replacing it."))
		}
	}
	
	@ViewBuilder
	private func _iconView() -> some View {
		if let icon = _icon {
			Image(uiImage: icon)
				.appIconStyle(size: 44)
		} else if let iconURL = app.iconURL {
			LazyImage(url: iconURL) { state in
				if let image = state.image {
					image.appIconStyle(size: 44)
				} else {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(Color(uiColor: .quaternarySystemFill))
						.frame(width: 44, height: 44)
				}
			}
		} else {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(Color(uiColor: .quaternarySystemFill))
				.frame(width: 44, height: 44)
		}
	}
	
	@ViewBuilder
	private func _field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
		LabeledContent(title) {
			TextField(placeholder, text: text)
				.multilineTextAlignment(.trailing)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
		}
	}
}

// MARK: - Extension: View (signing)
extension CloudSignOptionsView {
	private var _options: CeresifySignOptions {
		CeresifySignOptions(
			name: Self._trimmed(_name),
			version: Self._trimmed(_version),
			bundleIdentifier: Self._trimmed(_identifier),
			duplicate: _duplicate,
			icon: _icon
		)
	}
	
	private static func _trimmed(_ value: String) -> String? {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
	
	private func _sign() {
		// Nothing can be signed for a device the server has never seen.
		guard CeresifyEnrollmentModel.storedUdid != nil else {
			_isEnrollmentPresenting = true
			return
		}
		
		_isSigning = true
		_error = nil
		
		Task {
			do {
				let installURL = try await CeresifyCloudSigner.sign(source, options: _options)
				_isSigning = false
				UIApplication.open(installURL)
				_dismiss()
			} catch {
				_error = error.localizedDescription
				_isSigning = false
			}
		}
	}
}
