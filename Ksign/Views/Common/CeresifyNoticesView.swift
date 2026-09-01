//
//  CeresifyNoticesView.swift
//  Ksign
//
//  What the shop says to a device: the notices it sends, and the sheet it puts
//  over the store.
//

import SwiftUI
import NukeUI
import NimbleViews
import NimbleExtensions
import UserNotifications
import UIKit

// MARK: - Delivery
/// Raises the notices the shop has sent, once each.
///
/// There is no APNs here and there can't be: the app is signed with somebody
/// else's certificate, so its bundle identifier doesn't match any push topic we
/// own and Apple never issues it a token. A notice rides down with the config
/// instead — which the app already fetches at launch and on every return to
/// the front — and is raised locally the first time it is seen. The cost is
/// that a notice arrives when the app is next opened rather than while it is
/// closed; everything else about it reads the same to the user.
enum CeresifyNoticeDelivery {
    /// Puts every notice that has never been raised on this device into
    /// Notification Center, and marks it so the next launch leaves it alone.
    static func deliverPending() async {
        let manager = CeresifyConfigManager.shared
        let pending = manager.undeliveredNotifications()
        
        guard !pending.isEmpty else { return }
        
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        // Never asked for permission on the store's behalf: the ask belongs to
        // Preferences, where the user turned notifications on. A device that
        // hasn't still gets the notices in the inbox.
        guard settings.authorizationStatus == .authorized else {
            manager.markDelivered(pending)
            return
        }
        
        for notice in pending {
            let content = UNMutableNotificationContent()
            content.title = notice.title.isEmpty ? "Ceresify" : notice.title
            content.body = notice.message
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: "ceresify.notice.\(notice.id)",
                content: content,
                // Straight away rather than on a schedule — the notice is
                // already late by the time the app has been opened.
                trigger: nil
            )
            
            try? await center.add(request)
        }
        
        manager.markDelivered(pending)
    }
}

// MARK: - Inbox
/// Everything the shop has sent this device, newest first.
struct CeresifyInboxView: View {
    @ObservedObject private var _config = CeresifyConfigManager.shared
    
    var body: some View {
        NBList(.localized("Notifications")) {
            if _config.notifications.isEmpty {
                Section {
                    Text(.localized("Nothing from the store yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(_config.notifications) { notice in
                        _row(notice)
                    }
                } footer: {
                    Text(.localized("Notices arrive when the app is opened."))
                }
            }
        }
        .toolbar {
            if _config.unreadNotificationCount > 0 {
                NBToolbarButton(
                    .localized("Mark all read"),
                    style: .text,
                    placement: .topBarTrailing
                ) {
                    _config.markAllRead()
                }
            }
        }
        .refreshable {
            await _config.load()
        }
    }
    
    @ViewBuilder
    private func _row(_ notice: CeresifyConfig.Notification) -> some View {
        Button {
            _config.markRead(notice)
            
            if let url = URL(string: notice.url), !notice.url.isEmpty {
                UIApplication.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(_config.isUnread(notice) ? Color.ceresifyAccent : .clear)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 3) {
                    if !notice.title.isEmpty {
                        Text(verbatim: notice.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ceresifyTitle)
                    }
                    
                    if !notice.message.isEmpty {
                        Text(verbatim: notice.message)
                            .font(.footnote)
                            .foregroundStyle(Color.ceresifySubtitle)
                    }
                    
                    if let date = notice.createdAt {
                        Text(verbatim: date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                if !notice.url.isEmpty {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Popup
/// The sheet the shop puts over the store.
///
/// Shown a set number of times per device — the count is kept here, because the
/// server has no idea who has looked at what — and gone for good once the date
/// the shop set has passed.
struct CeresifyPopupView: View {
    let popup: CeresifyConfig.Popup
    let onClose: () -> Void
    
    @Environment(\.layoutDirection) private var _layoutDirection
    
    /// Which corner the dismiss button sits in.
    ///
    /// `auto` puts it in the corner the reader's eye ends on — left in Arabic,
    /// right in English — so it is out of the way of the text either way.
    private var _closeAlignment: Alignment {
        switch popup.closeSide {
        case "left":  return .topLeading
        case "right": return .topTrailing
        default:      return _layoutDirection == .rightToLeft ? .topLeading : .topTrailing
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            
            VStack(spacing: 0) {
                _artwork
                
                VStack(spacing: 10) {
                    if !popup.title.isEmpty {
                        Text(verbatim: popup.title)
                            .font(.title3.bold())
                            .foregroundStyle(Color.ceresifyTitle)
                            .multilineTextAlignment(.center)
                    }
                    
                    if !popup.message.isEmpty {
                        Text(verbatim: popup.message)
                            .font(.subheadline)
                            .foregroundStyle(Color.ceresifySubtitle)
                            .multilineTextAlignment(.center)
                    }
                    
                    if !popup.buttonText.isEmpty {
                        Button {
                            if let url = URL(string: popup.buttonURL), !popup.buttonURL.isEmpty {
                                UIApplication.open(url)
                            }
                            
                            onClose()
                        } label: {
                            Text(verbatim: popup.buttonText)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.ceresifyAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(Color.black)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: 340)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: _closeAlignment) { _closeButton }
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .padding(.horizontal, 24)
        }
    }
    
    @ViewBuilder
    private var _artwork: some View {
        if let url = URL(string: popup.imageURL), !popup.imageURL.isEmpty {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .tertiarySystemFill)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
        }
    }
    
    private var _closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel(Text(.localized("Close")))
    }
}

// MARK: - Host
/// Puts whichever sheet is owed to this device over the page, and counts it as
/// shown the moment it appears.
struct CeresifyPopupHostModifier: ViewModifier {
    @ObservedObject private var _config = CeresifyConfigManager.shared
    
    @State private var _popup: CeresifyConfig.Popup?
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if let popup = _popup {
                    CeresifyPopupView(popup: popup) {
                        withAnimation(.smooth(duration: 0.25)) { _popup = nil }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.smooth(duration: 0.25), value: _popup?.id)
            // A new config is what brings a sheet — and what takes one away
            // that the shop has since switched off.
            .onChange(of: _config.revision) { _ in _present() }
            .task {
                // The stored config is already in hand at launch, so the sheet
                // doesn't wait on the network to appear.
                _present()
                await CeresifyNoticeDelivery.deliverPending()
            }
    }
    
    private func _present() {
        guard _popup == nil, let due = _config.duePopup else { return }
        
        _popup = due
        _config.markPopupShown(due)
    }
}

extension View {
    /// The sheet the shop is owed a showing of, over this page.
    func ceresifyPopups() -> some View {
        modifier(CeresifyPopupHostModifier())
    }
}
