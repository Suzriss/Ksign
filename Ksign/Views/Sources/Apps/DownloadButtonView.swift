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

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?
	@State private var _signingApp: AnyApp?
	@State private var _installingApp: AnyApp?
	
	@State private var _isCloudSigning = false
	@State private var _cloudError: String?
	@State private var _isEnrollmentPresenting = false
	
	/// Set for entries whose Ceresify identity isn't visible in the download
	/// URL — the featured apps, which the server signs by id.
	private let _explicitCloudSource: CeresifySignSource?
	
	/// Ceresify signs its own builds on the server, the way the website does.
	/// Anything else — a build the user imported, or an app from someone
	/// else's source — stays on the device and goes through the local signer.
	private var _cloudSource: CeresifySignSource? {
		_explicitCloudSource ?? CeresifyCloudSigner.source(for: app)
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
		let predicate = app.id.map { NSPredicate(format: "identifier == %@", $0) }
			?? NSPredicate(value: false)
		
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
				_progressRing(for: currentDownload)
			} else if let signed = _signed.first {
				_pill(.localized("Install")) {
					_installingApp = AnyApp(base: signed)
				}
			} else if let imported = _imported.first {
				_pill(.localized("Sign")) {
					_signingApp = AnyApp(base: imported)
				}
			} else {
				_pill(.localized("Get")) {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(from: url, id: app.currentUniqueId)
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
			_pill(.localized("Get")) {
				_cloudSign(source)
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
		
		Task {
			do {
				let installURL = try await CeresifyCloudSigner.sign(source)
				UIApplication.open(installURL)
			} catch {
				_cloudError = error.localizedDescription
			}
			
			_isCloudSigning = false
		}
	}
	
	@ViewBuilder
	private func _pill(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
				.lineLimit(0)
				.font(.headline.bold())
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 24)
				.padding(.vertical, 6)
				.background(Color(uiColor: .quaternarySystemFill))
				.clipShape(Capsule())
		}
		.buttonStyle(.borderless)
		.compatTransition()
	}
	
	@ViewBuilder
	private func _progressRing(for currentDownload: Download) -> some View {
		ZStack {
			Circle()
				.trim(from: 0, to: downloadProgress)
				.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
				.rotationEffect(.degrees(-90))
				.frame(width: 31, height: 31)
				.animation(.smooth, value: downloadProgress)

			Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
				.foregroundStyle(.tint)
				.font(.footnote).bold()
		}
		.onTapGesture {
			if downloadProgress <= 0.75 {
				downloadManager.cancelDownload(currentDownload)
			}
		}
		.compatTransition()
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			downloadProgress = 0
			return
		}
		downloadProgress = download.overallProgress

		let publisher = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)

		cancellable = publisher.sink { _, _ in
			downloadProgress = download.overallProgress
		}
	}
}
