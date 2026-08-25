//
//  SignerView.swift
//  Ksign
//
//  The Signer tab: bring an IPA in from a link or a file, then sign it here.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import NimbleViews
import UIKit

/// Two ways in — a link or a file — and everything that came in already,
/// waiting to be signed.
///
/// Nothing is uploaded anywhere: a link is downloaded onto the device and both
/// paths end in the same local signer the library uses, so signing works with
/// whatever certificate is installed, offline included.
struct SignerView: View {
    @StateObject private var downloadManager = IPADownloadManager()
    @StateObject private var libraryManager = DownloadManager.shared
    
    @State private var webViewURL: URL?
    @State private var shareItems: [Any] = []
    @State private var showDocumentPicker = false
    @State private var fileToExport: URL?
    @State private var _isImportingPresenting = false
    @State private var _searchText = ""
    
    @State private var _signingApp: AnyApp?
    @State private var _installingApp: AnyApp?
    
    /// Set the moment a link or a file is handed over, so the app that lands
    /// after it can be taken straight to the signing options.
    @State private var _awaitingImportSince: Date?
    
    @FetchRequest(
        entity: Imported.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
        animation: .snappy
    ) private var _importedApps: FetchedResults<Imported>
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    private var _filteredImported: [Imported] {
        _importedApps.filter {
            _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false)
        }
    }
    
    private var _filteredSigned: [Signed] {
        _signedApps.filter {
            _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false)
        }
    }
    
    private var _filteredDownloadItems: [DownloadItem] {
        downloadManager.finishedItems.filter {
            _searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(_searchText)
        }
    }
    
    private var _isWorking: Bool {
        !libraryManager.downloads.isEmpty || !downloadManager.activeItems.isEmpty
    }
    
    private var _isEmpty: Bool {
        _importedApps.isEmpty
        && _signedApps.isEmpty
        && downloadManager.finishedItems.isEmpty
        && !_isWorking
    }
    
    // MARK: Body
    var body: some View {
        NBNavigationView(.localized("Signer")) {
            List {
                Section {
                    SignerSourceButtonsView(
                        onLink: { _addFromLink() },
                        onFile: { _isImportingPresenting = true }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                
                if _isWorking {
                    NBSection(
                        .localized("Downloading"),
                        secondary: (libraryManager.downloads.count + downloadManager.activeItems.count).description
                    ) {
                        ForEach(libraryManager.downloads) { download in
                            AppStoreDownloadItemRow(download: download)
                        }
                        ForEach(downloadManager.activeItems) { item in
                            DownloadItemRow(
                                item: item,
                                shareItems: $shareItems,
                                importIpaToLibrary: { item in importIpaToLibrary(item) },
                                exportToFiles: { item in exportToFiles(item) },
                                deleteItem: { item in deleteItem(item) }
                            )
                        }
                    }
                }
                
                if !_filteredImported.isEmpty {
                    NBSection(.localized("Ready to sign"), secondary: _filteredImported.count.description) {
                        ForEach(_filteredImported, id: \.uuid) { app in
                            SignerAppRowView(
                                app: app,
                                actionTitle: .localized("Sign"),
                                action: { _signingApp = AnyApp(base: app) }
                            )
                        }
                    }
                }
                
                if !_filteredSigned.isEmpty {
                    NBSection(.localized("Signed"), secondary: _filteredSigned.count.description) {
                        ForEach(_filteredSigned, id: \.uuid) { app in
                            SignerAppRowView(
                                app: app,
                                actionTitle: .localized("Install"),
                                action: { _installingApp = AnyApp(base: app) }
                            )
                        }
                    }
                }
                
                if !_filteredDownloadItems.isEmpty {
                    NBSection(.localized("Downloaded"), secondary: _filteredDownloadItems.count.description) {
                        ForEach(_filteredDownloadItems) { item in
                            DownloadItemRow(
                                item: item,
                                shareItems: $shareItems,
                                importIpaToLibrary: { item in importIpaToLibrary(item) },
                                exportToFiles: { item in exportToFiles(item) },
                                deleteItem: { item in deleteItem(item) }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if _isEmpty {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("Nothing to sign yet"), systemImage: "signature")
                        } description: {
                            Text(.localized("Add an IPA from a link or from your files, and sign it right here."))
                        }
                    }
                }
            }
            .searchable(text: $_searchText, placement: .platform())
            .onChange(of: libraryManager.downloads.count) { _ in
                downloadManager.loadDownloadedIPAs()
            }
            .onChange(of: downloadManager.activeItems.count) { _ in
                downloadManager.loadDownloadedIPAs()
            }
            .onChange(of: _importedApps.count) { _ in
                _presentSigningForNewImportIfNeeded()
            }
            .fullScreenCover(item: $webViewURL) { url in
                webViewSheet(url: url)
            }
            .fullScreenCover(item: $_signingApp) { app in
                SigningView(app: app.base)
            }
            .sheet(item: $_installingApp) { app in
                InstallPreviewView(app: app.base)
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDocumentPicker) {
                documentPickerSheet
            }
            .sheet(isPresented: $_isImportingPresenting) {
                importerSheet
            }
        }
    }
}

// MARK: - Sheet Content
private extension SignerView {
    func webViewSheet(url: URL) -> some View {
        WebViewSheet(
            downloadManager: downloadManager,
            url: url,
        )
    }
    
    @ViewBuilder
    var documentPickerSheet: some View {
        if let fileURL = fileToExport {
            FileExporterRepresentableView(
                urlsToExport: [fileURL],
                asCopy: true,
                useLastLocation: false,
                onCompletion: { _ in
                    showDocumentPicker = false
                }
            )
        }
    }
    
    var importerSheet: some View {
        FileImporterRepresentableView(
            allowedContentTypes: [.ipa, .tipa],
            allowsMultipleSelection: true,
            onDocumentsPicked: { urls in
                guard !urls.isEmpty else { return }
                _addFromFiles(urls)
            }
        )
    }
}

// MARK: - Action Handlers
private extension SignerView {
    /// Brings in an IPA the user picked from Files, then hands it to the signer.
    func _addFromFiles(_ urls: [URL]) {
        _awaitingImportSince = Date()
        
        for ipa in urls {
            let id = "FeatherManualDownload_\(UUID().uuidString)"
            let download = libraryManager.startArchive(from: ipa, id: id)
            
            libraryManager.handlePachageFile(url: ipa, dl: download) { err in
                if err != nil {
                    _awaitingImportSince = nil
                    UIAlertController.showAlertWithOk(
                        title: .localized("Error"),
                        message: .localized("Whoops!, something went wrong when extracting the file. \nMaybe try switching the extraction library in the settings?")
                    )
                }
            }
        }
    }
    
    func _addFromLink() {
        UIAlertController.showAlertWithTextBox(
            title: .localized("Sign from a link"),
            message: .localized("""
Paste a link to an IPA, or to a page that holds one. It's downloaded onto this device and signed here — nothing is uploaded anywhere.
- https://example.com/app.ipa
- itms-services://?url=https://example.com
- https://example.com
"""),
            textFieldPlaceholder: .localized("https://example.com/app.ipa"),
            submit: .localized("OK"),
            cancel: .localized("Cancel"),
            onSubmit: { url in
                handleURLInput(url: url)
            }
        )
    }

    func handleURLInput(url: String) {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var finalUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalUrl.lowercased().hasPrefix("http://") && !finalUrl.lowercased().hasPrefix("https://") {
            finalUrl = "https://" + finalUrl
        }
        
        guard let validUrl = URL(string: finalUrl) else {
            UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Invalid URL format"))
            return
        }
        
        // A direct IPA goes to the library the short way: downloaded, unpacked,
        // and opened in the signer. Anything else is a page to find one on.
        if downloadManager.isIPAFile(validUrl) {
            _awaitingImportSince = Date()
            _ = libraryManager.startDownload(
                from: validUrl,
                id: "FeatherManualDownload_\(UUID().uuidString)"
            )
        } else {
            webViewURL = validUrl
        }
    }
    
    /// The download and the unpacking both finish out of sight, so the signer
    /// is opened from the app that lands rather than from the tap that asked
    /// for it.
    func _presentSigningForNewImportIfNeeded() {
        guard
            let since = _awaitingImportSince,
            let newest = _importedApps.first,
            let date = newest.date,
            date >= since.addingTimeInterval(-1)
        else {
            return
        }
        
        _awaitingImportSince = nil
        _signingApp = AnyApp(base: newest)
    }
    
    func importIpaToLibrary(_ file: DownloadItem) {
        _awaitingImportSince = Date()
        
        let id = "FeatherManualDownload_\(UUID().uuidString)"
        let download = libraryManager.startArchive(from: file.url, id: id)
        libraryManager.handlePachageFile(url: file.url, dl: download) { err in
            DispatchQueue.main.async {
                if err != nil {
                    _awaitingImportSince = nil
                    UIAlertController.showAlertWithOk(
                        title: .localized("Error"),
                        message: .localized("Whoops!, something went wrong when extracting the file. \nMaybe try switching the extraction library in the settings?")
                    )
                }
                if let index = libraryManager.getDownloadIndex(by: download.id) {
                    libraryManager.downloads.remove(at: index)
                }
            }
        }
    }
    
    func exportToFiles(_ item: DownloadItem) {
        fileToExport = item.localPath
        showDocumentPicker = true
    }
    
    func deleteItem(_ item: DownloadItem) {
        if !item.isFinished {
            downloadManager.cancelDownload(item)
            return
        }
        
        do {
            try FileManager.default.removeItem(at: item.localPath)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if let index = downloadManager.downloadItems.firstIndex(where: { $0.id == item.id }) {
                    downloadManager.downloadItems.remove(at: index)
                }
            }
        } catch {
            UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
        }
    }
}

// MARK: - Source buttons
struct SignerSourceButtonsView: View {
    let onLink: () -> Void
    let onFile: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            _card(
                title: .localized("From a link"),
                subtitle: .localized("Paste an IPA URL"),
                systemImage: "link",
                action: onLink
            )
            
            _card(
                title: .localized("From a file"),
                subtitle: .localized("Pick an IPA on this device"),
                systemImage: "folder",
                action: onFile
            )
        }
    }
    
    private func _card(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .quaternarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App row
struct SignerAppRowView: View {
    let app: AppInfoPresentable
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            FRAppIconView(app: app, size: 44)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: app.name ?? .localized("Unknown"))
                    .font(.body)
                    .lineLimit(1)
                
                Text(verbatim: [app.version, app.identifier].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            Button(action: action) {
                Text(verbatim: actionTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .quaternarySystemFill))
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
