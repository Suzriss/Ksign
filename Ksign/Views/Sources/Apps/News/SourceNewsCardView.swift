//
//  SourceNewsCardView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit
import NimbleExtensions
import NukeUI

struct SourceNewsCardView: View {
	var new: ASRepository.News
	var width: CGFloat = 250
	var height: CGFloat = 150
	var cornerRadius: CGFloat = 12
	
	var body: some View {
		Group {
			if let url = new.url {
				Button {
					UIApplication.open(url)
				} label: {
					_card
				}
				.buttonStyle(.plain)
			} else {
				_card
			}
		}
	}
	
	private var _card: some View {
		ZStack(alignment: .bottomLeading) {
			let placeholderView = {
				Color.gray.opacity(0.2)
			}()
			
			if let iconURL = new.imageURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image
							.resizable()
							.aspectRatio(contentMode: .fill)
							.frame(width: width, height: height)
							.clipped()
					} else {
						placeholderView
					}
				}
			} else {
				placeholderView
			}
			
			LinearGradient(
				gradient: Gradient(colors: [.black.opacity(0.6), .clear]),
				startPoint: .bottom,
				endPoint: .top
			)
			.frame(height: 70)
			.frame(maxWidth: .infinity, alignment: .bottom)
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
			
			Text(new.title)
				.font(.headline)
				.foregroundColor(.white)
				.lineLimit(2)
				.padding()
		}
		.frame(width: width, height: height)
		.background(new.tintColor ?? Color.secondary)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
		)
	}
}

