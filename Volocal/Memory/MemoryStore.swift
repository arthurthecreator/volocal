import Foundation
#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import os
#endif

#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
private let memoryLogger = Logger(subsystem: "com.volocal.app", category: "memory")
#endif

enum MemoryLog {
    static func error(_ message: String) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        memoryLogger.error("\(message, privacy: .public)")
        #else
        FileHandle.standardError.write(Data("memory: \(message)\n".utf8))
        #endif
    }
}

/// JSON file `memory.pbmem` in Application Support.
/// Every change is written immediately with `Data.write(options: .atomic)`.
/// A corrupt file is moved aside to `.bak` and is never replaced by an empty file first.
final class MemoryStore {
    static let fileName = "memory.pbmem"
    static let maxEntries = 40
    static let maxPromptCharacters = 1500
    static let promptHeader = "Ce que tu sais de l'utilisateur :"

    private(set) var entries: [MemoryEntry] = []

    private let fileURL: URL
    private var persistenceAllowed: Bool
    private let fileManager = FileManager.default

    /// `directory` is the folder that contains `memory.pbmem`.
    /// The app passes nothing and uses Application Support, created if needed.
    init(directory: URL? = nil) {
        if let directory {
            fileURL = directory.appendingPathComponent(Self.fileName)
            persistenceAllowed = true
        } else {
            do {
                let support = try Self.applicationSupportDirectory()
                fileURL = support.appendingPathComponent(Self.fileName)
                persistenceAllowed = true
            } catch {
                MemoryLog.error("Failed to open Application Support for memory: \(error.localizedDescription)")
                fileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("volocal-memory-unavailable")
                    .appendingPathComponent(Self.fileName)
                persistenceAllowed = false
                entries = []
                return
            }
        }
        load()
    }

    /// Extracts at most one durable fact from a finalized user turn and writes it now.
    @discardableResult
    func ingest(userUtterance: String) -> Bool {
        guard let draft = MemoryExtractor.extract(from: userUtterance) else { return false }
        upsert(draft)
        return true
    }

    func upsert(_ draft: MemoryDraft, at date: Date = Date()) {
        let text = Self.oneSentence(draft.text)
        guard !text.isEmpty else { return }
        if let index = entries.firstIndex(where: { $0.key == draft.key }) {
            entries[index].text = text
            entries[index].category = draft.category
            entries[index].updatedAt = date
        } else {
            entries.append(MemoryEntry(
                id: UUID(),
                text: text,
                category: draft.category,
                key: draft.key,
                updatedAt: date
            ))
        }
        capEntries()
        save()
    }

    /// Deletes every fact and writes the empty file immediately.
    func wipe() {
        if !persistenceAllowed {
            guard restorePersistenceIfPossible() else {
                MemoryLog.error("Refusing to wipe memory because the existing file could not be moved aside")
                return
            }
        }
        entries = []
        save()
    }

    /// Short block injected into the system prompt. Empty when nothing is known.
    /// Newest facts are kept when the block would pass 1500 characters.
    func promptBlock() -> String {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.key < rhs.key
        }
        var lines: [String] = []
        for entry in sorted {
            let sentence = entry.text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { continue }
            let line = "- \(sentence)"
            let candidate = ([Self.promptHeader] + lines + [line]).joined(separator: "\n")
            if candidate.count <= Self.maxPromptCharacters {
                lines.append(line)
            } else if lines.isEmpty {
                let budget = Self.maxPromptCharacters - Self.promptHeader.count - 3
                guard budget > 1 else { break }
                let shortened = String(sentence.prefix(budget))
                lines.append("- \(shortened)")
                break
            } else {
                break
            }
            if lines.count == Self.maxEntries { break }
        }
        guard !lines.isEmpty else { return "" }
        return ([Self.promptHeader] + lines).joined(separator: "\n")
    }

    static func composeSystemPrompt(base: String, memoryBlock: String) -> String {
        let block = memoryBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty else { return base }
        return base + "\n\n" + block
    }

    // MARK: - Persistence

    private func load() {
        guard persistenceAllowed else {
            entries = []
            return
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }
        // A file that cannot be read (for example before the first unlock) is not corrupt.
        // Leave it in place and refuse to overwrite it.
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            MemoryLog.error("Failed to load memory file: \(error.localizedDescription)")
            entries = []
            persistenceAllowed = false
            return
        }
        do {
            let decoded = try Self.makeDecoder().decode(MemoryFile.self, from: data)
            let normalized = Self.normalize(decoded.entries)
            entries = normalized.entries
            if normalized.didChange {
                save()
            }
        } catch {
            MemoryLog.error("Failed to decode memory file: \(error.localizedDescription)")
            do {
                try quarantineCorruptFile()
                MemoryLog.error("Moved corrupt memory file aside as \(self.fileURL.appendingPathExtension("bak").lastPathComponent)")
                entries = []
                persistenceAllowed = true
            } catch {
                MemoryLog.error("Failed to move corrupt memory file aside: \(error.localizedDescription)")
                entries = []
                persistenceAllowed = false
            }
        }
    }

    private func save() {
        guard persistenceAllowed else {
            MemoryLog.error("Refusing to overwrite a memory file that could not be moved aside")
            return
        }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.makeEncoder().encode(MemoryFile(entries: entries))
            try writeAtomically(data)
        } catch {
            MemoryLog.error("Failed to save memory file: \(error.localizedDescription)")
        }
    }

    /// Atomic replace, with complete-until-first-unlock protection on Apple platforms.
    private func writeAtomically(_ data: Data) throws {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            MemoryLog.error("Failed to set memory file protection: \(error.localizedDescription)")
        }
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    /// Moves `memory.pbmem` to `memory.pbmem.bak`. An existing `.bak` is kept under a stamped name.
    private func quarantineCorruptFile() throws {
        let bakURL = fileURL.appendingPathExtension("bak")
        if fileManager.fileExists(atPath: bakURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            var stamped = fileURL.appendingPathExtension("\(stamp).bak")
            if fileManager.fileExists(atPath: stamped.path) {
                stamped = fileURL.appendingPathExtension("\(stamp)-\(UUID().uuidString).bak")
            }
            try fileManager.moveItem(at: bakURL, to: stamped)
        }
        try fileManager.moveItem(at: fileURL, to: bakURL)
    }

    private func restorePersistenceIfPossible() -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            persistenceAllowed = true
            return true
        }
        do {
            try quarantineCorruptFile()
            persistenceAllowed = true
            return true
        } catch {
            MemoryLog.error("Failed to move memory file aside before wipe: \(error.localizedDescription)")
            return false
        }
    }

    private func capEntries() {
        guard entries.count > Self.maxEntries else { return }
        entries.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.key < rhs.key
        }
        entries.removeFirst(entries.count - Self.maxEntries)
    }

    private struct NormalizeResult {
        var entries: [MemoryEntry]
        var didChange: Bool
    }

    private static func normalize(_ input: [MemoryEntry]) -> NormalizeResult {
        var byKey: [String: MemoryEntry] = [:]
        var order: [String] = []
        var droppedDuplicate = false
        for entry in input {
            let text = oneSentence(entry.text)
            guard !text.isEmpty, !entry.key.isEmpty else {
                droppedDuplicate = true
                continue
            }
            var cleaned = entry
            cleaned.text = text
            if let existing = byKey[entry.key] {
                droppedDuplicate = true
                if cleaned.updatedAt >= existing.updatedAt {
                    byKey[entry.key] = cleaned
                }
            } else {
                byKey[entry.key] = cleaned
                order.append(entry.key)
            }
        }
        var unique = order.compactMap { byKey[$0] }
        let overflow = unique.count > maxEntries
        if overflow {
            unique.sort { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.key < rhs.key
            }
            unique = Array(unique.prefix(maxEntries))
        }
        return NormalizeResult(entries: unique, didChange: droppedDuplicate || overflow)
    }

    private static func oneSentence(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.hasSuffix(".") { return collapsed }
        return collapsed + "."
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601(date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = Self.date(fromISO8601: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid memory date"
                )
            }
            return date
        }
        return decoder
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(fromISO8601 value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private struct MemoryFile: Codable {
    var entries: [MemoryEntry]
}
