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
		var id: String { name }
	}
	
	let categories: [Category]
	@Binding var selection: String?
	
	private var _totalCount: Int {
		categories.reduce(0) { $0 + $1.count }
	}
	
	var body: some View {
		ScrollViewReader { proxy in
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					_chip(
						title: .localized("All"),
						count: _totalCount,
						isSelected: selection == nil
					) {
						selection = nil
					}
					.id(_allChipId)
					
					ForEach(categories) { category in
						_chip(
							title: category.name,
							count: category.count,
							isSelected: selection == category.name
						) {
							selection = category.name
						}
						.id(category.name)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 8)
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
	
	@ViewBuilder
	private func _chip(
		title: String,
		count: Int,
		isSelected: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: {
			UISelectionFeedbackGenerator().selectionChanged()
			withAnimation(.snappy(duration: 0.2)) { action() }
		}) {
			HStack(spacing: 5) {
				Text(verbatim: title)
					.font(.subheadline.weight(isSelected ? .semibold : .regular))
				
				Text(verbatim: "\(count)")
					.font(.caption2.weight(.medium))
					.monospacedDigit()
					.opacity(0.7)
			}
			.lineLimit(1)
			.padding(.horizontal, 13)
			.padding(.vertical, 7)
			.foregroundStyle(isSelected ? Color.white : Color.primary)
			.background {
				Capsule(style: .continuous)
					.fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
			}
			.contentShape(Capsule(style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(Text(verbatim: "\(title), \(count)"))
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
}

// MARK: - Extension: build categories from repositories
extension SourceAppsCategoryStrip {
	/// Collects the categories present across the given repositories, ordered by
	/// app count so the big ones (Games, Apps) land first.
	static func categories(from sources: [ASRepository]) -> [Category] {
		var counts: [String: Int] = [:]
		
		for source in sources {
			for app in source.apps {
				guard
					let category = app.category?.trimmingCharacters(in: .whitespacesAndNewlines),
					!category.isEmpty
				else {
					continue
				}
				
				counts[category, default: 0] += 1
			}
		}
		
		return counts
			.map { Category(name: $0.key, count: $0.value) }
			.sorted {
				$0.count != $1.count
				? $0.count > $1.count
				: $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
			}
	}
}
