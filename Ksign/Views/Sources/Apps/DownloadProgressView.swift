//
//  DownloadProgressView.swift
//  Ksign
//
//  The sheet that comes up on Get: how far along the download is, and how much
//  of it is left.
//

import SwiftUI
import Combine
import NukeUI
import NimbleViews
import NimbleExtensions

// MARK: - View
/// Presented the moment Get is tapped, so the answer to "how long is this going
/// to take" is on screen instead of being read off a pill in a list row.
///
/// It follows the download it was opened for by id rather than holding onto the
/// object: the manager drops a download as soon as it finishes, which is what
/// turns this sheet into its finished state.
struct DownloadProgressView: View {
	let title: String
	let iconURL: URL?
	let downloadId: String
	/// Ceresify signs its own builds server-side, where there is no byte count
	/// to show — only the wait.
	let isCloudSigning: Bool
	
	@ObservedObject private var _manager = DownloadManager.shared
	@Environment(\.dismiss) private var _dismiss
	
	@State private var _didStart = false
	
	private var _download: Download? {
		_manager.getDownload(by: downloadId)
	}
	
	var body: some View {
		VStack(spacing: 22) {
			_header
			
			if let download = _download {
				_DownloadBody(download: download)
					.onAppear { _didStart = true }
			} else if isCloudSigning {
				_waiting(.localized("Preparing your download…"))
			} else if _didStart {
				_finished
			} else {
				_waiting(.localized("Starting…"))
			}
			
			_action
		}
		.padding(.horizontal, 24)
		.padding(.top, 26)
		.padding(.bottom, 18)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.presentationDetents([.height(360)])
		.presentationDragIndicator(.visible)
	}
	
	// MARK: Header
	
	private var _header: some View {
		VStack(spacing: 10) {
			Group {
				if let iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
							image.appIconStyle(size: 62)
						} else {
							Image("App_Unknown").appIconStyle(size: 62)
						}
					}
				} else {
					Image("App_Unknown").appIconStyle(size: 62)
				}
			}
			
			Text(verbatim: title)
				.font(.headline)
				.foregroundStyle(Color.ceresifyTitle)
				.lineLimit(1)
		}
	}
	
	// MARK: States
	
	@ViewBuilder
	private func _waiting(_ text: String) -> some View {
		VStack(spacing: 12) {
			ProgressView()
			
			Text(verbatim: text)
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 18)
	}
	
	private var _finished: some View {
		VStack(spacing: 12) {
			Image(systemName: "checkmark.circle.fill")
				.font(.system(size: 40))
				.foregroundStyle(.green)
			
			Text(.localized("Download complete"))
				.font(.subheadline.weight(.medium))
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 10)
		.task {
			// Long enough to be read, short enough not to be in the way.
			try? await Task.sleep(for: .seconds(1.4))
			_dismiss()
		}
	}
	
	// MARK: Action
	
	@ViewBuilder
	private var _action: some View {
		if let download = _download, download.unpackageProgress == 0 {
			Button(role: .destructive) {
				_manager.cancelDownload(download)
				_dismiss()
			} label: {
				Text(.localized("Cancel Download"))
					.font(.body.weight(.medium))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(Color(uiColor: .quaternarySystemFill))
					.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.red)
		} else {
			Button {
				_dismiss()
			} label: {
				Text(.localized("Hide"))
					.font(.body.weight(.medium))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(Color(uiColor: .quaternarySystemFill))
					.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
			.foregroundStyle(Color.ceresifyGold)
		}
	}
}

// MARK: - Progress
/// Split out so the sheet can watch one download's own `@Published` fields:
/// the manager only republishes when the list of downloads changes.
private struct _DownloadBody: View {
	@ObservedObject var download: Download
	
	/// Sampled once a second — the byte count moves far more often than that,
	/// and a rate recomputed on every callback jumps around too much to read.
	@State private var _lastBytes: Int64 = 0
	@State private var _bytesPerSecond: Double = 0
	
	private let _tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
	
	private var _isExtracting: Bool {
		download.unpackageProgress > 0
	}
	
	private var _percent: Int {
		Int((download.overallProgress * 100).rounded())
	}
	
	private var _remaining: Int64 {
		max(0, download.totalBytes - download.bytesDownloaded)
	}
	
	var body: some View {
		VStack(spacing: 14) {
			ZStack {
				Circle()
					.stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 10)
				
				Circle()
					.trim(from: 0, to: max(0.001, min(1, download.overallProgress)))
					.stroke(
						Color.ceresifyGold,
						style: StrokeStyle(lineWidth: 10, lineCap: .round)
					)
					.rotationEffect(.degrees(-90))
					.animation(.smooth, value: download.overallProgress)
				
				VStack(spacing: 2) {
					Text(verbatim: "\(_percent)%")
						.font(.title2.bold())
						.monospacedDigit()
						.contentTransition(.numericText())
						.animation(.smooth, value: _percent)
					
					Text(_isExtracting ? .localized("Extracting") : .localized("Downloading"))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			.frame(width: 108, height: 108)
			
			VStack(spacing: 4) {
				if download.totalBytes > 0 {
					Text(verbatim: "\(download.bytesDownloaded.formattedByteCount) / \(download.totalBytes.formattedByteCount)")
						.font(.subheadline.weight(.medium))
						.monospacedDigit()
				}
				
				Text(verbatim: _detail)
					.font(.caption)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
		}
		.onReceive(_tick) { _ in
			let bytes = download.bytesDownloaded
			let delta = bytes - _lastBytes
			_lastBytes = bytes
			
			guard delta > 0 else { return }
			
			// Smoothed, so one slow second doesn't throw the estimate away.
			_bytesPerSecond = _bytesPerSecond == 0
			? Double(delta)
			: (_bytesPerSecond * 0.6) + (Double(delta) * 0.4)
		}
	}
	
	/// What is actually left: bytes first, and a time estimate once there is a
	/// rate worth trusting.
	private var _detail: String {
		if _isExtracting {
			return .localized("Unpacking the app…")
		}
		
		guard download.totalBytes > 0 else {
			return .localized("Starting…")
		}
		
		let left = "\(_remaining.formattedByteCount) " + .localized("left")
		
		guard _bytesPerSecond > 0 else {
			return left
		}
		
		let seconds = Double(_remaining) / _bytesPerSecond
		let speed = Int64(_bytesPerSecond).formattedByteCount
		
		return "\(left) • \(Self._time(seconds)) • \(speed)/s"
	}
	
	private static func _time(_ seconds: Double) -> String {
		guard seconds.isFinite, seconds > 0 else {
			return .localized("almost done")
		}
		
		let total = Int(seconds.rounded())
		
		if total < 60 {
			return String.localized("%@s left", arguments: "\(total)")
		}
		
		let minutes = total / 60
		
		if minutes < 60 {
			return String.localized("%@m left", arguments: "\(minutes)")
		}
		
		return String.localized("%@h left", arguments: "\(minutes / 60)")
	}
}
