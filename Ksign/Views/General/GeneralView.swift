//
//  GeneralView.swift
//  Ksign
//
//  The General tab: the same page the web app serves at /app/general.html.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import NukeUI
import UIKit

// MARK: - View
struct GeneralView: View {
    @StateObject private var _viewModel = GeneralViewModel()
    @State private var _selected: GeneralViewModel.Product?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    _deviceCard
                    
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
        }
        .task {
            await _viewModel.load()
        }
    }
    
    // MARK: Device
    
    private var _deviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(.localized("Your device"), systemImage: "iphone")
                    .font(.headline)
                
                Spacer(minLength: 0)
                
                _statusPill
            }
            
            if let device = _viewModel.device {
                VStack(spacing: 8) {
                    _row(.localized("Device"), value: device.name ?? .localized("Unknown"))
                    _row(.localized("UDID"), value: Self._shorten(device.udid)) {
                        UIPasteboard.general.string = device.udid
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    _row(.localized("Subscription"), value: Self._subscriptionText(for: device))
                }
            } else {
                Text(.localized("This device isn't registered yet. Register it to get a certificate and a subscription."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.quaternarySystemFill))
        )
    }
    
    private var _statusPill: some View {
        let isSubscribed = _viewModel.device?.isSubscribed ?? false
        let isRegistered = _viewModel.device != nil
        
        let title: String = isSubscribed
        ? .localized("Active")
        : (isRegistered ? .localized("Not subscribed") : .localized("Not registered"))
        
        return HStack(spacing: 6) {
            Circle()
                .fill(isSubscribed ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            
            Text(verbatim: title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSubscribed ? Color.green : Color.secondary)
        }
    }
    
    @ViewBuilder
    private func _row(_ title: String, value: String, onTap: (() -> Void)? = nil) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 12)
            
            Text(verbatim: value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            
            if onTap != nil {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
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
    
    // MARK: Formatting
    
    private static func _shorten(_ udid: String) -> String {
        guard udid.count > 16 else { return udid }
        return "\(udid.prefix(10))…\(udid.suffix(6))"
    }
    
    private static func _subscriptionText(for device: GeneralViewModel.Device) -> String {
        guard device.isSubscribed else {
            return .localized("Not subscribed")
        }
        
        guard let expiry = device.expiry else {
            return .localized("Active")
        }
        
        return .localized("Expires %@", arguments: expiry.formatted(date: .abbreviated, time: .omitted))
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
                        .foregroundStyle(Color.accentColor)
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
                                    .foregroundStyle(Color.accentColor)
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
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
