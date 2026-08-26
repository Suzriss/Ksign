//
//  AppFeaturesView.swift
//  Ksign
//
//  Created by Nagata Asami on 10/10/25.
//

import SwiftUI
import NimbleViews

struct AppFeaturesView: View {
    /// Read straight from `UserDefaults` at launch too, before any view exists.
    static let keepSignerAppsKey = "Ksign.keepSignerApps"
    
    @AppStorage("Ksign.cleanUpAfterInstall") private var _cleanUpAfterInstall: Bool = true
    @AppStorage(AppFeaturesView.keepSignerAppsKey) private var _keepSignerApps: Bool = false
    @StateObject private var _optionsManager = OptionsManager.shared
    
    var body: some View {
        NBList(.localized("App Features")) {
            Section {
                Toggle(isOn: $_optionsManager.options.backgroundAudio) {
                    Label(.localized("Keep app running in background"), systemImage: "arrow.trianglehead.2.clockwise")
                }
            } footer: {
                Text(.localized("This will keep the app running even when you close it, helpful with download or installing ipa."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.signingLogs) {
                    Label(.localized("Show logs when signing"), systemImage: "terminal")
                }
            } footer: {
                Text(.localized("This will show the logs of the signing process when you start signing."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.saveAppStoreDownloadsToDownloadsFolder) {
                    Label(.localized("Save App Store downloads to Downloads folder"), systemImage: "square.and.arrow.down.fill")
                }
            } footer: {
                Text(.localized("This will save the App Store downloads to the Downloads folder, turning this off will help reduce disk usage."))
            }
            Section {
                Toggle(isOn: $_cleanUpAfterInstall) {
                    Label(.localized("Clean up after installing"), systemImage: "trash")
                }
            } footer: {
                Text(.localized("Once an app finishes installing, remove its downloaded archive and its Library entries. Reinstalling it means downloading it again."))
            }
            Section {
                Toggle(isOn: $_keepSignerApps) {
                    Label(.localized("Keep apps after signing"), systemImage: "tray.full")
                }
            } footer: {
                Text(.localized("The Signer tab is emptied every time Ksign opens, because each app there is stored twice over. Turn this on to keep those apps until you delete them yourself. Certificates are never touched either way."))
            }
        }
        .onChange(of: _optionsManager.options) { _ in
            _optionsManager.saveOptions()
        }
    }
}
