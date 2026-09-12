//
//  SigningTweakPresetsViewModel.swift
//  Ksign
//
//  Ready-made tweaks the shop has placed for everyone, alongside whatever the
//  user imports themselves in the same "Tweaks" screen.
//

import Foundation
import Zip

/// One ready-made tweak the panel has uploaded — a `.dylib`, a `.deb`, or a
/// `.zip` holding a `.framework`/`.bundle`.
struct TweakPreset: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let fileName: String
    let size: Int64?
    let url: URL

    enum CodingKeys: String, CodingKey {
        case id, name, fileName, size, url
    }
}

@MainActor
final class SigningTweakPresetsViewModel: ObservableObject {
    @Published private(set) var presets: [TweakPreset] = []
    @Published private(set) var isLoading = false
    /// The preset currently being fetched, so its row can show a spinner
    /// instead of the whole list blocking on one download.
    @Published private(set) var downloadingId: String?

    private var _hasLoaded = false

    func load() async {
        guard !_hasLoaded else { return }
        _hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        do {
            let url = CeresifyAPI.baseURL.appendingPathComponent("api/sign/tweak-presets")
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            presets = try JSONDecoder().decode(_Response.self, from: data).presets
        } catch {
            // Empty on failure — the screen just shows the user's own tweaks.
            _hasLoaded = false
        }
    }

    /// Downloads the preset into the app's Tweaks directory, unzipping it
    /// first if it's a `.zip`, and hands back the file(s) to add to the
    /// signing options — same shape `_importTweaks` produces for a locally
    /// picked file.
    func download(_ preset: TweakPreset) async throws -> [URL] {
        downloadingId = preset.id
        defer { downloadingId = nil }

        let tweaksDir = FileManager.default.tweaks
        try FileManager.default.createDirectoryIfNeeded(at: tweaksDir)

        let (tempURL, _) = try await URLSession.shared.download(from: preset.url)

        let ext = (preset.fileName as NSString).pathExtension.lowercased()
        guard ext == "zip" else {
            let destination = tweaksDir.appendingPathComponent(preset.fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            return [destination]
        }

        // A zip stands in for a framework/bundle, which can't travel as a
        // single file — unpack it into its own folder under Tweaks and hand
        // back whatever .framework/.bundle/.dylib sits at its root.
        let baseName = (preset.fileName as NSString).deletingPathExtension
        let extractedRoot = tweaksDir.appendingPathComponent(baseName)
        try? FileManager.default.removeItem(at: extractedRoot)
        try FileManager.default.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try Zip.unzipFile(tempURL, destination: extractedRoot, overwrite: true, password: nil)

        let items = (try? FileManager.default.contentsOfDirectory(
            at: extractedRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        let wanted = items.filter { ["framework", "bundle", "dylib"].contains($0.pathExtension.lowercased()) }
        return wanted.isEmpty ? [extractedRoot] : wanted
    }

    private struct _Response: Decodable {
        let presets: [TweakPreset]
    }
}
