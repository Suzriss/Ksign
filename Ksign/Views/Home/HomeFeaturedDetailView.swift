//
//  HomeFeaturedDetailView.swift
//  Ksign
//
//  What the web app's featured sheet shows, as a sheet.
//

import SwiftUI
import NimbleViews

struct HomeFeaturedDetailView: View {
    let item: HomeFeaturedViewModel.Item
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    _header
                    _stats
                    
                    if let details = item.details {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(.localized("About this app"))
                                .font(.headline)
                            
                            Text(verbatim: details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
    
    private var _header: some View {
        HStack(spacing: 14) {
            HomeFeaturedIconView(url: item.iconURL, size: 62)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name)
                    .font(.title3.bold())
                
                if let subtitle = item.subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            if let app = item.app {
                DownloadButtonView(app: app)
            }
        }
    }
    
    private var _stats: some View {
        HStack(spacing: 0) {
            _stat(value: item.version.map { "v\($0)" }, label: .localized("Version"))
            _stat(value: _formattedSize, label: .localized("Size"))
            _stat(value: _formattedDate, label: .localized("Last updated"))
        }
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func _stat(value: String?, label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value ?? "—")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(verbatim: label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var _formattedSize: String? {
        guard
            let size = item.size,
            size > 0
        else {
            return nil
        }
        
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private var _formattedDate: String? {
        guard let date = item.date else { return nil }
        
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
