//
//  launchpadview.swift
//  Launchpad
//
//  Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI


private struct DismissKey: EnvironmentKey {
	static let defaultValue: () -> Void = { NSApp.terminate(nil) }
}
extension EnvironmentValues {
	var dismissLaunchpad: () -> Void {
		get { self[DismissKey.self] }
		set { self[DismissKey.self] = newValue }
	}
}

struct VisualEffect: NSViewRepresentable {
	func makeNSView(context: Context) -> NSVisualEffectView {
		let v = NSVisualEffectView()
		v.material = .hudWindow
		v.blendingMode = .behindWindow
		v.state = .active
		return v
	}
	func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct LaunchpadView: View {
	@StateObject private var store = AppStore()
	@State private var query = ""
	@State private var page = 0
	@State private var drag: CGFloat = 0
	@State private var scroll = ScrollState()
	@State private var monitorsInstalled = false
	@State private var appeared = false
	@State private var hidden: Set<String> =
		Set(UserDefaults.standard.stringArray(forKey: "hiddenApps") ?? [])
	@FocusState private var searchFocused: Bool

	private let columns = 7
	private let rows = 5
	private var perPage: Int { columns * rows }

	private var visibleApps: [AppItem] {
		store.apps.filter { !hidden.contains($0.url.path) }
	}
	private var filtered: [AppItem] {
		query.isEmpty ? visibleApps
					  : visibleApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
	}
	private var pages: [[AppItem]] {
		stride(from: 0, to: filtered.count, by: perPage).map {
			Array(filtered[$0..<min($0 + perPage, filtered.count)])
		}
	}

	var body: some View {
		ZStack {
			VisualEffect().ignoresSafeArea()
			Color.black.opacity(0.15).ignoresSafeArea()
				.onTapGesture { dismiss() }
				.contextMenu {
					Button("Show Hidden Apps") { unhideAll() }
						.disabled(hidden.isEmpty)
				}

			VStack(spacing: 24) {
				searchBar
				pager
				dots
			}
			.padding(.vertical, 40)
			.scaleEffect(appeared ? 1 : 1.1)
		}
		.opacity(appeared ? 1 : 0)
		.environment(\.dismissLaunchpad, { dismiss() })
		.onChange(of: query) { page = 0 }
		.onChange(of: hidden) { go(0) }
		.onAppear {
			searchFocused = true
			installMonitors()
			withAnimation(.easeOut(duration: 0.3)) { appeared = true }
		}
	}

	private var searchBar: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 17, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))
			TextField("Căutare", text: $query)
				.textFieldStyle(.plain)
				.font(.system(size: 18))
				.foregroundStyle(.white)
				.focused($searchFocused)
				.onSubmit {
					if let first = filtered.first {
						first.launch()
						dismiss()
					}
				}
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 12)
		.frame(width: 400)
		.modifier(GlassCapsule())
	}

	private var pager: some View {
		GeometryReader { geo in
			let w = geo.size.width
			HStack(spacing: 0) {
				ForEach(pages.indices, id: \.self) { i in
					PageGrid(items: pages[i], columns: columns, onHide: hide)
						.frame(width: w, height: geo.size.height, alignment: .top)
				}
			}
			.offset(x: -CGFloat(page) * w + drag)
			.animation(.interpolatingSpring(stiffness: 220, damping: 28), value: page)
			.gesture(
				DragGesture()
					.onChanged { drag = $0.translation.width }
					.onEnded { v in
						if v.translation.width < -w * 0.15 { go(1) }
						else if v.translation.width > w * 0.15 { go(-1) }
						withAnimation(.easeOut(duration: 0.25)) { drag = 0 }
					}
			)
		}
		.clipped()
	}

	private var dots: some View {
		HStack(spacing: 10) {
			ForEach(pages.indices, id: \.self) { i in
				Circle()
					.fill(.white.opacity(i == page ? 0.95 : 0.35))
					.frame(width: 8, height: 8)
					.onTapGesture { page = i }
			}
		}
		.frame(height: 12)
	}

	private func dismiss() {
		guard appeared else { return }
		withAnimation(.easeIn(duration: 0.22)) { appeared = false }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { NSApp.terminate(nil) }
	}

	private func go(_ delta: Int) {
		page = min(max(page + delta, 0), max(pages.count - 1, 0))
	}

	private func hide(_ item: AppItem) {
		hidden.insert(item.url.path)
		UserDefaults.standard.set(Array(hidden), forKey: "hiddenApps")
	}

	private func unhideAll() {
		hidden.removeAll()
		UserDefaults.standard.removeObject(forKey: "hiddenApps")
	}

	private func installMonitors() {
		guard !monitorsInstalled else { return }
		monitorsInstalled = true

		NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
			switch e.keyCode {
			case 53:  dismiss(); return nil               // Esc
			case 123: go(-1); return nil                  // ←
			case 124: go(1);  return nil                  // →
			default:  return e
			}
		}

		NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
			if e.momentumPhase != [] { return e }

			let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY

			if e.phase == .mayBegin || e.phase == .began {
				scroll.accumulated = 0
				scroll.consumed = false
			}

			if e.phase != [] {
				if !scroll.consumed, abs(dx) > abs(dy) {
					scroll.accumulated += dx
					if abs(scroll.accumulated) > 60 {
						go(scroll.accumulated < 0 ? 1 : -1)
						scroll.consumed = true
					}
				}
				if e.phase == .ended || e.phase == .cancelled {
					scroll.accumulated = 0
					scroll.consumed = false
				}
			} else if abs(dx) > abs(dy), abs(dx) > 4,
					  Date().timeIntervalSince(scroll.lastWheel) > 0.3 {
				scroll.lastWheel = Date()
				go(dx < 0 ? 1 : -1)
			}
			return e
		}
	}
}

struct PageGrid: View {
	let items: [AppItem]
	let columns: Int
	let onHide: (AppItem) -> Void

	var body: some View {
		LazyVGrid(
			columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columns),
			spacing: 28
		) {
			ForEach(items) { AppTile(item: $0, onHide: onHide) }
		}
		.padding(.horizontal, 140)
		.padding(.top, 20)
		.frame(maxHeight: .infinity, alignment: .top)
	}
}

struct AppTile: View {
	let item: AppItem
	let onHide: (AppItem) -> Void
	@Environment(\.dismissLaunchpad) private var dismiss
	@State private var hovering = false

	var body: some View {
		Button { open() } label: {
			VStack(spacing: 8) {
				Image(nsImage: item.icon)
					.resizable()
					.interpolation(.high)
					.frame(width: 96, height: 96)
					.scaleEffect(hovering ? 1.06 : 1)
					.shadow(color: .black.opacity(0.25), radius: 6, y: 3)
				Text(item.name)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.easeOut(duration: 0.15), value: hovering)
		.contextMenu {
			Button("Open") { open() }
			Button("Show in Finder") {
				item.showInFinder()
				dismiss()
			}
			Button("Get Info") {
				item.getInfo()
				dismiss()
			}
			Divider()
			Button("Hide") { onHide(item) }
		}
	}

	private func open() {
		item.launch()
		dismiss()
	}
}

extension AppItem {
	func showInFinder() {
		NSWorkspace.shared.activateFileViewerSelecting([url])
	}

	func getInfo() {
		let path = url.path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		let source = """
		tell application "Finder"
			activate
			open information window of (POSIX file "\(path)" as alias)
		end tell
		"""
		var error: NSDictionary?
		NSAppleScript(source: source)?.executeAndReturnError(&error)
		if let error { print("Get Info error:", error) }
	}
}

final class ScrollState {
	var accumulated: CGFloat = 0
	var consumed = false
	var lastWheel = Date.distantPast
}

struct GlassCapsule: ViewModifier {
	func body(content: Content) -> some View {
		if #available(macOS 26.0, *) {
			content.glassEffect(.regular.interactive(), in: Capsule())
		} else {
			content.background(.white.opacity(0.15), in: Capsule())
		}
	}
}
