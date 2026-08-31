//
//  HomeView.swift
//  Ksign
//
//  The Home tab: the featured apps the web app's main page shows.
//

import SwiftUI
import NimbleViews
import NukeUI

// MARK: - View
struct HomeView: View {
    @StateObject private var _viewModel = HomeFeaturedViewModel()
    @State private var _selected: HomeFeaturedViewModel.Item?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // The shop's own mark and whatever it is counting down to,
                    // above the featured cards.
                    CeresifyStoreLogoView()
                    CeresifyCountdownStack(placement: .home)
                    
                    if _viewModel.items.isEmpty {
                        _placeholder
                    } else {
                        ForEach(_viewModel.items) { item in
                            HomeFeaturedCardView(item: item) {
                                _selected = item
                            }
                        }
                    }
                }
                // The web page caps the column too — a card stretched across an
                // iPad turns the artwork into a letterbox.
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle(.localized("Home"))
            .refreshable {
                await _viewModel.load(force: true)
            }
            .sheet(item: $_selected) { item in
                HomeFeaturedDetailView(item: item)
            }
        }
        .task {
            await _viewModel.load()
        }
    }
    
    @ViewBuilder
    private var _placeholder: some View {
        if _viewModel.isLoading {
            ProgressView()
                .padding(.top, 60)
        } else {
            VStack(spacing: 10) {
                Image(systemName: _viewModel.didFail ? "wifi.exclamationmark" : "star")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                
                Text(
                    verbatim: _viewModel.didFail
                    ? String.localized("Couldn't reach the server.")
                    : String.localized("Nothing featured yet.")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
        }
    }
}

// MARK: - Card
struct HomeFeaturedCardView: View {
    let item: HomeFeaturedViewModel.Item
    let onOpen: () -> Void
    
    private let _cornerRadius: CGFloat = 26
    
    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .overlay { _artwork }
            .overlay { _shade }
            .overlay(alignment: .topLeading) { _unavailableBadge }
            .overlay(alignment: .bottom) { _bottomBar }
            .clipShape(RoundedRectangle(cornerRadius: _cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: _cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: _cornerRadius, style: .continuous))
            .onTapGesture(perform: onOpen)
    }
    
    @ViewBuilder
    private var _artwork: some View {
        if let imageURL = item.imageURL {
            LazyImage(url: imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
        } else {
            Color.gray.opacity(0.2)
        }
    }
    
    private var _shade: some View {
        LinearGradient(
            colors: [.black.opacity(0.72), .black.opacity(0.34), .clear],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    @ViewBuilder
    private var _unavailableBadge: some View {
        if !item.isAvailable {
            Text(.localized("Unavailable"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
    }
    
    private var _bottomBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let app = item.app {
                VStack(spacing: 5) {
                    DownloadButtonView(app: app, cloudSource: item.cloudSource)
                    
                    if let note = item.note {
                        Text(verbatim: note)
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            HStack(spacing: 11) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: item.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if let subtitle = item.subtitle {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                
                HomeFeaturedIconView(url: item.iconURL, size: 58)
            }
        }
        .padding(16)
    }
}

// MARK: - Icon
struct HomeFeaturedIconView: View {
    let url: URL?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        _placeholder
                    }
                }
            } else {
                _placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2337, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2337, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
    
    private var _placeholder: some View {
        Image("App_Unknown")
            .resizable()
            .scaledToFill()
    }
}
