// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
//  Settings.swift
//  Launchpad
//
//  Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI
import ServiceManagement

enum Keys {
	static let columns = "columns"
	static let rows = "rows"
	static let iconSize = "iconSize"
	static let showLabels = "showLabels"
	static let language = "language"
	static let layout = "layout.v1"
	static let hidden = "hiddenApps.v1"
	static let menuBar = "menuBar"
	static let launchCounts = "launchCounts.v1"
	static let dim = "backgroundDim"
	static let hotkeyEnabled = "hotkeyEnabled"
	static let hotkeyCode = "hotkeyCode"
	static let hotkeyMods = "hotkeyMods"
	static let hotkeyLabel = "hotkeyLabel"
}

enum Defaults {
	static let columns = 7
	static let rows = 5
	static let iconSize = 96.0
	static let dim = 0.35
	static let hotkeyCode = 37
	static let hotkeyMods = 4096
	static let hotkeyLabel = "L"
}

enum AppLanguage: String, CaseIterable, Identifiable {
	case system, en, ro, es, fr, de
	var id: String { rawValue }

	var locale: Locale {
		self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
	}

	var nativeName: String? {
		switch self {
		case .system: nil
		case .en: "English"
		case .ro: "Română"
		case .es: "Español"
		case .fr: "Français"
		case .de: "Deutsch"
		}
	}
}

func tr(_ key: String) -> String {
	let code = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.system.rawValue
	if code != AppLanguage.system.rawValue,
	   let path = Bundle.main.path(forResource: code, ofType: "lproj"),
	   let bundle = Bundle(path: path) {
		return bundle.localizedString(forKey: key, value: key, table: nil)
	}
	return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

struct RootView: View {
	@AppStorage(Keys.language) private var language = AppLanguage.system.rawValue

	var body: some View {
		LaunchpadView()
			.environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
	}
}

enum LaunchAtLogin {
	static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

	static func set(_ enabled: Bool) {
		guard enabled != isEnabled else { return }
		do {
			if enabled { try SMAppService.mainApp.register() }
			else { try SMAppService.mainApp.unregister() }
		} catch {
			print("Launch at login failed:", error)
		}
	}
}

extension View {
	func glassCard<S: Shape>(_ shape: S) -> some View {
		background {
			if #available(macOS 26.0, *) {
				shape.glassEffect(.regular, in: shape)
			} else {
				shape.fill(.ultraThinMaterial)
			}
		}
	}
}

func animated<R>(_ animation: Animation = .spring(response: 0.35, dampingFraction: 0.85),
				 _ body: () throws -> R) rethrows -> R {
	try withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, body)
}

struct SettingsPanel: View {
	let close: () -> Void
	@EnvironmentObject private var store: AppStore

	@AppStorage(Keys.columns) private var columns = Defaults.columns
	@AppStorage(Keys.rows) private var rows = Defaults.rows
	@AppStorage(Keys.iconSize) private var iconSize = Defaults.iconSize
	@AppStorage(Keys.showLabels) private var showLabels = true
	@AppStorage(Keys.dim) private var dim = Defaults.dim
	@AppStorage(Keys.language) private var language = AppLanguage.system.rawValue

	@AppStorage(Keys.menuBar) private var menuBar = true
	@AppStorage(Keys.hotkeyEnabled) private var hotkeyEnabled = true

	@State private var launchAtLogin = LaunchAtLogin.isEnabled
	@State private var confirmReset = false

	var body: some View {
		ZStack {
			Color.black.opacity(0.35)
				.ignoresSafeArea()
				.contentShape(Rectangle())
				.onTapGesture(perform: close)

			VStack(spacing: 0) {
				HStack {
					Text("Settings").font(.title2.weight(.semibold))
					Spacer()
					Button("Done", action: close)
				}
				.padding(.horizontal, 24)
				.padding(.top, 20)
				.padding(.bottom, 8)

				Form {
					Section("Layout") {
						Stepper(value: $columns, in: 4...10) {
							LabeledContent("Columns") { Text(String(columns)).monospacedDigit() }
						}
						Stepper(value: $rows, in: 3...7) {
							LabeledContent("Rows") { Text(String(rows)).monospacedDigit() }
						}
						LabeledContent("Icon size") {
							Slider(value: $iconSize, in: 48...128).frame(width: 180)
						}
						Toggle("Show app names", isOn: $showLabels)
						LabeledContent("Background dim") {
							Slider(value: $dim, in: 0...0.8).frame(width: 180)
						}
					}

					Section("General") {
						Toggle("Launch at login", isOn: $launchAtLogin)
							.onChange(of: launchAtLogin) { _, on in
								LaunchAtLogin.set(on)
								launchAtLogin = LaunchAtLogin.isEnabled
							}

						Picker("Language", selection: $language) {
							ForEach(AppLanguage.allCases) { lang in
								if let name = lang.nativeName {
									Text(verbatim: name).tag(lang.rawValue)
								} else {
									Text("System default").tag(lang.rawValue)
								}
							}
						}
					}

					Section("Shortcut & menu bar") {
						Toggle("Global shortcut", isOn: $hotkeyEnabled)
						LabeledContent("Shortcut") { ShortcutField() }
							.disabled(!hotkeyEnabled)
						Toggle("Show in menu bar", isOn: $menuBar)
						Button("Quit Launchpad") { NSApp.terminate(nil) }
					}

					Section("Hidden apps") {
						let hiddenApps = store.hiddenApps
						if hiddenApps.isEmpty {
							Text("No hidden apps").foregroundStyle(.secondary)
						}
						ForEach(hiddenApps) { app in
							HStack(spacing: 10) {
								Image(nsImage: app.icon)
									.resizable()
									.frame(width: 22, height: 22)
								Text(verbatim: app.name)
								Spacer()
								Button("Unhide") { store.unhide(app.path) }
							}
						}
					}

					Section {
						if confirmReset {
							Text("This removes all folders and your custom order. Hidden apps stay hidden.")
								.font(.callout)
								.foregroundStyle(.secondary)
							HStack {
								Button("Cancel") { confirmReset = false }
								Spacer()
								Button("Reset layout", role: .destructive) {
									store.resetLayout()
									confirmReset = false
								}
							}
						} else {
							Button("Reset layout", role: .destructive) { confirmReset = true }
						}
						Button("Clear launch history") { store.clearLaunchHistory() }
					}
				}
				.formStyle(.grouped)
				.scrollContentBackground(.hidden)
			}
			.frame(width: 480, height: 600)
			.glassCard(RoundedRectangle(cornerRadius: 28, style: .continuous))
			.contentShape(Rectangle())
			.onTapGesture { }
			.environment(\.colorScheme, .dark)
		}
	}
}
