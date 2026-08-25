//
//  AppFeaturesView.swift
//  Ksign
//
//  Created by Nagata Asami on 10/10/25.
//

import SwiftUI
import NimbleViews

struct AppFeaturesView: View {
    @AppStorage("Ksign.cleanUpAfterInstall") private var _cleanUpAfterInstall: Bool = true
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
        }
        .onChange(of: _optionsManager.options) { _ in
            _optionsManager.saveOptions()
        }
    }
}
