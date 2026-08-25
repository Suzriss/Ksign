//
//  FRTitleWithSubtitleView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI

public struct NBTitleWithSubtitleView: View {
	private let _title: String
	private let _subtitle: String
	private var _linelimit: Int? = nil
	
	public init(title: String, subtitle: String, linelimit: Int? = nil) {
		self._title = title
		self._subtitle = subtitle
		self._linelimit = linelimit
	}
	
	public var body: some View {
		// App names and their descriptions stay white while the rest of the app
		// reads gold, so a list of apps is content rather than more chrome.
		VStack(alignment: .leading, spacing: 2) {
			Text(_title)
				.font(.headline)
				.foregroundStyle(.white)
			Text(_subtitle)
				.font(.subheadline)
				.foregroundStyle(.white.opacity(0.72))
		}
		.lineLimit(_linelimit)
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}
