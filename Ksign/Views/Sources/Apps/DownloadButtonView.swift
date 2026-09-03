//
//  DownloadButtonView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import CoreData
import Combine
import AltSourceKit
import NimbleViews
import NimbleExtensions

/// Walks an app all the way from the catalog onto the device without leaving the
/// store: `Get` downloads it, `Sign` signs the imported copy, and `Install` hands
/// the signed build to the installer — each step replacing the one before it as
/// soon as its result lands in storage.
struct DownloadButtonView: View {
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared
	/// The store's own wording for these three steps, which the shop can
	/// change from the admin panel without a new build.
	@ObservedObject private var _config = CeresifyConfigManager.shared

	@State private var downloadProgress: Double = 0
	@State private var _isExtracting = false
	@State private var _bytesDownloaded: Int64 = 0
	@State private var _totalBytes: Int64 = 0
	@State private var cancellable: AnyCancellable?
	@State private var _signingApp: AnyApp?
	@State private var _installingApp: AnyApp?
	
	@State private var _isCloudSigning = false
	@State private var _cloudError: String?
	@State private var _isEnrollmentPresenting = false
	@State private var _isOptionsPresenting = false
	
	/// Get opens the progress sheet: the wait is the part worth showing, and a
	/// pill in a list row is too small to say how much of it is left.
	@State private var _isProgressPresenting = false
	
	/// Set for entries whose Ceresify identity isn't visible in the download
	/// URL — the featured apps, which the server signs by id.
	private let _explicitCloudSource: CeresifySignSource?
	
	/// Ceresify signs its own builds on the server, the way the website does.
	/// Anything else — a build the user imported, or an app from someone
	/// else's source — stays on the device and goes through the local signer.
	///
	/// A featured card names its build by id rather than by URL, but *where*
	/// it is signed is still the shop's call: a rule pinning that app to the
	/// device, or a size limit it is over, drops the cloud path here too and
	/// sends it down Get → Sign → Install like anything else.
	private var _cloudSource: CeresifySignSource? {
		guard let explicit = _explicitCloudSource else {
			return CeresifyCloudSigner.source(for: app)
		}
		
		return CeresifyCloudSigner.place(for: app) == .server ? explicit : nil
	}
	
	/// What the options sheet is opened on — the server's reference to the
	/// build where the server signs it, and the plain download URL otherwise.
	private var _optionsSource: CeresifySignSource? {
		if let source = _cloudSource { return source }
		return app.currentDownloadUrl.map(CeresifySignSource.ipaURL)
	}
	
	// Driven by Core Data so the button advances on its own the moment a signed
	// or imported build appears, with no manual refresh from the signing screen.
	@FetchRequest private var _signed: FetchedResults<Signed>
	@FetchRequest private var _imported: FetchedResults<Imported>
	
	init(app: ASRepository.App, cloudSource: CeresifySignSource? = nil) {
		self.app = app
		self._explicitCloudSource = cloudSource
		
		// A nil identifier can never match a stored build, so use a predicate
		// that stays empty rather than one that matches everything.
		//
		// Matched on the download URL rather than the bundle identifier: a
		// store lists several builds of one app under the same identifier —
		// YouTube, YouTube Reborn, YTLite — and going by identifier alone made
		// downloading any one of them turn every sibling's button into
		// "Install". Builds stored before the URL was recorded have none, so
		// they still fall back to the identifier and keep working.
		let predicate: NSPredicate
		
		if let identifier = app.id {
			if let source = app.currentDownloadUrl {
				predicate = NSPredicate(
					format: "source == %@ OR (source == nil AND identifier == %@)",
					source as NSURL,
					identifier
				)
			} else {
				predicate = NSPredicate(format: "identifier == %@", identifier)
			}
		} else {
			predicate = NSPredicate(value: false)
		}
		
		self.__signed = FetchRequest(
			entity: Signed.entity(),
			sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
			predicate: predicate,
			animation: .snappy
		)
		self.__imported = FetchRequest(
			entity: Imported.entity(),
			sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
			predicate: predicate,
			animation: .snappy
		)
	}

	var body: some View {
		ZStack {
			if let cloudSource = _cloudSource {
				_cloudPill(for: cloudSource)
			} else if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
				_progressPill(for: currentDownload)
			} else if let signed = _signed.first {
				_pill(_installTitle) {
					_installingApp = AnyApp(base: signed)
				}
			} else if let imported = _imported.first {
				_pill(_signTitle) {
					_signingApp = AnyApp(base: imported)
				}
			} else {
				_pill(_getTitle) {
					guard let url = app.currentDownloadUrl else { return }
					_ = downloadManager.startDownload(from: url, id: app.currentUniqueId)
					_isProgressPresenting = true
				}
				// The same options the cloud pill offers. A build signed on the
				// device is exactly the one whose options are worth setting
				// first, so leaving the entry off this pill was backwards.
				.contextMenu {
					Button(.localized("Signing options"), systemImage: "slider.horizontal.3") {
						_isOptionsPresenting = true
					}
				}
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
		.fullScreenCover(item: $_signingApp) { app in
			SigningView(app: app.base)
		}
		.sheet(isPresented: $_isEnrollmentPresenting) {
			CeresifyEnrollmentView()
		}
		.sheet(isPresented: $_isOptionsPresenting) {
			if let source = _optionsSource {
				CloudSignOptionsView(app: app, source: source)
			}
		}
		.sheet(isPresented: $_isProgressPresenting) {
			DownloadProgressView(
				title: app.currentName,
				iconURL: app.iconURL,
				downloadId: app.currentUniqueId,
				isCloudSigning: _isCloudSigning
			)
		}
		.alert(
			String.localized("Signing failed."),
			isPresented: Binding(
				get: { _cloudError != nil },
				set: { if !$0 { _cloudError = nil } }
			)
		) {
			Button(String.localized("OK"), role: .cancel) {}
		} message: {
			Text(verbatim: _cloudError ?? "")
		}
		.sheet(item: $_installingApp) { app in
			InstallPreviewView(app: app.base)
				.presentationDetents([.height(200)])
				.presentationDragIndicator(.visible)
		}
	}
	
	@ViewBuilder
	private func _cloudPill(for source: CeresifySignSource) -> some View {
		if _isCloudSigning {
			ProgressView()
				.frame(width: 31, height: 31)
				.compatTransition()
		} else {
			_pill(_getTitle) {
				_cloudSign(source)
			}
			// The same options the app's page shows a button for, for the rows
			// that only have room for the pill.
			.contextMenu {
				Button(.localized("Signing options"), systemImage: "slider.horizontal.3") {
					_isOptionsPresenting = true
				}
			}
		}
	}
	
	private func _cloudSign(_ source: CeresifySignSource) {
		// Nothing can be signed for a device the server has never seen.
		guard CeresifyEnrollmentModel.storedUdid != nil else {
			_isEnrollmentPresenting = true
			return
		}
		
		_isCloudSigning = true
		_isProgressPresenting = true
		
		Task {
			do {
				let installURL = try await CeresifyCloudSigner.sign(source)
				_isProgressPresenting = false
				UIApplication.open(installURL)
			} catch {
				_isProgressPresenting = false
				_cloudError = error.localizedDescription
			}
			
			_isCloudSigning = false
		}
	}
	
	private var _getTitle: String {
		_config.text(_config.config.strings.get, fallback: .localized("Get"))
	}
	
	private var _signTitle: String {
		_config.text(_config.config.strings.sign, fallback: .localized("Sign"))
	}
	
	private var _installTitle: String {
		_config.text(_config.config.strings.install, fallback: .localized("Install"))
	}
	
	@ViewBuilder
	private func _pill(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
				.lineLimit(0)
				.font(.headline.bold())
				.foregroundStyle(Color.ceresifyAccent)
				.padding(.horizontal, 24)
				.padding(.vertical, 6)
				.background(Color(uiColor: .quaternarySystemFill))
				.clipShape(Capsule())
		}
		.buttonStyle(.borderless)
		.compatTransition()
	}
	
	/// What the tap turns into: the pill stays where it was and fills up, so the
	/// app being fetched keeps its place in the row and the wait has a visible
	/// end to it.
	///
	/// The number matters more than the ring did — "how much is left" is the
	/// question being asked — so the percentage is spelled out, and the bar
	/// behind it moves with `.smooth` rather than jumping between updates.
	@ViewBuilder
	private func _progressPill(for currentDownload: Download) -> some View {
		let percent = Int((downloadProgress * 100).rounded())
		
		ZStack {
			Capsule()
				.fill(Color(uiColor: .quaternarySystemFill))
			
			// The fill is clipped to the capsule so it reads as one control
			// filling up rather than a bar drawn inside a pill.
			GeometryReader { proxy in
				Capsule()
					.fill(Color.ceresifyAccent.opacity(0.28))
					.frame(width: max(0, min(1, downloadProgress)) * proxy.size.width)
					.animation(.smooth, value: downloadProgress)
			}
			
			HStack(spacing: 4) {
				if _isExtracting {
					_extractingIcon
					
					Text(.localized("Extracting"))
						.font(.caption.bold())
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				} else {
					Image(systemName: "arrow.down")
						.font(.system(size: 9, weight: .bold))
					
					Text(verbatim: "\(percent)%")
						.font(.subheadline.bold())
						.monospacedDigit()
						.contentTransition(.numericText())
						.animation(.smooth, value: percent)
				}
			}
			.foregroundStyle(Color.ceresifyAccent)
			.padding(.horizontal, 10)
		}
		.frame(width: 92, height: 31)
		.clipShape(Capsule())
		.contentShape(Capsule())
		.onTapGesture {
			// Cancelling now lives on the sheet, next to the numbers it applies
			// to, so a stray tap on a row can't throw a download away.
			_isProgressPresenting = true
		}
		.accessibilityLabel(Text(verbatim: _downloadingTitle))
		.accessibilityValue(Text(verbatim: _accessibilityValue(percent: percent)))
		.compatTransition()
	}
	
	@ViewBuilder
	private var _extractingIcon: some View {
		let icon = Image(systemName: "archivebox.fill")
			.font(.system(size: 11, weight: .bold))
		
		if #available(iOS 17, *) {
			icon.symbolEffect(.pulse)
		} else {
			icon
		}
	}
	
	private var _downloadingTitle: String {
		_config.text(_config.config.strings.downloading, fallback: .localized("Downloading"))
	}
	
	private func _accessibilityValue(percent: Int) -> String {
		guard !_isExtracting else {
			return .localized("Extracting")
		}
		
		guard _totalBytes > 0 else {
			return "\(percent)%"
		}
		
		return "\(percent)% — \(_bytesDownloaded.formattedByteCount) / \(_totalBytes.formattedByteCount)"
	}
	
	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			downloadProgress = 0
			_isExtracting = false
			_bytesDownloaded = 0
			_totalBytes = 0
			return
		}
		_update(from: download)

		let publisher = Publishers.CombineLatest3(
			download.$progress,
			download.$unpackageProgress,
			download.$bytesDownloaded
		)

		cancellable = publisher.sink { _, _, _ in
			self._update(from: download)
		}
	}
	
	private func _update(from download: Download) {
		downloadProgress = download.overallProgress
		_isExtracting = download.unpackageProgress > 0
		_bytesDownloaded = download.bytesDownloaded
		_totalBytes = download.totalBytes
	}
}
