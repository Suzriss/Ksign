//
//  DeviceInfoView.swift
//  Ksign
//
//  The first thing Settings opens: what this device is, and whether it is
//  registered and subscribed.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import UIKit

// MARK: - View
struct DeviceInfoView: View {
	@StateObject private var _model = DeviceInfoModel()
	@State private var _isEnrollmentPresenting = false
	@State private var _didCopy = false
	
	var body: some View {
		NBList(.localized("Device Information")) {
			Section {
				_header
					.listRowBackground(EmptyView())
			}
			
			// What the device is, said whether or not the server has ever
			// answered about it: someone whose registration hasn't gone
			// through is exactly who opens this page, and it used to have
			// nothing at all on it for them.
			Section {
				_row(.localized("Name"), value: _deviceName)
				_row(.localized("Model"), value: DeviceHardware.marketingName)
				_row(.localized("Identifier"), value: DeviceHardware.identifier)
				_row(.localized("iOS Version"), value: DeviceHardware.systemVersion)
				
				if let device = _model.device {
					_udidRow(device.udid)
				}
			}
			
			if let device = _model.device {
				Section {
					_row(
						.localized("Subscription"),
						value: device.isSubscribed
						? .localized("Active")
						: .localized("None")
					)
					
					if let expiry = device.expiry {
						_row(.localized("Expires"), value: expiry.formatted(date: .abbreviated, time: .omitted))
					}
				} footer: {
					if !device.isSubscribed {
						Text(.localized("Order a subscription from the store to sign and install without limits."))
					}
				}
			} else {
				Section {
					Button {
						_isEnrollmentPresenting = true
					} label: {
						Label(.localized("Register your device"), systemImage: "iphone.badge.checkmark")
					}
				} footer: {
					Text(.localized("Install the profile so we can register your device. After that you can sign apps."))
				}
			}
		}
		.sheet(isPresented: $_isEnrollmentPresenting) {
			CeresifyEnrollmentView()
		}
		.refreshable {
			await _model.load()
		}
		.task {
			await _model.load()
		}
		.onChange(of: _isEnrollmentPresenting) { isPresenting in
			// The sheet is where registration happens, so the card is stale the
			// moment it closes.
			if !isPresenting {
				Task { await _model.load() }
			}
		}
	}
	
	/// The name the profile registered, and the device's own otherwise.
	///
	/// `UIDevice.name` has been the model name rather than what the owner
	/// called their device since iOS 16, so the registered name is the only
	/// one worth having: the server's answer first, then the copy kept from
	/// registration for when the server can't be reached, and the model name
	/// only before there is any.
	private var _deviceName: String {
		_model.device?.name
		?? CeresifyEnrollmentModel.storedDeviceName
		?? UIDevice.current.name
	}
	
	// MARK: Header
	
	private var _header: some View {
		VStack(spacing: 10) {
			Image(systemName: "iphone.gen3")
				.font(.system(size: 42))
				.foregroundStyle(Color.ceresifyGold)
			
			Text(verbatim: _deviceName)
				.font(.title3.bold())
			
			_statusPill
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 8)
	}
	
	private var _statusPill: some View {
		let device = _model.device
		let isSubscribed = device?.isSubscribed ?? false
		
		let title: String = isSubscribed
		? .localized("Active")
		: (device != nil ? .localized("Registered") : .localized("Not registered"))
		
		let color: Color = isSubscribed
		? .green
		: (device != nil ? .ceresifyGold : .secondary)
		
		return HStack(spacing: 6) {
			Circle()
				.fill(color)
				.frame(width: 7, height: 7)
			
			Text(verbatim: title)
				.font(.caption.weight(.semibold))
		}
		.foregroundStyle(color)
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(Color(uiColor: .quaternarySystemFill))
		.clipShape(Capsule())
	}
	
	// MARK: Rows
	
	@ViewBuilder
	private func _row(_ title: String, value: String) -> some View {
		HStack {
			Text(verbatim: title)
			
			Spacer(minLength: 12)
			
			Text(verbatim: value)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}
	
	@ViewBuilder
	private func _udidRow(_ udid: String) -> some View {
		Button {
			UIPasteboard.general.string = udid
			UINotificationFeedbackGenerator().notificationOccurred(.success)
			
			withAnimation { _didCopy = true }
			
			Task {
				try? await Task.sleep(for: .seconds(2))
				withAnimation { _didCopy = false }
			}
		} label: {
			HStack {
				Text(verbatim: .localized("UDID"))
					.foregroundStyle(Color.ceresifyGold)
				
				Spacer(minLength: 12)
				
				Text(verbatim: _didCopy ? .localized("Copied") : Self._shorten(udid))
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
				
				Image(systemName: _didCopy ? "checkmark" : "doc.on.doc")
					.font(.caption)
			}
		}
	}
	
	/// The full UDID never fits a row, and the ends are what identifies it.
	private static func _shorten(_ udid: String) -> String {
		guard udid.count > 16 else { return udid }
		return "\(udid.prefix(8))…\(udid.suffix(4))"
	}
}
