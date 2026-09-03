//
//  CeresifyReviewView.swift
//  Ksign
//
//  The box that asks what the user makes of the app, and what happens to what
//  they write.
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - Sending
/// Hands a rating to Ceresify.
///
/// It lands on `/api/reviews`, which holds it unapproved until the panel says
/// otherwise — so nothing written here appears anywhere on its own. The device
/// is named by its UDID where there is one, which is what lets the server tie
/// the rating to a subscription and refuse a second one from the same account.
enum CeresifyReviewSender {
	/// What the server accepts, so the app can say why before spending a trip.
	static let nameLimit = 40
	static let commentRange = 10...500

	enum Failure: LocalizedError {
		case rejected(String)
		case unreachable

		var errorDescription: String? {
			switch self {
			case .rejected(let message): return message
			case .unreachable:           return .localized("Couldn't reach the server.")
			}
		}
	}

	static func send(name: String, rating: Int, comment: String) async throws {
		var request = URLRequest(url: CeresifyAPI.baseURL.appendingPathComponent("api/reviews"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = 30

		let body: [String: Any] = [
			"displayName": name,
			"rating": rating,
			"comment": comment,
			"udid": CeresifyEnrollmentModel.storedUdid ?? "",
			"appVersion": Bundle.main.version,
			"device": "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
		]

		request.httpBody = try? JSONSerialization.data(withJSONObject: body)

		let data: Data
		let response: URLResponse

		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw Failure.unreachable
		}

		let payload = try? JSONDecoder().decode(_Response.self, from: data)

		guard
			let http = response as? HTTPURLResponse,
			(200..<300).contains(http.statusCode),
			payload?.ok == true
		else {
			throw Failure.rejected(payload?.error ?? .localized("Couldn't send your rating. Try again."))
		}
	}

	private struct _Response: Decodable {
		let ok: Bool?
		let error: String?
	}
}

// MARK: - View
/// The rating box itself, the same one whether it was asked for from Settings
/// or raised over the store on a launch.
///
/// `isDismissable` is what tells the two apart: a box the shop has set to be
/// answered has no way out of it, so it carries neither a close button nor a
/// drag indicator, and the one in Settings has both.
struct CeresifyReviewView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _config = CeresifyConfigManager.shared

	var isDismissable: Bool = true

	@State private var _rating = 0
	@State private var _name = CeresifyEnrollmentModel.storedDeviceName ?? ""
	@State private var _comment = ""
	@State private var _isSending = false
	@State private var _error: String?
	@State private var _didSend = false
	/// Set once a send has actually failed for want of a connection.
	///
	/// A box the shop set to be answered has no way out of it, which is the
	/// point — but a device with no signal can't answer however willing it is,
	/// and an app with no way past that screen is bricked. So the way out
	/// appears only after a real attempt reached nothing, and nothing is
	/// marked as sent: the box is owed again on the next launch.
	@State private var _isUnreachable = false

	private var _review: CeresifyConfig.Review {
		_config.config.review
	}

	private var _trimmedName: String {
		_name.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var _trimmedComment: String {
		_comment.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var _canSend: Bool {
		!_isSending
		&& _rating > 0
		&& !_trimmedName.isEmpty
		&& _trimmedName.count <= CeresifyReviewSender.nameLimit
		&& CeresifyReviewSender.commentRange.contains(_trimmedComment.count)
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(_title, displayMode: .inline) {
			Form {
				Section {
					_stars
				} header: {
					Text(verbatim: _message)
						.font(.subheadline)
						.foregroundStyle(Color.ceresifySubtitle)
						.textCase(nil)
				}

				Section {
					TextField(.localized("Your name"), text: $_name)
						.autocorrectionDisabled()
				} footer: {
					Text(.localized("This is the name shown next to your rating. Nothing else about you is published."))
				}

				Section {
					TextField(_placeholder, text: $_comment, axis: .vertical)
						.lineLimit(4...10)
				} footer: {
					// The server's own floor, said before a trip is spent on
					// finding out — ten characters is a sentence, not a hurdle.
					Text(.localized(
						"At least %lld characters.",
						arguments: CeresifyReviewSender.commentRange.lowerBound
					))
				}

				if let error = _error {
					Section {
						Text(verbatim: error)
							.font(.subheadline)
							.foregroundStyle(.red)
					}
				}
			}
			.disabled(_isSending)
			.safeAreaInset(edge: .bottom) {
				Button {
					Task { await _send() }
				} label: {
					NBSheetButton(title: _isSending ? .localized("Sending") : _buttonText)
				}
				.disabled(!_canSend)
				.padding(.bottom, 4)
			}
			.toolbar {
				if isDismissable || _isUnreachable {
					NBToolbarButton(role: .dismiss)
				}

				if _isSending {
					ToolbarItem(placement: .topBarTrailing) {
						ProgressView()
					}
				}
			}
			.alert(.localized("Thanks!"), isPresented: $_didSend) {
				Button(.localized("OK")) { _dismiss() }
			} message: {
				Text(verbatim: _thanks)
			}
			.animation(.smooth, value: _isSending)
		}
		.interactiveDismissDisabled(!isDismissable)
	}

	// MARK: Wording
	// Every line the box says is the shop's if it wrote one, and the app's
	// translated one otherwise — the same rule the rest of the store follows.

	private var _title: String {
		_config.text(_review.title, fallback: .localized("Rate us"))
	}

	private var _message: String {
		_config.text(_review.message, fallback: .localized("How are you finding the app? Your words reach us directly."))
	}

	private var _placeholder: String {
		_config.text(_review.placeholder, fallback: .localized("Write what you think…"))
	}

	private var _buttonText: String {
		_config.text(_review.buttonText, fallback: .localized("Send"))
	}

	private var _thanks: String {
		_config.text(_review.thanks, fallback: .localized("Your rating reached us."))
	}

	@ViewBuilder
	private var _stars: some View {
		HStack(spacing: 10) {
			Spacer(minLength: 0)

			ForEach(1...5, id: \.self) { star in
				Button {
					UISelectionFeedbackGenerator().selectionChanged()
					_rating = star
				} label: {
					Image(systemName: star <= _rating ? "star.fill" : "star")
						.font(.system(size: 30))
						.foregroundStyle(Color.ceresifyAccent)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel(Text(.localized("%lld stars", arguments: star)))
			}

			Spacer(minLength: 0)
		}
		.padding(.vertical, 6)
		.animation(.smooth(duration: 0.2), value: _rating)
	}

	private func _send() async {
		_isSending = true
		_error = nil
		defer { _isSending = false }

		do {
			try await CeresifyReviewSender.send(
				name: _trimmedName,
				rating: _rating,
				comment: _trimmedComment
			)

			// Marked here rather than on the alert being dismissed: the rating
			// is with the server either way, and the box must not come back on
			// the next launch because somebody swiped the alert away.
			_config.markReviewSent()
			UINotificationFeedbackGenerator().notificationOccurred(.success)
			_didSend = true
		} catch {
			if case CeresifyReviewSender.Failure.unreachable = error {
				_isUnreachable = true
			}
			
			_error = error.localizedDescription
		}
	}
}

// MARK: - Host
/// Raises the box over the app when the shop has asked for it.
///
/// Two shapes, and the shop picks: a sheet that can be put away, or — with
/// `requireAnswer` on — a cover with no way past it, which is the one that
/// means nobody reaches the store without answering. Either way a device that
/// has already sent a rating is never asked again.
struct CeresifyReviewHostModifier: ViewModifier {
	@ObservedObject private var _config = CeresifyConfigManager.shared

	@State private var _isPresenting = false

	private var _isRequired: Bool {
		_config.config.review.requireAnswer
	}

	func body(content: Content) -> some View {
		content
			.sheet(isPresented: Binding(
				get: { _isPresenting && !_isRequired },
				set: { if !$0 { _isPresenting = false } }
			)) {
				CeresifyReviewView()
			}
			.fullScreenCover(isPresented: Binding(
				get: { _isPresenting && _isRequired },
				set: { if !$0 { _isPresenting = false } }
			)) {
				CeresifyReviewView(isDismissable: false)
			}
			// Opened when a config turns the box on. Closing is the box's own
			// job — it dismisses itself once the rating is away, which is the
			// only way out of the version that has to be answered.
			.onChange(of: _config.revision) { _ in _present() }
			.task {
				// The stored config is already in hand, so a box owed to this
				// launch is there from the start rather than after a round trip.
				_present()
			}
	}

	private func _present() {
		guard !_isPresenting, _config.isReviewDue else { return }

		_isPresenting = true
		_config.markReviewShown()
	}
}

extension View {
	/// The rating box, if this launch is owed one.
	func ceresifyReviewPrompt() -> some View {
		modifier(CeresifyReviewHostModifier())
	}
}
