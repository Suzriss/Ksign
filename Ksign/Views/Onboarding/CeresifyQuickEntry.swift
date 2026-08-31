//
//  CeresifyQuickEntry.swift
//  Ksign
//
//  Getting a registered device its certificate without asking again.
//

import Foundation
import CoreData
import NimbleExtensions

/// The profile is installed once, and everything after that happens by itself.
///
/// Registration hands over the device's UDID, and the account's certificate is
/// tied to it — so from the second launch on there is nothing for the user to
/// do: the certificate is pulled and imported in the background, and a launch
/// that finds it expired or revoked pulls the replacement. What used to take
/// two files and a password takes nothing at all.
///
/// It never opens a screen. A device that was never registered, or an account
/// with no certificate on it, is left exactly as it was for the registration
/// screen to deal with.
@MainActor
enum CeresifyQuickEntry {
	/// Re-checks with the server even when the stored certificate still looks
	/// good — a certificate can be replaced on the account without this device
	/// ever noticing otherwise.
	private static let _refreshInterval: TimeInterval = 7 * 24 * 60 * 60
	private static let _lastRefreshKey = "Ceresify.certificateRefreshedAt"
	
	/// Brings the device's certificate up to date, silently.
	static func refresh() async {
		guard let udid = CeresifyEnrollmentModel.storedUdid else { return }
		
		let existing = _storedCertificates()
		let hasUsable = existing.contains { !$0.revoked && ($0.expiration ?? .distantPast) > Date() }
		
		guard !hasUsable || _isDueForRefresh else { return }
		
		guard case .installed = await CeresifyEnrollmentModel.installCertificate(udid: udid) else {
			// No certificate on the account, or the server was unreachable —
			// either way what is already imported stays imported.
			return
		}
		
		UserDefaults.standard.set(Date(), forKey: _lastRefreshKey)
		
		// The import added a fresh pair rather than replacing anything, so the
		// ones it supersedes come off now — after the new one is safely in,
		// never before.
		let replaced = Set(existing.compactMap { $0.uuid })
		
		for certificate in _storedCertificates() where certificate.uuid.map(replaced.contains) == true {
			Storage.shared.deleteCertificate(for: certificate)
		}
	}
	
	private static var _isDueForRefresh: Bool {
		guard let last = UserDefaults.standard.object(forKey: _lastRefreshKey) as? Date else {
			return true
		}
		
		return Date().timeIntervalSince(last) > _refreshInterval
	}
	
	/// The certificates this device pulled from the account, as opposed to any
	/// the user imported themselves.
	private static func _storedCertificates() -> [CertificatePair] {
		let request: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		request.predicate = NSPredicate(
			format: "nickname == %@",
			CeresifyEnrollmentModel.certificateName
		)
		
		return (try? Storage.shared.context.fetch(request)) ?? []
	}
}
