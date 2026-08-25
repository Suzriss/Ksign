//
//  PreferencesView.swift
//  Ksign
//
//  Language and notifications, the two preferences the website's settings
//  page keeps.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import UserNotifications
import UIKit

// MARK: - View
struct PreferencesView: View {
	@StateObject private var _language = LanguageManager.shared
	@StateObject private var _options = OptionsManager.shared
	
	@State private var _isAuthorized = true
	
	var body: some View {
		NBList(.localized("Preferences")) {
			NBSection(.localized("Language")) {
				_languageRow(LanguageManager.systemCode)
				
				ForEach(LanguageManager.supported, id: \.self) { code in
					_languageRow(code)
				}
			} footer: {
				Text(.localized("Some parts of the app only pick up a new language after it is reopened."))
			}
			
			NBSection(.localized("Notifications")) {
				Toggle(isOn: $_options.options.notifications) {
					Label(.localized("Notify when download is completed"), systemImage: "bell")
				}
				.onChange(of: _options.options.notifications) { enabled in
					_options.saveOptions()
					_requestAuthorizationIfNeeded(enabled)
				}
				
				if !_isAuthorized {
					Button {
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					} label: {
						Label(.localized("Open Settings"), systemImage: "gear")
					}
				}
			} footer: {
				Text(
					_isAuthorized
					? .localized("This will notify you when the download is completed.")
					: .localized("Notifications are turned off for this app in iOS Settings.")
				)
			}
		}
		.task {
			await _refreshAuthorization()
		}
	}
	
	// MARK: Language
	
	@ViewBuilder
	private func _languageRow(_ code: String) -> some View {
		Button {
			_language.select(code)
		} label: {
			HStack {
				Text(verbatim: LanguageManager.displayName(for: code))
				
				Spacer(minLength: 12)
				
				if _language.code == code {
					Image(systemName: "checkmark")
						.font(.headline)
						.foregroundStyle(Color.ceresifyGold)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
	
	// MARK: Notifications
	
	private func _refreshAuthorization() async {
		let settings = await UNUserNotificationCenter.current().notificationSettings()
		_isAuthorized = settings.authorizationStatus != .denied
	}
	
	/// Turning the toggle on is the ask for permission; a device that already
	/// said no keeps it off and is pointed at iOS Settings instead.
	private func _requestAuthorizationIfNeeded(_ enabled: Bool) {
		guard enabled else { return }
		
		Task {
			let center = UNUserNotificationCenter.current()
			let settings = await center.notificationSettings()
			
			switch settings.authorizationStatus {
			case .notDetermined:
				let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
				
				if !granted {
					_options.options.notifications = false
					_options.saveOptions()
				}
				
				_isAuthorized = granted
			case .denied:
				_options.options.notifications = false
				_options.saveOptions()
				_isAuthorized = false
			default:
				_isAuthorized = true
			}
		}
	}
}
