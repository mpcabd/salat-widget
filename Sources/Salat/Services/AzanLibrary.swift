import AVFoundation
import Foundation

/// An audio file the user added. The file is copied into the library folder, so it keeps
/// working if the original moves or is deleted.
struct UserAzan: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// File name inside the library folder.
    var fileName: String
    /// A Fajr azan: offered only for Fajr, like bundled Fajr recordings.
    var isFajr = false
}

/// Imports, locates and removes the user's own azan recordings.
struct AzanLibrary {
    static let shared = AzanLibrary(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Salat/Azans", isDirectory: true))

    static let idPrefix = "user."

    let directory: URL

    enum ImportError: Error {
        case notPlayable
    }

    func url(for azan: UserAzan) -> URL {
        directory.appendingPathComponent(azan.fileName)
    }

    /// Copies a local audio file into the library. Rejects files AVFoundation can't play.
    func importFile(at source: URL) throws -> UserAzan {
        guard let player = try? AVAudioPlayer(contentsOf: source), player.duration > 0 else {
            throw ImportError.notPlayable
        }
        let uuid = UUID().uuidString.lowercased()
        let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension.lowercased()
        let fileName = uuid + ext
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(fileName))
        return UserAzan(id: Self.idPrefix + uuid, name: source.deletingPathExtension().lastPathComponent,
                        fileName: fileName)
    }

    func remove(_ azan: UserAzan) {
        try? FileManager.default.removeItem(at: url(for: azan))
    }
}
