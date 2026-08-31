//
//  CeresifyDeviceIdentity.swift
//  Ksign
//
//  Knowing which device this is from the certificate the app was signed with.
//

import Foundation
import NimbleExtensions

/// Reads this device's UDID out of the app's own provisioning profile.
///
/// A build signed for one subscriber carries exactly one device in its
/// profile — theirs. Apple hands that list to the app itself, so a copy
/// installed with a certificate issued here already knows whose device it is
/// running on, and there is nothing left for the profile-install dance to
/// find out: the app asks the server whether that UDID is registered, and
/// either opens on the subscriber's own account or says why it can't.
///
/// A build signed for many devices — a shared certificate, a development
/// profile, the App Store — tells us nothing, since the list is everyone's
/// rather than this one's. Those fall back to registering by hand, exactly as
/// before.
enum CeresifyDeviceIdentity {
	/// The UDID this copy was signed for, when it was signed for one device.
	static func provisionedUdid() -> String? {
		guard
			let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
			let data = try? Data(contentsOf: url),
			let profile = CertificateReader.parseData(data),
			let devices = profile.ProvisionedDevices
		else {
			return nil
		}
		
		// More than one and it isn't an answer about this device; none at all
		// is a store build.
		guard devices.count == 1 else { return nil }
		
		let udid = devices[0].trimmingCharacters(in: .whitespacesAndNewlines)
		return udid.isEmpty ? nil : udid
	}
	
	/// Takes the profile's UDID as this device's, unless registration has
	/// already found one.
	///
	/// Nothing overwrites a UDID that came from registering: that one was
	/// confirmed by the server, and a re-signed copy of the app must not
	/// quietly move an account onto a different device.
	@discardableResult
	static func adoptProvisionedUdidIfNeeded() -> String? {
		if let existing = CeresifyEnrollmentModel.storedUdid { return existing }
		guard let udid = provisionedUdid() else { return nil }
		
		let defaults = UserDefaults.standard
		defaults.set(udid, forKey: CeresifyEnrollmentModel.udidKey)
		// There is no profile to install, so the registration screen has
		// nothing left to ask for.
		defaults.set(true, forKey: CeresifyEnrollmentModel.hasSeenEnrollmentKey)
		
		return udid
	}
}
