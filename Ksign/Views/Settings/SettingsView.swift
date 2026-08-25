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

// MARK: - View
struct SettingsView: View {
	/// The accounts the website's settings page links to, in its order.
	/// Computed, so the titles follow a language picked in Preferences.
	private var _accounts: [_Account] {
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
				} footer: {
					Text(.localized("Language and notifications."))
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
				
				Section {
					_developerCredit
						.listRowBackground(EmptyView())
				}
			}
		}
	}
}

// MARK: - Extension: View
private extension SettingsView {
	struct _Account: Identifiable {
		let title: String
		let systemImage: String
		let tint: Color
		/// No link means the account isn't open yet — the website marks it
		/// "soon" rather than hiding it.
		let url: String?
		
		var id: String { title }
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
