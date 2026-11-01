// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// Onboarding.swift
// Launchpad
//
// Created by Dorneanu Denis on 01/11/2026.
//

import SwiftUI

struct OnboardingPanel: View {
	let finish: () -> Void

	@State private var step = 0

	private struct Page {
		let icon: String
		let title: LocalizedStringKey
		let text: LocalizedStringKey
	}

	private let pages: [Page] = [
		Page(icon: "square.grid.3x3.fill",
			 title: "Welcome to Launchpad",
			 text: "All your apps in one place. Click an app to open it, or just start typing to search. Return opens the best match."),
		Page(icon: "folder.fill",
			 title: "Organize your apps",
			 text: "Drag an app onto another to make a folder. Drop it on the side of an app to reorder. Right-click to hide an app."),
		Page(icon: "keyboard.fill",
			 title: "Move with the keyboard",
			 text: "Use the arrow keys to move around, Return to open, and the , and . keys to flip pages. Esc closes Launchpad."),
		Page(icon: "command",
			 title: "Open it from anywhere",
			 text: "Choose a shortcut to open and close Launchpad from any app. You can change it later in Settings.")
	]

	private var isLast: Bool { step == pages.count - 1 }

	var body: some View {
		ZStack {
			Color.black.opacity(0.45)
				.ignoresSafeArea()
				.contentShape(Rectangle())
				.onTapGesture { }

			VStack(spacing: 22) {
				Image(systemName: pages[step].icon)
					.font(.system(size: 44, weight: .medium))
					.foregroundStyle(.white)
					.frame(height: 54)

				VStack(spacing: 10) {
					Text(pages[step].title)
						.font(.system(size: 26, weight: .semibold))
						.foregroundStyle(.white)
					Text(pages[step].text)
						.font(.system(size: 15))
						.foregroundStyle(.white.opacity(0.8))
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}

				if isLast {
					ShortcutField()
						.controlSize(.large)
					Text("Launchpad keeps running in the background. Use the menu bar icon to open or quit it.")
						.font(.system(size: 13))
						.foregroundStyle(.white.opacity(0.6))
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}

				HStack(spacing: 8) {
					ForEach(pages.indices, id: \.self) { i in
						Circle()
							.fill(.white.opacity(i == step ? 0.95 : 0.3))
							.frame(width: 7, height: 7)
					}
				}

				HStack {
					if step > 0 {
						Button("Back") { step -= 1 }
					} else if !isLast {
						Button("Skip", action: finish)
					}
					Spacer()
					if isLast {
						Button("Done", action: finish)
							.keyboardShortcut(.defaultAction)
					} else {
						Button("Next") { step += 1 }
							.keyboardShortcut(.defaultAction)
					}
				}
			}
			.padding(36)
			.frame(width: 500)
			.glassCard(RoundedRectangle(cornerRadius: 32, style: .continuous))
			.contentShape(Rectangle())
			.onTapGesture { }
			.environment(\.colorScheme, .dark)
		}
	}
}
