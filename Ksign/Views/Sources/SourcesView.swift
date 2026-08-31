//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	/// Held rather than deleted on the tap: a source takes a moment to add
	/// back, so the removal is confirmed first.
	@State private var _sourceToDelete: AltSource?
	
	/// The list a user manages: the sources they added. Ceresify's own catalog
	/// is what the store is, not a row to inspect or delete — and its URL stays
	/// off the screen, the same way the General tab's card leaves it out.
	private var _filteredSources: [AltSource] {
		_sources
			.filter { $0.sourceURL?.host != CeresifyAPI.baseURL.host }
			.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Sources")) {
			NBListAdaptable {
				Section {
					NavigationLink {
						SourceAppsView(object: Array(_sources), viewModel: viewModel)
					} label: {
						HStack(spacing: 9) {
							Image("Repositories").appIconStyle()
							NBTitleWithSubtitleView(
								title: .localized("All Repositories"),
								subtitle: .localized("See all apps from your sources")
							)
						}
					}
					.buttonStyle(.plain)
				}
				
				NBSection(
					.localized("Repositories"),
					secondary: _filteredSources.count.description
				) {
					ForEach(_filteredSources) { source in
						NavigationLink {
							SourceAppsView(object: [source], viewModel: viewModel)
						} label: {
							SourcesCellView(source: source)
						}
						.buttonStyle(.plain)
						// Swipe covers the list, the menu covers the grid the
						// iPad gets instead of one — a source added by hand
						// has to come off by hand either way.
						.swipeActions(edge: .trailing, allowsFullSwipe: false) {
							Button(role: .destructive) {
								_sourceToDelete = source
							} label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
						.contextMenu {
							Button(role: .destructive) {
								_sourceToDelete = source
							} label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
            .overlay {
                if _filteredSources.isEmpty {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("No Repositories"), systemImage: "globe.desk.fill")
                        } description: {
                            Text(.localized("Get started by adding your first repository."))
                        } actions: {
                            Button {
                                _isAddingPresenting = true
                            } label: {
                                Text("Add Source").bg()
                            }
                        }
                    }
                }
            }
            .toolbar {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing,
					isDisabled: _addingSourceLoading
				) {
					_isAddingPresenting = true
				}
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
					.presentationDetents([.medium])
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
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}
