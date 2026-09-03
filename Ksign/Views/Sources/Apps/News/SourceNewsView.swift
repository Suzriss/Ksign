//
//  SourceNewsView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit

struct SourceNewsView: View {
	@State var isLoading = true
	@State var hasLoadedInitialData = false
	
	var news: [ASRepository.News]?
	var cardWidth: CGFloat = 250
	var cardHeight: CGFloat = 150
	var cornerRadius: CGFloat = 12
	/// The width of the page the strip sits on. A card narrower than it —
	/// the capped one on an iPad — is centred instead of hugging the edge.
	var containerWidth: CGFloat = 0
	
	var body: some View {
		VStack {
			if
				let news,
				!news.isEmpty
			{
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(spacing: 10) {
						ForEach(news.reversed(), id: \.id) { new in
							SourceNewsCardView(
								new: new,
								width: cardWidth,
								height: cardHeight,
								cornerRadius: cornerRadius
							)
						}
					}
					.padding(.horizontal, 21)
					.frame(minWidth: containerWidth > 0 ? containerWidth : nil)
				}
				.frame(height: cardHeight)
				.opacity(isLoading ? 0 : 1)
				.transition(.opacity)
			}
		}
		.frame(height: (news?.isEmpty == false) ? cardHeight : 0)
		.onAppear {
			if !hasLoadedInitialData && news?.isEmpty == false {
				_load()
				hasLoadedInitialData = true
			}
		}
	}
	
	private func _load() {
		withAnimation(.easeIn(duration: 0.3)) {
			isLoading = false
		}
	}
}
