//
//  CeresifyEnrollmentView.swift
//  Ksign
//
//  First-launch device registration.
//

import SwiftUI
import NimbleViews

struct CeresifyEnrollmentView: View {
    @StateObject private var _model = CeresifyEnrollmentModel()
    
    @Environment(\.scenePhase) private var _scenePhase
    
    /// Set once the user has been through here, so a launch without a
    /// certificate doesn't corner them every time.
    @AppStorage("Ceresify.hasSeenEnrollment") private var _hasSeenEnrollment: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                
                VStack(spacing: 22) {
                    _icon
                    _title
                    _body
                }
                .padding(.horizontal, 28)
                
                Spacer(minLength: 0)
                
                _actions
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
            .toolbar {
                NBToolbarButton(
                    .localized("Later"),
                    style: .text,
                    placement: .topBarTrailing
                ) {
                    _finish()
                }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            // A device that registered on an earlier launch only needs the
            // certificate, so skip straight past the profile step.
            if _model.storedUdid != nil, _model.step == .intro {
                _model.fetchCertificateForStoredDevice()
            }
        }
        .onChange(of: _scenePhase) { phase in
            // Installing the profile means leaving for Settings, so coming back
            // is the moment the UDID is most likely to be waiting.
            if phase == .active {
                _model.resumeIfPending()
            }
        }
        .onChange(of: _model.step) { step in
            // Registering is what this screen exists for; whether a
            // certificate came with it is the account's business, and the
            // background refresh picks that up on a later launch.
            if step == .installed || _model.storedUdid != nil {
                _hasSeenEnrollment = true
            }
        }
    }
    
    // MARK: Pieces
    
    private var _icon: some View {
        Image(systemName: _iconName)
            .font(.system(size: 54))
            .foregroundStyle(Color.accentColor)
            .symbolRenderingMode(.hierarchical)
    }
    
    private var _iconName: String {
        switch _model.step {
        case .intro:                return "iphone.badge.checkmark"
        case .waiting:              return "arrow.down.circle"
        case .fetchingCertificate:  return "arrow.down.doc"
        case .installed:            return "checkmark.seal.fill"
        case .noCertificate:        return "exclamationmark.triangle"
        case .failed:               return "xmark.octagon"
        }
    }
    
    private var _title: some View {
        Text(verbatim: _titleText)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
    }
    
    private var _titleText: String {
        switch _model.step {
        case .intro:                return .localized("Register your device")
        case .waiting:              return .localized("Waiting for your device")
        case .fetchingCertificate:  return .localized("Fetching your certificate")
        case .installed:            return .localized("Your certificate is ready")
        case .noCertificate:        return .localized("No certificate on this account")
        case .failed:               return .localized("Registration failed")
        }
    }
    
    @ViewBuilder
    private var _body: some View {
        switch _model.step {
        case .intro:
            _text(.localized("Ceresify needs your device's UDID to issue a signing certificate. Tap below — Safari opens, downloads a profile, and you install it from Settings."))
        case .waiting:
            VStack(spacing: 16) {
                ProgressView()
                _text(.localized("Open Settings, tap the downloaded profile, and install it. This screen carries on by itself once your device reports in."))
            }
        case .fetchingCertificate:
            VStack(spacing: 16) {
                ProgressView()
                _text(.localized("Your device is registered. Bringing over the certificate."))
            }
        case .installed:
            _text(.localized("The certificate is installed and picked as your signing certificate. You can sign apps right away."))
        case .noCertificate(let isSubscribed):
            _text(
                isSubscribed
                ? .localized("Your subscription is active but no certificate has been issued yet. Contact support and try again.")
                : .localized("This device isn't subscribed yet. Once a subscription is active, come back and the certificate lands here.")
            )
        case .failed(let message):
            _text(message)
        }
    }
    
    private func _text(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var _actions: some View {
        switch _model.step {
        case .intro:
            _primaryButton(.localized("Register this device")) {
                _model.register()
            }
        case .waiting:
            _secondaryButton(.localized("Cancel")) {
                _model.cancel()
            }
        case .fetchingCertificate:
            EmptyView()
        case .installed:
            _primaryButton(.localized("Done")) {
                _finish()
            }
        case .noCertificate:
            VStack(spacing: 10) {
                _primaryButton(.localized("Check again")) {
                    _model.fetchCertificateForStoredDevice()
                }
                _secondaryButton(.localized("Later")) {
                    _finish()
                }
            }
        case .failed:
            VStack(spacing: 10) {
                // A device that already registered has nothing to gain from a
                // second profile — what failed was the certificate, so that is
                // what is tried again.
                if _model.storedUdid != nil {
                    _primaryButton(.localized("Check again")) {
                        _model.fetchCertificateForStoredDevice()
                    }
                } else {
                    _primaryButton(.localized("Try again")) {
                        _model.register()
                    }
                }
                
                _secondaryButton(.localized("Later")) {
                    _finish()
                }
            }
        }
    }
    
    private func _primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
    }
    
    private func _secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
    
    private func _finish() {
        _model.cancel()
        _hasSeenEnrollment = true
        dismiss()
    }
}
