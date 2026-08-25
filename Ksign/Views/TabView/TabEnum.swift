//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
    case home
    case files
	case sources
	case library
	case settings
	case certificates
	case appstore
    case general
    case signer
	var title: String {
		switch self {
        case .home:         return .localized("Home")
        case .files:        return .localized("Files")
		case .sources:     	return .localized("Sources")
		case .library: 		return .localized("Library")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		case .appstore: 	return .localized("Apps")
        case .general:      return .localized("General")
        case .signer:       return .localized("Signer")
		}
	}
	
	var icon: String {
		switch self {
        case .home:         return "house.fill"
        case .files:        return "folder.fill"
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		case .appstore: 	return "square.grid.2x2.fill"
        case .general:      return "globe"
        case .signer:       return "signature"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
        case .home: HomeView()
        case .files: FilesView()
		case .sources: SourcesView()
		case .library: LibraryView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		case .appstore: AppstoreView()
        case .general: GeneralView()
        case .signer: SignerView()
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
            .home,
            .appstore,
            .general,
            .signer,
			.settings,
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
