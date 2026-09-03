//
//  SourceAppsListHeaderView.swift
//  Ksign
//
//  The banner + category strip that ride above the app list.
//

import SwiftUI
import AltSourceKit

/// Everything that sits between the search field and the first app row, in the
/// order a store reads: the featured banner first, then the category picker.
///
/// It lives inside the table's header rather than above the table so both
/// scroll away with the list instead of pinning the banner to the top.
struct SourceAppsListHeaderView: View {
    let news: [ASRepository.News]?
    let categories: [SourceAppsCategoryStrip.Category]
    /// Width of the table hosting this header, used to size the banner. Taking
    /// it from the table keeps the sizing pass deterministic — a GeometryReader
    /// would measure nothing during `sizeThatFits`.
    let width: CGFloat
    let selection: String?
    let onSelectCategory: (String?) -> Void

    private var _cardWidth: CGFloat {
        max(width - 42, 240)
    }

    /// Banners are drawn 2:1 (the CheckOver artwork is 1200x600), so the card
    /// follows that rather than cropping into it.
    private var _cardHeight: CGFloat {
        min(max(_cardWidth / 2, 140), 260)
    }

    var body: some View {
        VStack(spacing: 0) {
            if
                let news,
                !news.isEmpty
            {
                SourceNewsView(
                    news: news,
                    cardWidth: _cardWidth,
                    cardHeight: _cardHeight,
                    cornerRadius: 20
                )
                .padding(.top, 6)
            }

            if !categories.isEmpty {
                SourceAppsCategoryStrip(
                    categories: categories,
                    selection: Binding(
                        get: { selection },
                        set: { onSelectCategory($0) }
                    )
                )
            }
        }
    }
}
