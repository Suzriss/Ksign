//
//  LanguageManager.swift
//  Ksign
//
//  Picking the app's language from inside the app, the way the website's
//  settings page does.
//

import Foundation
import SwiftUI
import ObjectiveC.runtime

/// Swaps the bundle every `NSLocalizedString` lookup goes through, so a language
/// picked in Settings applies without waiting for a relaunch.
///
/// `Bundle.main` is re-classed once, at startup, to a subclass that forwards to
/// the chosen `.lproj`. `AppleLanguages` is written too — it is what the system
/// reads for anything the app doesn't localize itself (share sheets, date
/// formats), which only picks up on the next launch.
final class LanguageManager: ObservableObject {
	static let shared = LanguageManager()
	
	/// Empty means "follow the device", which is what a fresh install does.
	static let systemCode = ""
	
	/// Only the languages this app actually ships strings for.
	static let supported: [String] = ["ar", "en", "cs", "de", "es", "fr", "ru", "tr", "vi"]
	
	private static let _key = "Ceresify.language"
	
	@Published private(set) var code: String
	
	private init() {
		code = UserDefaults.standard.string(forKey: Self._key) ?? Self.systemCode
		_LocalizedBundle.activate()
		_LocalizedBundle.overrideBundle = Self._bundle(for: code)
	}
	
	var layoutDirection: LayoutDirection {
		Self.isRightToLeft(effectiveCode) ? .rightToLeft : .leftToRight
	}
	
	var locale: Locale {
		Locale(identifier: effectiveCode)
	}
	
	/// What the app is actually showing: the picked language, or the best match
	/// the device asked for.
	var effectiveCode: String {
		guard code.isEmpty else { return code }
		
		let preferred = Locale.preferredLanguages.first ?? "en"
		let base = String(preferred.prefix(2))
		return Self.supported.contains(base) ? base : "en"
	}
	
	func select(_ code: String) {
		guard code != self.code else { return }
		
		self.code = code
		_LocalizedBundle.overrideBundle = Self._bundle(for: code)
		
		let defaults = UserDefaults.standard
		
		if code.isEmpty {
			defaults.removeObject(forKey: Self._key)
			defaults.removeObject(forKey: "AppleLanguages")
		} else {
			defaults.set(code, forKey: Self._key)
			defaults.set([code], forKey: "AppleLanguages")
		}
	}
	
	static func isRightToLeft(_ code: String) -> Bool {
		["ar", "fa", "he", "ur"].contains(code)
	}
	
	/// The language's own name, so the list reads the way each language expects
	/// to be called.
	static func displayName(for code: String) -> String {
		guard !code.isEmpty else {
			return .localized("System")
		}
		
		let locale = Locale(identifier: code)
		let name = locale.localizedString(forLanguageCode: code) ?? code
		return name.prefix(1).uppercased() + name.dropFirst()
	}
	
	private static func _bundle(for code: String) -> Bundle? {
		guard
			!code.isEmpty,
			let path = Bundle.main.path(forResource: code, ofType: "lproj")
		else {
			return nil
		}
		
		return Bundle(path: path)
	}
}

// MARK: - Bundle
/// `Bundle.main` re-classed to this: with no override it behaves exactly as it
/// did before, so a device-language install is untouched.
private final class _LocalizedBundle: Bundle {
	nonisolated(unsafe) static var overrideBundle: Bundle?
	
	private nonisolated(unsafe) static var _isActive = false
	
	static func activate() {
		guard !_isActive else { return }
		_isActive = true
		_ = object_setClass(Bundle.main, _LocalizedBundle.self)
	}
	
	override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
		guard let bundle = Self.overrideBundle else {
			return super.localizedString(forKey: key, value: value, table: tableName)
		}
		
		return bundle.localizedString(forKey: key, value: value, table: tableName)
	}
}
