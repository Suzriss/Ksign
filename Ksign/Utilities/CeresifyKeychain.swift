//
//  CeresifyKeychain.swift
//  Ksign
//
//  A reinstall wipes UserDefaults, but not the Keychain — and the device's
//  udid was kept in UserDefaults, so reinstalling the app (a fresh TestFlight
//  build, say) made an already-registered, already-subscribed device look
//  brand new: the enrollment screen came back and asked to install the
//  profile a second time, even though the server had known this exact udid
//  the whole time. Anything that has to survive that goes here instead.
//

import Foundation
import Security

enum CeresifyKeychain {
    /// Scoped to this feature specifically — a service string is how the
    /// Keychain tells one app's items from another's, or one feature's from
    /// the next within the same app.
    private static let service = "com.ceresify.enrollment"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `nil` or empty deletes the item — a udid is either there or it isn't,
    /// never an empty string sitting in for "none".
    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        guard updateStatus == errSecItemNotFound else { return }

        var newItem = query
        newItem[kSecValueData as String] = data
        // Available the moment the device is unlocked once after a restart,
        // and — the point of all this — not removed on reinstall the way
        // `.whenUnlockedThisDeviceOnly` would be for some items.
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newItem as CFDictionary, nil)
    }

    static func getBool(_ key: String) -> Bool {
        get(key) == "1"
    }

    static func setBool(_ value: Bool, for key: String) {
        set(value ? "1" : nil, for: key)
    }
}
