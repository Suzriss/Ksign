//
//  GeneralView.swift
//  Ksign
//
//  The General tab: the same page the web app serves at /app/general.html.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews
import NimbleExtensions
import NukeUI
import UIKit

// MARK: - View
struct GeneralView: View {
    @StateObject private var _viewModel = GeneralViewModel()
    @StateObject private var _sourcesViewModel = SourcesViewModel.shared
    @State private var _selected: GeneralViewModel.Product?
    @State private var _isAddingSource = false
    /// Held rather than deleted on the tap: a source takes a moment to add
    /// back, so the removal is confirmed first.
    @State private var _sourceToDelete: AltSource?
    
    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var _sources: FetchedResults<AltSource>
    
    /// The catalog the store is built on is not something to manage: it ships
    /// with the app and is what the Apps tab already shows. This card is for
    /// the sources added on top of it.
    private var _addedSources: [AltSource] {
        _sources.filter { $0.sourceURL?.host != CeresifyAPI.baseURL.host }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CeresifyCountdownStack(placement: .general)
                    
                    _sourcesCard
                    
                    if _viewModel.products.isEmpty {
                        _placeholder
                    } else {
                        _store
                    }
                }
                // The web page caps its column too, so an iPad doesn't stretch
                // a two-line product card across the whole window.
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle(.localized("General"))
            .refreshable {
                await _viewModel.load(force: true)
            }
            .sheet(item: $_selected) { product in
                GeneralProductDetailView(product: product)
            }
            .confirmationDialog(
                .localized("Delete Source"),
                isPresented: Binding(
                    get: { _sourceToDelete != nil },
                    set: { if !$0 { _sourceToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(.localized("Delete"), role: .destructive) {
                    if let source = _sourceToDelete {
                        Storage.shared.deleteSource(for: source)
                    }
                    
                    _sourceToDelete = nil
                }
                
                Button(.localized("Cancel"), role: .cancel) { _sourceToDelete = nil }
            } message: {
                Text(verbatim: _sourceToDelete?.name ?? "")
            }
            .sheet(isPresented: $_isAddingSource) {
                SourcesAddView()
                    .presentationDetents([.medium])
            }
        }
        .task {
            await _viewModel.load()
        }
        // The store tab primes the shared view model, but General can be the
        // first tab opened — a source row would push an empty list otherwise.
        .task(id: Array(_sources)) {
            await _sourcesViewModel.fetchSources(Array(_sources))
        }
    }
    
    // MARK: Sources
    
    /// Where a second catalog gets added from. The store's toolbar used to
    /// carry this, but the store is one list of apps now — the sources behind
    /// it belong on the page that already holds the account's own settings.
    private var _sourcesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(.localized("Sources"), systemImage: "globe")
                    .font(.headline)
                
                Spacer(minLength: 0)
                
                Button {
                    _isAddingSource = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: String.localized("Add Source")))
            }
            
            if _addedSources.isEmpty {
                Text(.localized("Get started by adding your first repository."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(_addedSources) { source in
                        HStack(spacing: 8) {
                            NavigationLink {
                                SourceAppsView(object: [source], viewModel: _sourcesViewModel)
                            } label: {
                                _sourceRow(for: source)
                            }
                            .buttonStyle(.plain)
                            
                            // A source added by hand has to be removable by
                            // hand — the card is where they are added, so it
                            // is where they come off too. The store's own
                            // catalog is filtered out of this list already, so
                            // there is nothing here to delete by mistake.
                            Button {
                                _sourceToDelete = source
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: String.localized("Delete")))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.quaternarySystemFill))
        )
    }
    
    private func _sourceRow(for source: AltSource) -> some View {
        HStack(spacing: 10) {
            LazyImage(url: source.iconURL) { state in
                if let image = state.image {
                    image.appIconStyle(size: 34)
                } else {
                    Image("Repositories").appIconStyle(size: 34)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: source.name ?? .localized("Unknown"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ceresifyTitle)
                    .lineLimit(1)
                
                Text(verbatim: source.sourceURL?.absoluteString ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.ceresifySubtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
    
    // MARK: Store
    
    private var _store: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(.localized("Products"))
                    .font(.headline)
                
                Spacer(minLength: 0)
                
                Text(verbatim: "\(_viewModel.products.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                spacing: 12
            ) {
                ForEach(_viewModel.products) { product in
                    GeneralProductCardView(product: product) {
                        _selected = product
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var _placeholder: some View {
        if _viewModel.isLoading {
            ProgressView()
                .padding(.top, 50)
        } else {
            VStack(spacing: 10) {
                Image(systemName: _viewModel.didFail ? "wifi.exclamationmark" : "shippingbox")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                
                Text(
                    verbatim: _viewModel.didFail
                    ? String.localized("Couldn't reach the server.")
                    : String.localized("No products yet.")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 50)
        }
    }
}

// MARK: - Card
struct GeneralProductCardView: View {
    let product: GeneralViewModel.Product
    let onOpen: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { _artwork }
                .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                
                if let price = product.price {
                    Text(verbatim: price)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ceresifyAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.quaternarySystemFill))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
    
    @ViewBuilder
    private var _artwork: some View {
        if let url = product.imageURL {
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
    
    private var _placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "tag")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detail
struct GeneralProductDetailView: View {
    let product: GeneralViewModel.Product
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        _icon
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: product.name)
                                .font(.title3.bold())
                            
                            if let price = product.price {
                                Text(verbatim: price)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.ceresifyAccent)
                            }
                        }
                        
                        Spacer(minLength: 0)
                    }
                    
                    if let details = product.details {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(.localized("Description"))
                                .font(.headline)
                            
                            Text(verbatim: details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    if let url = product.orderURL {
                        Button {
                            UIApplication.open(url)
                        } label: {
                            Label(.localized("Order now"), systemImage: "paperplane.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.ceresifyAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle(.localized("Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NBToolbarButton(role: .close)
            }
        }
    }
    
    private var _icon: some View {
        Group {
            if let url = product.imageURL {
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
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    
    private var _placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
        }
    }
}
