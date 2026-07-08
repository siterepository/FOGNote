import Foundation
import CryptoKit
import AppKit

/// Encrypted local backup: zips the whole FOGNote data folder (notes DB +
/// recordings) and seals it with AES-GCM derived from a password.
/// File format: .fogbackup = AES-GCM(combined) over a zip archive.
@MainActor
enum BackupService {
    static var dataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "FOGNote", directoryHint: .isDirectory)
    }

    private static func key(from password: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(("fognote-backup:" + password).utf8)))
    }

    static func backUp(to destination: URL, password: String) throws {
        let zipURL = FileManager.default.temporaryDirectory
            .appending(path: "fognote-backup-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try runDitto(["-c", "-k", "--sequesterRsrc", dataDirectory.path, zipURL.path])

        let zipData = try Data(contentsOf: zipURL)
        let sealed = try AES.GCM.seal(zipData, using: key(from: password))
        guard let combined = sealed.combined else {
            throw NSError(domain: "FOGNote", code: 7, userInfo: [NSLocalizedDescriptionKey: "Encryption failed."])
        }
        try combined.write(to: destination)
    }

    /// Restores over the live data folder, then relaunches the app.
    static func restore(from backup: URL, password: String) throws {
        let combined = try Data(contentsOf: backup)
        let box = try AES.GCM.SealedBox(combined: combined)
        let zipData: Data
        do {
            zipData = try AES.GCM.open(box, using: key(from: password))
        } catch {
            throw NSError(domain: "FOGNote", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Wrong password or corrupted backup file."
            ])
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appending(path: "fognote-restore-\(UUID().uuidString).zip")
        let unpackDir = FileManager.default.temporaryDirectory
            .appending(path: "fognote-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: zipURL)
            try? FileManager.default.removeItem(at: unpackDir)
        }
        try zipData.write(to: zipURL)
        try runDitto(["-x", "-k", zipURL.path, unpackDir.path])

        guard let restoredRoot = try FileManager.default
            .contentsOfDirectory(at: unpackDir, includingPropertiesForKeys: nil)
            .first(where: { $0.hasDirectoryPath }) else {
            throw NSError(domain: "FOGNote", code: 9, userInfo: [NSLocalizedDescriptionKey: "Backup archive is empty."])
        }

        // Keep the current data as a safety copy next to the store.
        let safety = dataDirectory.deletingLastPathComponent()
            .appending(path: "FOGNote-pre-restore-\(Int(Date.now.timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: dataDirectory, to: safety)
        try FileManager.default.moveItem(at: restoredRoot, to: dataDirectory)

        relaunch()
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FOGNote", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Archive operation failed (ditto exit \(process.terminationStatus))."
            ])
        }
    }

    private static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open \"\(bundleURL.path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
