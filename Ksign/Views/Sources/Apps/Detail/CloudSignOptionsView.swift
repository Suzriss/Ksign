//
//  CloudSignOptionsView.swift
//  Ksign
//
//  Changing a store build — its name, icon, version, identifier — before
//  Ceresify signs it.
//

import SwiftUI
import CoreData
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
	
	@ObservedObject private var _downloadManager = DownloadManager.shared
	/// Set once Advanced has been asked for, so the signer opens by itself the
	/// moment the download lands rather than making the user come back.
	@State private var _isWaitingForBuild = false
	@State private var _signingApp: AnyApp?
	
	/// The signer's own options, editable here and now.
	///
	/// Advanced used to be four rows that each started a download and then
	/// handed the build to the signer — so the one thing the user came for,
	/// picking the options, only became possible after the wait. These are the
	/// same options the Signer tab edits, started from the saved defaults, and
	/// they carry into the signer when the build finally arrives.
	@State private var _advancedOptions: Options = OptionsManager.shared.options
	
	/// The copy of this build already on the device, if there is one. Matched
	/// on the download URL the same way the store's pill matches it: a store
	/// lists several builds under one identifier, and going by identifier
	/// alone would hand back a sibling.
	@FetchRequest private var _imported: FetchedResults<Imported>
	
	init(app: ASRepository.App, source: CeresifySignSource) {
		self.app = app
		self.source = source
		
		let predicate: NSPredicate
		
		if let url = app.currentDownloadUrl {
			predicate = NSPredicate(format: "source == %@", url as NSURL)
		} else if let identifier = app.id {
			predicate = NSPredicate(format: "identifier == %@", identifier)
		} else {
			predicate = NSPredicate(value: false)
		}
		
		self.__imported = FetchRequest(
			entity: Imported.entity(),
			sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
			predicate: predicate,
			animation: .snappy
		)
	}
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Signing options"), displayMode: .inline) {
			Form {
				_customization()
				_duplication()
				_advanced()
				
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
					// Anything picked under Advanced is the device's work, so
					// the same button fetches the build and signs it here
					// instead of asking the server for something it cannot do.
					if _signsOnDevice {
						_startAdvanced()
					} else {
						_sign()
					}
				} label: {
					NBSheetButton(title: _actionTitle)
				}
				.disabled(_isSigning || _isWaitingForBuild)
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
			.fullScreenCover(item: $_signingApp) { app in
				// Opened on what was picked here, so nothing chosen before the
				// download has to be chosen a second time.
				SigningView(
					app: app.base,
					opensModify: true,
					initialOptions: _localOptions,
					initialIcon: _icon
				)
			}
			.onChange(of: _imported.first?.uuid) { _ in
				_openSignerIfBuildArrived()
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
	/// Whether anything under Advanced was actually touched.
	///
	/// Compared against the saved defaults rather than tracked with a flag: a
	/// user who opens Properties, flips a toggle and flips it back has changed
	/// nothing, and should still get the fast server path.
	var _didCustomizeAdvanced: Bool {
		_advancedOptions != OptionsManager.shared.options
	}
	
	/// Whether this one is signed here rather than by Ceresify.
	///
	/// Either because the shop said so for this app — a rule in the panel, or
	/// a size over the limit — or because the user picked something under
	/// Advanced, which is work only the device can do.
	var _signsOnDevice: Bool {
		_didCustomizeAdvanced || CeresifyCloudSigner.place(for: app) == .device
	}
	
	/// What the bottom button says, which is also what it will do.
	var _actionTitle: String {
		if _isSigning { return .localized("Signing") }
		
		if _isWaitingForBuild {
			guard let download = _download else { return .localized("Downloading") }
			return "\(Int((download.overallProgress * 100).rounded()))%"
		}
		
		if _signsOnDevice { return .localized("Download & Sign here") }
		
		return _duplicate ? .localized("Duplicate & Install") : .localized("Sign & Install")
	}
	
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

// MARK: - Extension: View (advanced)
extension CloudSignOptionsView {
	/// Whether a download of this build is running right now.
	private var _download: Download? {
		_downloadManager.getDownload(by: app.currentUniqueId)
	}
	
	/// The signer's own Advanced pane, reached from the store.
	///
	/// The fields above are applied by Ceresify, which rewrites the IPA before
	/// it signs it — that is all a server can do to a build it never installs.
	/// Everything here is the device's work, so choosing it means the build is
	/// downloaded and signed on this device with the certificate already
	/// installed, exactly as a build brought in by hand is.
	///
	/// Tweaks and Properties open straight away and edit the real options:
	/// nothing about a `.dylib` the user is adding or a toggle they are
	/// flipping needs the IPA in hand, and making them wait for a download
	/// before they could even see the pane was the whole complaint. Only the
	/// two that read what is *inside* the build — its existing dylibs and its
	/// frameworks — have to fetch it first, and they say so.
	@ViewBuilder
	private func _advanced() -> some View {
		NBSection(.localized("Advanced")) {
			NavigationLink {
				SigningTweaksView(options: $_advancedOptions)
			} label: {
				Label(.localized("Tweaks"), systemImage: "wrench.adjustable")
					.foregroundStyle(.primary)
			}
			
			NavigationLink {
				Form {
					SigningOptionsView(
						options: $_advancedOptions,
						temporaryOptions: OptionsManager.shared.options
					)
				}
				.navigationTitle(.localized("Properties"))
			} label: {
				Label(.localized("Properties"), systemImage: "slider.horizontal.3")
					.foregroundStyle(.primary)
			}
		} footer: {
			Text(.localized("Pick these now — nothing is downloaded until you start. What you set here is signed onto the build on this device, with the certificate already installed."))
		}
		
		NBSection(.localized("Needs the build")) {
			ForEach(Self._buildEntries, id: \.title) { entry in
				_advancedRow(entry)
			}
		} footer: {
			Text(.localized("These two read what is already inside the app, so the build is fetched first and the signer opens on it — with everything you set above already applied."))
		}
	}
	
	private struct _AdvancedEntry {
		let title: String
		let systemImage: String
	}
	
	/// The two panes that can only be drawn once the IPA is on the device.
	private static var _buildEntries: [_AdvancedEntry] {
		[
			_AdvancedEntry(title: .localized("Existing Dylibs"), systemImage: "puzzlepiece.extension"),
			_AdvancedEntry(title: .localized("Frameworks & PlugIns"), systemImage: "shippingbox")
		]
	}
	
	@ViewBuilder
	private func _advancedRow(_ entry: _AdvancedEntry) -> some View {
		Button {
			_startAdvanced()
		} label: {
			LabeledContent {
				if _isWaitingForBuild, let download = _download {
					Text(verbatim: "\(Int((download.overallProgress * 100).rounded()))%")
						.monospacedDigit()
				} else if _isWaitingForBuild {
					ProgressView()
				} else {
					Image(systemName: "arrow.down.circle")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			} label: {
				Label(entry.title, systemImage: entry.systemImage)
					.foregroundStyle(.primary)
			}
		}
		.disabled(_isWaitingForBuild)
	}
	
	/// The options the local signer opens on: what was picked under Advanced,
	/// plus the name, identifier and version typed at the top of this sheet.
	///
	/// Those three are applied by Ceresify on the server path, so on the device
	/// path they have to be applied here or filling them in would quietly do
	/// nothing.
	private var _localOptions: Options {
		var options = _advancedOptions
		
		if let name = Self._trimmed(_name)              { options.appName = name }
		if let version = Self._trimmed(_version)        { options.appVersion = version }
		if let identifier = Self._trimmed(_identifier)  { options.appIdentifier = identifier }
		
		return options
	}
	
	/// Opens the signer straight away when the build is already here, and
	/// otherwise starts the download and waits for it.
	private func _startAdvanced() {
		if let imported = _imported.first {
			_signingApp = AnyApp(base: imported)
			return
		}
		
		guard let url = app.currentDownloadUrl else {
			_error = .localized("This app has no download to modify.")
			return
		}
		
		_isWaitingForBuild = true
		_ = _downloadManager.startDownload(from: url, id: app.currentUniqueId)
	}
	
	/// The download finishing is what puts the build in storage, and the fetch
	/// request noticing it is what gets us here.
	private func _openSignerIfBuildArrived() {
		guard
			_isWaitingForBuild,
			let imported = _imported.first
		else {
			return
		}
		
		_isWaitingForBuild = false
		_signingApp = AnyApp(base: imported)
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
