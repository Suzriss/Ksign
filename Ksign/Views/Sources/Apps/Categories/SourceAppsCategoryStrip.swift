//
//  SourceAppsCategoryStrip.swift
//  Ksign
//
//  Horizontal category picker sitting above the app list.
//

import SwiftUI
import UIKit
import AltSourceKit

// MARK: - View
struct SourceAppsCategoryStrip: View {
	/// Category name paired with how many apps carry it, so the strip can lead
	/// with the categories that actually have content.
	struct Category: Identifiable, Hashable {
		let name: String
		let count: Int
		/// The shop's thumbnail for it, and the emoji it falls back to.
		var imageURL: URL?
		var icon: String?
		/// A short line the shop attached to the category — shown as a label
		/// on the chip.
		var note: String?
		var id: String { name }
	}
	
	let categories: [Category]
	@Binding var selection: String?
	
	var body: some View {
		ScrollViewReader { proxy in
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					_chip(
						title: .localized("All"),
						isSelected: selection == nil
					) {
						selection = nil
					}
					.id(_allChipId)
					
					ForEach(categories) { category in
						// The chip reads in the app's language; the raw name
						// stays the identity the list filters on.
						_chip(
							title: SourceAppCategoryName.localized(category.name),
							category: category,
							isSelected: selection == category.name
						) {
							selection = category.name
						}
						.id(category.name)
					}
				}
				.padding(.horizontal, 21)
				.padding(.vertical, 10)
			}
			.onChange(of: selection) { newValue in
				// Keep the active chip on screen when the selection is changed
				// from somewhere other than a tap (restoring the stored filter).
				withAnimation(.snappy) {
					proxy.scrollTo(newValue ?? _allChipId, anchor: .center)
				}
			}
		}
	}
	
	private let _allChipId = "__all__"
	
	/// The thumbnail is drawn at a fixed size beside the name, so a category
	/// that has one reads the same as one that doesn't — the art sits in front
	/// of the label rather than pushing it around or shrinking it.
	private let _thumbnailSize: CGFloat = 22
	
	@ViewBuilder
	private func _chip(
		title: String,
		category: Category? = nil,
		isSelected: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: {
			UISelectionFeedbackGenerator().selectionChanged()
			withAnimation(.snappy(duration: 0.2)) { action() }
		}) {
			HStack(spacing: 7) {
				if let category, category.imageURL != nil || category.icon != nil {
					CeresifyThumbnailView(
						url: category.imageURL,
						size: _thumbnailSize,
						placeholder: category.icon
					)
				}
				
				Text(verbatim: title)
					.font(.subheadline.weight(.semibold))
					.lineLimit(1)
				
				if
					let note = category?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
					!note.isEmpty
				{
					_noteLabel(note, isSelected: isSelected)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 9)
			// The selected chip inverts against the page, so it reads the
			// same way in light and dark without leaning on a tint.
			.foregroundStyle(isSelected ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(Color.primary))
			.background {
				Capsule(style: .continuous)
					.fill(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary))
			}
			.contentShape(Capsule(style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(Text(verbatim: _accessibilityLabel(title, category: category)))
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
	
	@ViewBuilder
	private func _noteLabel(_ note: String, isSelected: Bool) -> some View {
		Text(verbatim: note)
			.font(.caption2.weight(.bold))
			.lineLimit(1)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.ceresifyGold))
			.background {
				Capsule(style: .continuous)
					.fill(
						isSelected
						? AnyShapeStyle(Color(uiColor: .systemBackground).opacity(0.9))
						: AnyShapeStyle(Color.ceresifyGold.opacity(0.16))
					)
			}
	}
	
	private func _accessibilityLabel(_ title: String, category: Category?) -> String {
		guard
			let note = category?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
			!note.isEmpty
		else {
			return title
		}
		
		return "\(title) — \(note)"
	}
}

// MARK: - Extension: build categories from repositories
extension SourceAppsCategoryStrip {
	/// Collects the categories present across the given repositories, in the
	/// order the source lists them.
	///
	/// A source hands its apps over already ordered — Ceresify's catalog is
	/// emitted category by category, in the order set in the admin panel — so
	/// following first appearance is what lets the shop decide which chips lead.
	/// Sorting by app count here would overrule that.
	///
	/// A source that also describes its categories (thumbnail, note) has that
	/// merged in by name; one that doesn't gets plain chips, exactly as before.
	static func categories(from sources: [ASRepository]) -> [Category] {
		var counts: [String: Int] = [:]
		var order: [String] = []
		var metadata: [String: ASRepository.Category] = [:]
		
		for source in sources {
			for category in source.categories ?? [] where !category.name.isEmpty {
				metadata[category.name] = category
			}
			
			for app in source.apps {
				guard
					let category = app.category?.trimmingCharacters(in: .whitespacesAndNewlines),
					!category.isEmpty
				else {
					continue
				}
				
				if counts[category] == nil {
					order.append(category)
				}
				
				counts[category, default: 0] += 1
			}
		}
		
		return order.map { name in
			Category(
				name: name,
				count: counts[name] ?? 0,
				imageURL: metadata[name]?.imageURL,
				icon: metadata[name]?.icon,
				note: metadata[name]?.note
			)
		}
	}
}
