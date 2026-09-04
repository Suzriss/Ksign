//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog
import Security

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss
	
	// Sharing
	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Ksign.cleanUpAfterInstall") private var _shouldCleanUpAfterInstall: Bool = true
	
	// Methods
    @AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
    @State private var progressTask: Task<Void, Never>?
    /// The hand-off to iOS, and the watch kept on it afterwards.
    @State private var _handoffTask: Task<Void, Never>?
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	@State var isSharing: Bool

	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
        let method = UserDefaults.standard.integer(forKey: "Feather.installationMethod")
		let viewModel = InstallerStatusViewModel(isIdevice: method == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if case .ready = newStatus {
				if _serverMethod == 0 {
					_handOffToSystem()
				} else if _serverMethod == 1 {
					_isWebviewPresenting = true
				}
			}
            
            if case .installing = newStatus {
                if progressTask == nil {
                    progressTask = startInstallProgressPolling(
                        bundleID: app.identifier!,
                        viewModel: viewModel
                    )
                }
            }
			
            switch newStatus {
            // Safari has done its part the moment the payload is asked for;
            // the rest of the install belongs to this screen.
            case .sendingPayload, .installing:
                _isWebviewPresenting = false
            case .completed:
                _isWebviewPresenting = false
                progressTask?.cancel()
                progressTask = nil
                BackgroundAudioManager.shared.stop()
                _cleanUpIfNeeded()
            case .broken(_):
                progressTask?.cancel()
                progressTask = nil
                BackgroundAudioManager.shared.stop()
            default:
                break
            }
		}
		.onAppear(perform: _install)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		.onDisappear {
            progressTask?.cancel()
            progressTask = nil
            _handoffTask?.cancel()
            _handoffTask = nil
			BackgroundAudioManager.shared.stop()
		}
	}
	
	/// Hands the install to iOS, and does not take its word for it.
	///
	/// `UIApplication.open` on an `itms-services://` link is the direct route,
	/// and since iOS 18 a sideloaded app has no entitlement for it: the call
	/// reports success, nothing opens, no prompt appears, and this screen sits
	/// on `Ready` for good — which is exactly what "the install never comes
	/// up" is. Nothing is reported because nothing failed, so the only way to
	/// know is to watch the server: if iOS had taken the link it would have
	/// come for the manifest within a moment.
	///
	/// When it doesn't, the link goes to Safari instead — by way of a page
	/// this device serves, since Safari is still allowed to open it. And if
	/// even that comes to nothing, what was found out goes on screen rather
	/// than being left to be guessed at.
	private func _handOffToSystem() {
		guard _handoffTask == nil else { return }
		
		let manifestLink = installer.iTunesLink
		let manifestUrl = installer.plistEndpoint.absoluteString
		let probeUrl = installer.pageEndpoint
		
		_handoffTask = Task { @MainActor in
			// One request at the installer's own server, over the same name,
			// port and certificate iOS is about to use.
			let (reachability, chain) = await _probe(probeUrl)
			let material = ServerInstaller.tlsSummary
			
			guard !Task.isCancelled else { return }
			
			let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
				UIApplication.shared.open(URL(string: manifestLink)!) { success in
					continuation.resume(returning: success)
				}
			}
			
			guard await _stillWaiting(for: 3) else { return }
			
			_isWebviewPresenting = true
			
			guard await _stillWaiting(for: 25) else { return }
			
			_isWebviewPresenting = false
			
			// An alert asked for over a dismissal still in progress is dropped,
			// and this one is the whole point of getting this far.
			try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
			
			guard !Task.isCancelled else { return }
			
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized(
					"iOS never asked for the install manifest, so nothing was offered to install.\n\nServer: %@\nChain: %@\nFiles: %@\nHand-off: %@\nManifest: %@",
					arguments: reachability,
					chain,
					material,
					opened ? "opened" : "refused",
					manifestUrl
				)
			)
		}
	}
	
	/// Waits out the given seconds and reports whether the manifest has still
	/// not been asked for.
	@MainActor
	private func _stillWaiting(for seconds: UInt64) async -> Bool {
		try? await Task.sleep(nanoseconds: seconds * NSEC_PER_SEC)
		
		guard !Task.isCancelled, case .ready = viewModel.status else { return false }
		
		return true
	}
	
	/// One request at the installer's own server, reported as it came back —
	/// along with what the server handed over and what iOS made of it, which
	/// is the part `itms-services://` will never say a word about.
	private func _probe(_ url: URL) async -> (result: String, chain: String) {
		var request = URLRequest(url: url)
		request.timeoutInterval = 10
		request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		
		let inspector = InstallProbeInspector()
		let session = URLSession(configuration: .ephemeral, delegate: inspector, delegateQueue: nil)
		
		defer { session.finishTasksAndInvalidate() }
		
		do {
			let (_, response) = try await session.data(for: request)
			return ("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", inspector.chain)
		} catch {
			let error = error as NSError
			return ("\(error.domain) \(error.code) — \(error.localizedDescription)", inspector.chain)
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	/// The app is on the device now, so the copies Ksign was holding on to are
	/// dead weight. Sharing runs through the same screen but produces a file the
	/// user still needs, and installing Ksign over itself would delete the very
	/// build that is running, so both are left alone.
	private func _cleanUpIfNeeded() {
		guard
			_shouldCleanUpAfterInstall,
			!isSharing,
			app.identifier != Bundle.main.bundleIdentifier
		else {
			return
		}
		
		Storage.shared.cleanUpAfterInstall(for: app)
	}
	
	private func _install() {
        // The manifest is fetched by iOS itself, and only over https. With no
        // certificate to serve it with, `itms-services://` opens nothing at
        // all — no prompt, no error — and this screen sits on `Ready` until
        // it is dismissed, which is what "the install never comes up" was.
        // Say so, and fetch them so the next attempt has them.
        guard
            isSharing
            || _installationMethod == 1
            || _serverMethod == 1
            || ServerInstaller.hasTLSMaterial
        else {
            _repairCertificates()
            return
        }
        
        guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
            UIAlertController.showAlertWithOk(
                title: .localized("Install"),
                message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
            )
            return
        }

		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
                    if await _installationMethod == 0 {
                        await MainActor.run {
                            installer.packageUrl = packageUrl
                            viewModel.status = .ready
                        }
                        
                        if case .installing = await viewModel.status {
                            let task = await startInstallProgressPolling(
                                bundleID: app.identifier!,
                                viewModel: viewModel
                            )

                            await MainActor.run {
                                progressTask = task
                            }
                        }
                    }
                    else if await _installationMethod == 1 {
                        let handler = await InstallationProxy(viewModel: viewModel)
                        try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
                    }
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
                await progressTask?.cancel()
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: error.localizedDescription,
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}
    
    /// Fetches the SSL pack the local server needs, and tells the user the
    /// install has to be asked for again once it is here.
    private func _repairCertificates() {
#if SERVER
        FR.downloadSSLCertificates(from: "https://backloop.dev/pack.json") { success in
            DispatchQueue.main.async {
                UIAlertController.showAlertWithOk(
                    title: .localized("Install"),
                    message: success
                        ? .localized("The install certificates were missing and have been downloaded. Please try installing again.")
                        : .localized("The install certificates are missing and couldn't be downloaded. Check your connection, then try again."),
                    action: { dismiss() }
                )
            }
        }
#else
        UIAlertController.showAlertWithOk(
            title: .localized("Install"),
            message: .localized("The install certificates are missing and couldn't be downloaded. Check your connection, then try again."),
            action: { dismiss() }
        )
#endif
    }
    
    private func startInstallProgressPolling(
            bundleID: String,
            viewModel: InstallerStatusViewModel
        ) -> Task<Void, Never> {

            Task.detached(priority: .background) {
                var hasStarted = false

                while !Task.isCancelled {
                    let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

                    if rawProgress > 0 {
                        hasStarted = true
                    }

                    let progress = await hasStarted
                        ? _normalizeInstallProgress(rawProgress)
                        : 0.0

                    Logger.misc.info("Install progress for \(bundleID): \(progress) - \(rawProgress) - \(viewModel.installProgress)")

                    await MainActor.run {
                        viewModel.installProgress = progress
                    }

                    if hasStarted && rawProgress == 0 {
                        await MainActor.run {
                            viewModel.installProgress = 1.0
                            viewModel.status = .completed(.success(()))
                            print(viewModel.installProgress)
                        }
                        break
                    }

                    try? await Task.sleep(nanoseconds: 1_000_000) // 1 ms
                }
            }
        }

        private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
            min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
        }
}

// MARK: - Probe
/// Reports what the installer's own server handed over during the handshake,
/// and what iOS made of it.
///
/// `itms-services://` never says why it gave up, and a failed handshake from
/// `URLSession` is one flat error code however it failed. The chain the server
/// actually sent, and the reason the system refused it, are the two things
/// that tell those cases apart.
private final class InstallProbeInspector: NSObject, URLSessionDelegate {
	private(set) var chain = "no handshake"
	
	func urlSession(
		_ session: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		guard
			challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
			let trust = challenge.protectionSpace.serverTrust
		else {
			completionHandler(.performDefaultHandling, nil)
			return
		}
		
		let sent = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.count ?? 0
		var error: CFError?
		
		chain = SecTrustEvaluateWithError(trust, &error)
		? "\(sent) sent, trusted"
		: "\(sent) sent — \(error.map { CFErrorCopyDescription($0) as String } ?? "refused")"
		
		completionHandler(.performDefaultHandling, nil)
	}
}
