import XCTest
@testable import Volocal

final class MemoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("volocal-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripUpdatesSameKeyAndWritesImmediately() throws {
        let store = MemoryStore(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertFalse(store.ingest(userUtterance: "salut ça va"))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertTrue(store.ingest(userUtterance: "my name is Ada"))
        XCTAssertEqual(store.entries.count, 1)
        let firstID = try XCTUnwrap(store.entries.first).id
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let onDisk = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: onDisk) as? [String: Any])
        let rows = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows[0]["id"])
        XCTAssertNotNil(rows[0]["text"])
        XCTAssertEqual(rows[0]["category"] as? String, "name")
        XCTAssertEqual(rows[0]["key"] as? String, "name")
        XCTAssertNotNil(rows[0]["updatedAt"])

        XCTAssertTrue(store.ingest(userUtterance: "je m'appelle Camille"))
        XCTAssertTrue(store.ingest(userUtterance: "j'habite à Lyon"))
        XCTAssertEqual(store.entries.count, 2)
        let name = try XCTUnwrap(store.entries.first { $0.key == "name" })
        XCTAssertEqual(name.id, firstID)
        XCTAssertTrue(name.text.contains("Camille"))

        let reloaded = MemoryStore(directory: directory)
        XCTAssertEqual(reloaded.entries.count, 2)
        let reloadedName = try XCTUnwrap(reloaded.entries.first { $0.key == "name" })
        XCTAssertEqual(reloadedName.id, firstID)
        XCTAssertEqual(reloadedName.text, name.text)
        XCTAssertEqual(reloadedName.category, name.category)
        XCTAssertEqual(reloadedName.key, name.key)
        XCTAssertEqual(
            reloadedName.updatedAt.timeIntervalSince1970,
            name.updatedAt.timeIntervalSince1970,
            accuracy: 1
        )
        let home = try XCTUnwrap(reloaded.entries.first { $0.key == "home" })
        XCTAssertTrue(home.text.contains("Lyon"))
    }

    func testPromptBlockCapsEntriesAndCharacters() {
        let store = MemoryStore(directory: directory)
        XCTAssertEqual(MemoryStore.maxEntries, 40)
        XCTAssertEqual(MemoryStore.maxPromptCharacters, 1500)
        XCTAssertEqual(store.promptBlock(), "")

        store.ingest(userUtterance: "my name is Ada")
        let block = store.promptBlock()
        XCTAssertTrue(block.hasPrefix("Ce que tu sais de l'utilisateur :"))
        XCTAssertTrue(block.contains("Ada"))
        XCTAssertLessThanOrEqual(block.count, 1500)

        let base = "You are Volocal."
        XCTAssertEqual(MemoryStore.composeSystemPrompt(base: base, memoryBlock: ""), base)
        XCTAssertEqual(
            MemoryStore.composeSystemPrompt(base: base, memoryBlock: block),
            base + "\n\n" + block
        )

        for index in 0..<41 {
            store.upsert(
                MemoryDraft(category: "project", key: "project.p\(index)", text: "The user is working on P\(index)."),
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        XCTAssertEqual(store.entries.count, 40)
        XCTAssertNil(store.entries.first { $0.key == "project.p0" })
        XCTAssertNotNil(store.entries.first { $0.key == "project.p40" })

        let longStore = MemoryStore(directory: directory)
        for index in 0..<12 {
            longStore.upsert(
                MemoryDraft(
                    category: "project",
                    key: "project.long\(index)",
                    text: "Fact \(index) " + String(repeating: "x", count: 300) + "."
                ),
                at: Date(timeIntervalSince1970: TimeInterval(100 + index))
            )
        }
        let longBlock = longStore.promptBlock()
        XCTAssertLessThanOrEqual(longBlock.count, 1500)
        XCTAssertTrue(longBlock.hasPrefix("Ce que tu sais de l'utilisateur :"))
        XCTAssertTrue(longBlock.contains("Fact 11"))
        XCTAssertFalse(longBlock.contains("Fact 0"))
    }

    func testCorruptFileIsMovedAsideAndNotReplacedWithEmpty() throws {
        let original = Data("{not json".utf8)
        try original.write(to: fileURL)

        let store = MemoryStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let bak = fileURL.appendingPathExtension("bak")
        XCTAssertEqual(try Data(contentsOf: bak), original)

        let second = MemoryStore(directory: directory)
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: bak), original)

        XCTAssertTrue(second.ingest(userUtterance: "my name is Ada"))
        XCTAssertEqual(try Data(contentsOf: bak), original)
        let saved = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(saved, Data())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual((json["entries"] as? [[String: Any]])?.count, 1)
    }

    func testSecondCorruptFileKeepsThePreviousBackup() throws {
        let bak = fileURL.appendingPathExtension("bak")
        try Data("first".utf8).write(to: bak)
        try Data("second".utf8).write(to: fileURL)

        _ = MemoryStore(directory: directory)

        XCTAssertEqual(try Data(contentsOf: bak), Data("second".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let extras = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".bak") && $0.lastPathComponent != "memory.pbmem.bak" }
        XCTAssertEqual(extras.count, 1)
        XCTAssertEqual(try Data(contentsOf: extras[0]), Data("first".utf8))
    }

    func testDoesNotOverwriteCorruptFileWhenQuarantineFails() throws {
        let original = Data("still-corrupt".utf8)
        try original.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }

        let store = MemoryStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), original)

        store.ingest(userUtterance: "my name is Ada")
        store.wipe()
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testUnreadableFileIsLeftInPlace() throws {
        let original = Data("protected".utf8)
        try original.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }

        let store = MemoryStore(directory: directory)
        store.ingest(userUtterance: "my name is Ada")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("bak").path))
    }

    func testWipeWritesEmptyFileImmediately() throws {
        let store = MemoryStore(directory: directory)
        XCTAssertTrue(store.ingest(userUtterance: "me llamo Lucía"))
        store.wipe()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.promptBlock(), "")

        let reloaded = MemoryStore(directory: directory)
        XCTAssertTrue(reloaded.entries.isEmpty)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let rows = try XCTUnwrap(json["entries"] as? [Any])
        XCTAssertTrue(rows.isEmpty)
    }

    func testFileProtectionUntilFirstUnlock() throws {
        #if os(iOS) || os(macOS)
        let store = MemoryStore(directory: directory)
        XCTAssertTrue(store.ingest(userUtterance: "my name is Ada"))
        let values = try fileURL.resourceValues(forKeys: [.fileProtectionKey])
        XCTAssertEqual(values.fileProtection, .completeUntilFirstUserAuthentication)
        #else
        throw XCTSkip("File protection is enforced on Apple platforms")
        #endif
    }

    private var fileURL: URL {
        directory.appendingPathComponent(MemoryStore.fileName)
    }
}
