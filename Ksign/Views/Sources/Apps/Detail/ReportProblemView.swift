//
//  ReportProblemView.swift
//  Ksign
//
//  Telling Ceresify that an app in the store is broken.
//

import SwiftUI
import AltSourceKit
import NimbleViews
import NimbleExtensions
import UIKit

/// A sheet for saying what is wrong with an app, sent to Ceresify.
///
/// The report goes to `/api/report`, which forwards it — the address it ends up
/// at lives on the server. Putting it in the app would ship it inside every
/// IPA, where anyone could pull it out and write to that account themselves.
///
/// What the app is, which build of it, and which device asked all ride along
/// with the message: a report saying only "it doesn't work" costs a round trip
/// to find out which of a bundle's builds was meant.
struct ReportProblemView: View {
	@Environment(\.dismiss) private var _dismiss
	
	let source: ASRepository
	let app: ASRepository.App
	
	@State private var _message = ""
	@State private var _isSending = false
	@State private var _error: String?
	@State private var _didSend = false
	
	private var _canSend: Bool {
		!_message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !_isSending
	}
	
	var body: some View {
		NBNavigationView(.localized("Report a problem"), displayMode: .inline) {
			Form {
				Section {
					HStack(spacing: 10) {
						Text(verbatim: app.currentName)
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(Color.ceresifyTitle)
						
						Spacer(minLength: 0)
						
						if let version = app.currentVersion, !version.isEmpty {
							Text(verbatim: version)
								.font(.caption)
								.foregroundStyle(Color.ceresifySubtitle)
						}
					}
				} header: {
					Text(.localized("App"))
				}
				
				Section {
					TextField(
						.localized("What went wrong?"),
						text: $_message,
						axis: .vertical
					)
					.lineLimit(4...10)
				} footer: {
					Text(.localized("Tell us what happens — it fails to install, it crashes on opening, the wrong app arrives."))
				}
				
				if let error = _error {
					Section {
						Text(verbatim: error)
							.font(.subheadline)
							.foregroundStyle(.red)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .cancel)
				
				if _isSending {
					ToolbarItem(placement: .confirmationAction) {
						ProgressView()
					}
				} else {
					NBToolbarButton(
						.localized("Send"),
						style: .text,
						placement: .confirmationAction,
						isDisabled: !_canSend
					) {
						Task { await _send() }
					}
				}
			}
			.alert(.localized("Thanks!"), isPresented: $_didSend) {
				Button(.localized("OK")) { _dismiss() }
			} message: {
				Text(.localized("Your report reached us."))
			}
		}
	}
	
	private func _send() async {
		_isSending = true
		_error = nil
		defer { _isSending = false }
		
		var request = URLRequest(url: CeresifyAPI.baseURL.appendingPathComponent("api/report"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = 30
		
		let body: [String: String] = [
			"message": _message.trimmingCharacters(in: .whitespacesAndNewlines),
			"appName": app.currentName,
			"bundleId": app.id ?? "",
			"version": app.currentVersion ?? "",
			"sourceName": source.name ?? "",
			"udid": CeresifyEnrollmentModel.storedUdid ?? "",
			"appVersion": Bundle.main.version,
			"device": "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)",
		]
		
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			let payload = try? JSONDecoder().decode(_Response.self, from: data)
			
			guard
				let http = response as? HTTPURLResponse,
				(200..<300).contains(http.statusCode),
				payload?.ok == true
			else {
				_error = payload?.error ?? .localized("Couldn't send the report. Try again.")
				return
			}
			
			UINotificationFeedbackGenerator().notificationOccurred(.success)
			_didSend = true
		} catch {
			_error = .localized("Couldn't reach the server.")
		}
	}
	
	private struct _Response: Decodable {
		let ok: Bool?
		let error: String?
	}
}
