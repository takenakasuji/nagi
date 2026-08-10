import Foundation
import Testing
@testable import NagiCore

@Suite("StashStore")
struct StashStoreTests {
    /// A store pointed at a throwaway state file.
    private func withStore<T>(_ body: (StashStore) throws -> T) throws -> T {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StashStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StashStore(fileURL: dir.appendingPathComponent("state.json"))
        return try body(store)
    }

    @Test("状態ファイルが無ければ空の状態を返す")
    func loadsEmptyStateWhenFileMissing() throws {
        try withStore { store in
            let state = store.load()
            #expect(state.activeDraft == nil)
            #expect(state.stashes.isEmpty)
        }
    }

    @Test("保存した状態を読み戻せる（ラウンドトリップ）")
    func roundTripsState() throws {
        try withStore { store in
            let active = Draft(filename: "いまの下書き", body: "本文A")
            let stashed = Draft(filename: "退避", body: "本文B")
            try store.save(NagiState(activeDraft: active, stashes: [stashed]))

            let loaded = store.load()
            #expect(loaded.activeDraft?.id == active.id)
            #expect(loaded.activeDraft?.filename == "いまの下書き")
            #expect(loaded.activeDraft?.body == "本文A")
            #expect(loaded.stashes.count == 1)
            #expect(loaded.stashes.first?.id == stashed.id)
            #expect(loaded.stashes.first?.body == "本文B")
        }
    }

    @Test("親ディレクトリが無くても保存できる")
    func createsParentDirectoryOnSave() throws {
        try withStore { store in
            try store.save(NagiState(activeDraft: Draft(body: "x"), stashes: []))
            #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        }
    }

    @Test("アクティブ下書きを nil で保存すると消える")
    func clearsActiveDraft() throws {
        try withStore { store in
            try store.save(NagiState(activeDraft: Draft(body: "残る?"), stashes: []))
            try store.save(NagiState(activeDraft: nil, stashes: []))

            #expect(store.load().activeDraft == nil)
        }
    }

    @Test("壊れた JSON は空の状態として扱い、クラッシュしない")
    func toleratesCorruptFile() throws {
        try withStore { store in
            try FileManager.default.createDirectory(
                at: store.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "{ this is not json".write(to: store.fileURL, atomically: true, encoding: .utf8)

            let state = store.load()
            #expect(state.activeDraft == nil)
            #expect(state.stashes.isEmpty)
        }
    }

    @Test("スタッシュの順序を保つ")
    func preservesStashOrder() throws {
        try withStore { store in
            let a = Draft(body: "1つ目")
            let b = Draft(body: "2つ目")
            let c = Draft(body: "3つ目")
            try store.save(NagiState(activeDraft: nil, stashes: [a, b, c]))

            #expect(store.load().stashes.map(\.body) == ["1つ目", "2つ目", "3つ目"])
        }
    }
}
