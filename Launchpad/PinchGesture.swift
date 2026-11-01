// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// PinchGesture.swift
// Launchpad
//
// Created by Dorneanu Denis on 01/11/2026.
//

import AppKit

private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias CreateListFunction = @convention(c) () -> Unmanaged<CFArray>?
private typealias RegisterFunction = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
private typealias DeviceStartFunction = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias DeviceStopFunction = @convention(c) (UnsafeMutableRawPointer) -> Void

nonisolated final class PinchDetector: @unchecked Sendable {
	static let shared = PinchDetector()

	var onPinch: (@Sendable () -> Void)?

	private var deviceList: CFArray?
	private var devices: [UnsafeMutableRawPointer] = []
	private var callback: ContactCallback?
	private var unregister: RegisterFunction?
	private var stopDevice: DeviceStopFunction?

	private var peakSpread: Float?
	private var fired = false
	private var lastFire = Date.distantPast

	func start() {
		guard devices.isEmpty else { return }

		let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
		guard let library = dlopen(path, RTLD_NOW),
			  let createSymbol = dlsym(library, "MTDeviceCreateList"),
			  let registerSymbol = dlsym(library, "MTRegisterContactFrameCallback"),
			  let unregisterSymbol = dlsym(library, "MTUnregisterContactFrameCallback"),
			  let startSymbol = dlsym(library, "MTDeviceStart"),
			  let stopSymbol = dlsym(library, "MTDeviceStop") else { return }

		let createList = unsafeBitCast(createSymbol, to: CreateListFunction.self)
		let register = unsafeBitCast(registerSymbol, to: RegisterFunction.self)
		let startDevice = unsafeBitCast(startSymbol, to: DeviceStartFunction.self)
		unregister = unsafeBitCast(unregisterSymbol, to: RegisterFunction.self)
		stopDevice = unsafeBitCast(stopSymbol, to: DeviceStopFunction.self)

		guard let list = createList()?.takeRetainedValue() else { return }
		deviceList = list

		let contactCallback: ContactCallback = { _, touches, count, _, _ in
			if let touches {
				PinchDetector.shared.process(touches, count: Int(count))
			}
			return 0
		}
		callback = contactCallback

		for index in 0..<CFArrayGetCount(list) {
			guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
			let device = UnsafeMutableRawPointer(mutating: raw)
			register(device, contactCallback)
			startDevice(device, 0)
			devices.append(device)
		}
	}

	func stop() {
		if let callback, let unregister, let stopDevice {
			for device in devices {
				unregister(device, callback)
				stopDevice(device)
			}
		}
		devices = []
		deviceList = nil
		callback = nil
		peakSpread = nil
		fired = false
	}

	fileprivate func process(_ touches: UnsafeMutableRawPointer, count: Int) {
		guard count >= 4, count <= 5 else {
			if count < 3 {
				peakSpread = nil
				fired = false
			}
			return
		}

		var xs: [Float] = []
		var ys: [Float] = []
		for index in 0..<count {
			let base = touches + index * 96
			xs.append(base.load(fromByteOffset: 32, as: Float.self))
			ys.append(base.load(fromByteOffset: 36, as: Float.self))
		}

		let centerX = xs.reduce(0, +) / Float(count)
		let centerY = ys.reduce(0, +) / Float(count)
		var total: Float = 0
		for index in 0..<count {
			total += hypotf(xs[index] - centerX, ys[index] - centerY)
		}
		let spread = total / Float(count)

		guard let peak = peakSpread else {
			peakSpread = spread
			return
		}

		if spread > peak {
			peakSpread = spread
			return
		}

		if !fired, peak > 0.12, spread < peak * 0.65, Date().timeIntervalSince(lastFire) > 1 {
			fired = true
			lastFire = Date()
			let handler = onPinch
			DispatchQueue.main.async { handler?() }
		}
	}
}
