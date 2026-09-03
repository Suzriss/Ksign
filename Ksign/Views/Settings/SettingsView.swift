//
//  SettingsView.swift
//  Ksign
//
//  The store's settings page, laid out the way the website's is: the device
//  first, then preferences, then the store's own accounts.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import UIKit

// MARK: - View
struct SettingsView: View {
	@ObservedObject private var _config = CeresifyConfigManager.shared
	
	/// The accounts the store links out to.
	///
	/// The panel's list when the shop has filled one in, and the ones the app
	/// shipped with otherwise — so clearing every row restores the original
	/// four rather than leaving an empty section.
	private var _accounts: [_Account] {
		let fromServer = _config.config.accounts
			.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
		
		guard fromServer.isEmpty else {
			return fromServer.map(_Account.init(_:))
		}
		
		return Self._shippedAccounts
	}
	
	/// The website's own settings page, in its order. Titles are computed so
	/// they follow a language picked in Preferences.
	private static var _shippedAccounts: [_Account] {
		[
			_Account(
				title: .localized("Telegram Channel"),
				systemImage: "paperplane.fill",
				tint: Color(red: 0x2A/255, green: 0xAB/255, blue: 0xEE/255),
				url: "https://t.me/ceresify"
			),
			_Account(
				title: .localized("Instagram"),
				systemImage: "camera.fill",
				tint: Color(red: 0xE1/255, green: 0x30/255, blue: 0x6C/255),
				url: "https://instagram.com/ceresify"
			),
			_Account(
				title: .localized("TikTok"),
				systemImage: "music.note",
				tint: Color(white: 0.25),
				url: nil
			),
			_Account(
				title: .localized("Tutorials"),
				systemImage: "play.circle.fill",
				tint: Color(red: 0x50/255, green: 0xC8/255, blue: 0x78/255),
				url: "https://t.me/+Fjm9BFK7TBMwYjhi"
			)
		]
	}
	
	private static let _developerUrl = "https://t.me/uussuu"
	
	@State private var _isReviewPresenting = false
	
	/// Whether the rating row belongs on the page.
	///
	/// Off unless the shop has switched it on, and gone for good once this
	/// device has had its say — the server only takes one rating per account
	/// anyway, so a row that would be refused is a row worth not drawing.
	private var _showsReview: Bool {
		_config.config.review.enabled && !_config.hasSentReview
	}
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				Section {
					NavigationLink(destination: DeviceInfoView()) {
						Label(.localized("Device Information"), systemImage: "iphone.gen3")
					}
				} footer: {
					Text(.localized("Your device's registration, its UDID, and your subscription."))
				}
				
				Section {
					NavigationLink(destination: PreferencesView()) {
						Label(.localized("Preferences"), systemImage: "slider.horizontal.3")
					}
					
					NavigationLink(destination: CeresifyInboxView()) {
						HStack {
							Label(.localized("Notifications"), systemImage: "bell.badge")
							
							Spacer(minLength: 8)
							
							if _config.unreadNotificationCount > 0 {
								Text(verbatim: "\(_config.unreadNotificationCount)")
									.font(.caption.weight(.bold))
									.foregroundStyle(.white)
									.padding(.horizontal, 7)
									.padding(.vertical, 2)
									.background(Color.red, in: Capsule())
							}
						}
					}
				} footer: {
					Text(.localized("Language, and what the store has sent you."))
				}
				
				NBSection(.localized("Store Accounts")) {
					ForEach(_accounts) { account in
						_accountRow(account)
					}
				} footer: {
					Text(.localized("Follow the store to know when apps and subscriptions land."))
				}
				
				Section {
					NavigationLink(destination: AppFeaturesView()) {
						Label(.localized("App Features"), systemImage: "sparkles")
					}
				}
				
				if _showsReview {
					Section {
						Button {
							_isReviewPresenting = true
						} label: {
							Label(.localized("Rate us"), systemImage: "star.bubble")
								.foregroundStyle(.primary)
						}
					} footer: {
						Text(.localized("Tell us what you make of the app — it reaches us straight away."))
					}
				}
				
				Section {
					_developerCredit
						.listRowBackground(EmptyView())
				}
			}
			.sheet(isPresented: $_isReviewPresenting) {
				CeresifyReviewView()
			}
		}
	}
}

// MARK: - Extension: View
private extension SettingsView {
	struct _Account: Identifiable {
		/// The panel's own row id where there is one, and the title otherwise —
		/// two accounts the shop happens to have named the same thing are still
		/// two rows.
		let id: String
		let title: String
		let systemImage: String
		let tint: Color
		/// No link means the account isn't open yet — the website marks it
		/// "soon" rather than hiding it.
		let url: String?
		
		init(title: String, systemImage: String, tint: Color, url: String?) {
			self.id = title
			self.title = title
			self.systemImage = systemImage
			self.tint = tint
			self.url = url
		}
		
		/// A row the shop wrote in the admin panel.
		///
		/// The panel picks from a short list of names rather than typing an SF
		/// Symbol, so a symbol that goes away in a future iOS can't leave a
		/// blank square in the list — and a name nobody recognises still gets
		/// a link icon rather than nothing.
		init(_ account: CeresifyConfig.Account) {
			self.id = account.id
			self.title = account.title
			self.systemImage = Self._symbol(for: account.icon)
			self.tint = Color(uiColor: UIColor(hexString: account.color) ?? UIColor(Self._defaultTint(for: account.icon)))
			self.url = account.url.isEmpty ? nil : account.url
		}
		
		private static func _symbol(for icon: String) -> String {
			switch icon {
			case "telegram":  "paperplane.fill"
			case "instagram": "camera.fill"
			case "tiktok":    "music.note"
			case "youtube":   "play.rectangle.fill"
			case "whatsapp":  "phone.fill"
			case "twitter":   "at"
			case "tutorials": "play.circle.fill"
			case "web":       "globe"
			default:          "link"
			}
		}
		
		private static func _defaultTint(for icon: String) -> Color {
			switch icon {
			case "telegram":  Color(red: 0x2A/255, green: 0xAB/255, blue: 0xEE/255)
			case "instagram": Color(red: 0xE1/255, green: 0x30/255, blue: 0x6C/255)
			case "tiktok":    Color(white: 0.25)
			case "youtube":   Color(red: 0xFF/255, green: 0x00/255, blue: 0x33/255)
			case "whatsapp":  Color(red: 0x25/255, green: 0xD3/255, blue: 0x66/255)
			case "twitter":   Color(white: 0.16)
			case "tutorials": Color(red: 0x50/255, green: 0xC8/255, blue: 0x78/255)
			default:          Color.ceresifyAccent
			}
		}
	}
	
	@ViewBuilder
	func _accountRow(_ account: _Account) -> some View {
		Button {
			if let url = account.url {
				UIApplication.open(url)
			}
		} label: {
			HStack(spacing: 12) {
				Image(systemName: account.systemImage)
					.font(.system(size: 15))
					.foregroundStyle(.white)
					.frame(width: 29, height: 29)
					.background(account.tint)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				
				Text(verbatim: account.title)
				
				Spacer(minLength: 8)
				
				if account.url == nil {
					Text(.localized("Soon"))
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background(Color(uiColor: .quaternarySystemFill))
						.clipShape(Capsule())
				} else {
					Image(systemName: "chevron.right")
						.font(.caption.bold())
						.foregroundStyle(.secondary)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(account.url == nil)
	}
	
	/// Last thing on the page, the way the website closes its settings page.
	var _developerCredit: some View {
		Button {
			UIApplication.open(Self._developerUrl)
		} label: {
			VStack(spacing: 4) {
				Text(verbatim: "تصميم وبرمجة أيمن الناصري")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(Color.ceresifyGold)
				
				Text(verbatim: "Design & development by Ayman Al-Nasiri")
					.font(.caption)
					.foregroundStyle(.secondary)
				
				HStack(spacing: 4) {
					Image(systemName: "paperplane.fill")
					Text(verbatim: "@uussuu")
				}
				.font(.caption.weight(.medium))
				.foregroundStyle(Color.ceresifyGold)
				.padding(.top, 2)
			}
			.multilineTextAlignment(.center)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 10)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
