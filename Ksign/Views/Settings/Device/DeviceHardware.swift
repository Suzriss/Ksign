//
//  DeviceHardware.swift
//  Ksign
//
//  What this device actually is, without asking the server.
//

import Foundation
import UIKit

/// The facts about the device the app is running on.
///
/// Everything here is read off the device itself, so it is there before
/// registration and while offline — which is the point: the Device Information
/// page used to show nothing at all until the server had answered, and the
/// people most likely to open it are the ones whose registration hasn't gone
/// through yet.
enum DeviceHardware {
    /// The hardware identifier — `iPad13,4`, `iPhone16,2`.
    ///
    /// `utsname` rather than `UIDevice`: `UIDevice.model` says only "iPad", and
    /// `UIDevice.name` has been the model name for everybody since iOS 16
    /// unless the app carries an entitlement we don't have.
    static let identifier: String = {
        var system = utsname()
        uname(&system)
        
        let mirror = Mirror(reflecting: system.machine)
        let raw = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        
        return raw.isEmpty ? UIDevice.current.model : raw
    }()
    
    /// The name the device is sold under, when it is one we can name, and the
    /// hardware identifier when it isn't — a model newer than this build reads
    /// as `iPhone19,1` rather than as nothing.
    static var marketingName: String {
        _names[identifier] ?? identifier
    }
    
    /// `iPadOS 18.2`, the way Settings writes it.
    static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
    
    /// Free and total storage, already formatted.
    static var storage: (free: String, total: String)? {
        guard
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            ),
            let free = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity
        else {
            return nil
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        
        return (
            formatter.string(fromByteCount: free),
            formatter.string(fromByteCount: Int64(total))
        )
    }
    
    /// The models this build knows by name. Anything missing falls back to its
    /// identifier, so the list going stale costs a nicer word and nothing else.
    private static let _names: [String: String] = [
        // iPhone
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        // iPad
        "iPad11,1": "iPad mini (5th generation)",
        "iPad11,2": "iPad mini (5th generation)",
        "iPad11,3": "iPad Air (3rd generation)",
        "iPad11,4": "iPad Air (3rd generation)",
        "iPad11,6": "iPad (8th generation)",
        "iPad11,7": "iPad (8th generation)",
        "iPad12,1": "iPad (9th generation)",
        "iPad12,2": "iPad (9th generation)",
        "iPad13,1": "iPad Air (4th generation)",
        "iPad13,2": "iPad Air (4th generation)",
        "iPad13,4": "iPad Pro 11-inch (3rd generation)",
        "iPad13,5": "iPad Pro 11-inch (3rd generation)",
        "iPad13,6": "iPad Pro 11-inch (3rd generation)",
        "iPad13,7": "iPad Pro 11-inch (3rd generation)",
        "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad13,18": "iPad (10th generation)",
        "iPad13,19": "iPad (10th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,3": "iPad Air 11-inch (M3)",
        "iPad15,4": "iPad Air 11-inch (M3)",
        "iPad15,5": "iPad Air 13-inch (M3)",
        "iPad15,6": "iPad Air 13-inch (M3)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        // The simulator names itself after the host
        "x86_64": "Simulator",
        "arm64": "Simulator"
    ]
}
