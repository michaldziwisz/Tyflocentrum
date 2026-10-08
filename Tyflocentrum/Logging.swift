//
//  Logging.swift
//  Tyflocentrum
//

import Foundation
import os

enum AppLog {
	private static var subsystem: String {
		Bundle.main.bundleIdentifier ?? "Tyflocentrum"
	}

	static let network = Logger(subsystem: subsystem, category: "network")
	static let persistence = Logger(subsystem: subsystem, category: "persistence")
	static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
	static let uiTests = Logger(subsystem: subsystem, category: "ui-tests")
	// Parsowanie treści z serwisów (notatki audycji, znaczniki czasu, odnośniki).
	// Nie logujemy tu treści wiadomości ani głosówek - tylko fakty techniczne.
	static let parsing = Logger(subsystem: subsystem, category: "parsing")
}

// TYFLO-CAT-DIAG: wyłącznie pomiar na osobnej gałęzi, bez zmiany przepływu.
enum CategoryLoadTrace {
	private static let lock = NSLock()
	private static let enabled = ProcessInfo.processInfo.arguments.contains("UI_TESTING")
		&& ProcessInfo.processInfo.arguments.contains("UI_TESTING_CATEGORY_TRACE")

	static func emit(_ event: String, _ detail: @autoclosure () -> String = "") {
		#if DEBUG
			guard enabled else { return }
			let object: [String: Any] = [
				"event": event, "detail": detail(),
				"uptime": ProcessInfo.processInfo.systemUptime,
				"pid": ProcessInfo.processInfo.processIdentifier,
				"mainThread": Thread.isMainThread,
			]
			guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
			      let text = String(data: data, encoding: .utf8) else { return }
			lock.lock()
			defer { lock.unlock() }
			NSLog("TYFLO-CAT-DIAG %@", text)
			guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
			let url = directory.appendingPathComponent("category-load.jsonl")
			do {
				let line = Data((text + "\n").utf8)
				if !FileManager.default.fileExists(atPath: url.path) {
					try line.write(to: url)
				} else {
					let handle = try FileHandle(forWritingTo: url)
					defer { try? handle.close() }
					try handle.seekToEnd()
					try handle.write(contentsOf: line)
				}
			} catch {
				NSLog("TYFLO-CAT-DIAG zapis śladu: %@", String(describing: error))
			}
		#endif
	}

	static func describe(_ error: Error) -> String {
		let nsError = error as NSError
		let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
		return "type=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) underlying=\(String(describing: underlying))"
	}
}
