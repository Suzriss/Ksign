//
//  SourceAppCategoryName.swift
//  Ksign
//
//  Turning a source's own category name into the language the app is set to.
//

import Foundation
import NimbleExtensions

/// A source hands out one category name per app, in whatever language the
/// catalog was written in — CheckOver's are English. The picker has to follow
/// the language chosen in Preferences, so the raw name is matched against a
/// table of the categories stores actually use and looked up in the app's own
/// strings.
///
/// The raw name stays the identity: it is what the app list filters on, so a
/// translation never changes which apps a chip selects — only what the chip
/// reads. A name that isn't in the table is a store's own custom category,
/// already written in that shop's language, and is shown as it came.
enum SourceAppCategoryName {
	/// The localized name to show for a source's category.
	static func localized(_ raw: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		
		guard
			!trimmed.isEmpty,
			let key = _keys[trimmed.lowercased()]
		else {
			return trimmed
		}
		
		return .localized(key)
	}
	
	/// Lowercased source name → the string it is filed under. The keys are the
	/// English names themselves, so a language with no translation for one falls
	/// back to English rather than to a missing-string placeholder.
	private static let _keys: [String: String] = [
		// CheckOver's catalog, the source the app ships with.
		"games": "Games",
		"apps": "Apps",
		"paid applications": "Paid applications",
		"paid games": "Paid Games",
		"design applications": "Design applications",
		"artificial intelligence applications": "Artificial Intelligence Applications",
		"sports applications": "Sports applications",
		"movies and tv shows": "Movies and TV shows",
		"medical applications": "Medical applications",
		"arcade games": "Arcade Games",
		"islamic applications": "Islamic applications",
		"social media": "Social Media",
		"jailbreak applications": "Jailbreak applications",
		"testflight apps": "TestFlight apps",
		// What AltStore-shaped sources commonly use.
		"utilities": "Utilities",
		"entertainment": "Entertainment",
		"productivity": "Productivity",
		"photo & video": "Photo & Video",
		"music": "Music",
		"education": "Education",
		"news": "News",
		"emulators": "Emulators",
		"tools": "Tools",
		"other": "Other",
	]
}
