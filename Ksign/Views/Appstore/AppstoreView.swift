//
//  AppstoreView.swift
//  Ksign
//
//  Created by Nagata Asami on 3/8/25.
//

import SwiftUI
import NimbleViews
import CoreData
import AltSourceKit

struct AppstoreView: View {
	@StateObject private var _viewModel = SourcesViewModel.shared
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	/// This tab is the shop's own store, and nothing else.
	///
	/// A source someone added by hand used to be merged in here, which mixed a
	/// stranger's builds into the catalog the shop curates and gave them the
	/// shop's categories to sit under. They are reached from their own page
	/// instead — the Sources card on General, one source at a time.
	private var _catalog: [AltSource] {
		_sources.filter { $0.sourceURL?.host == CeresifyAPI.baseURL.host }
	}
	
	var body: some View {
		NavigationStack {
            SourceAppsView(fromAppStore: true, object: _catalog, viewModel: _viewModel)
                .nbAppearanceBackground()
		}
		// Every source is still fetched — the Sources card on General shows a
		// page per source and reads the same view model, and only one fetch
		// gets to run at a time. What changed is which of them this tab draws.
		.task(id: Array(_sources)) {
			await _viewModel.fetchSources(Array(_sources))
		}
	}
}
