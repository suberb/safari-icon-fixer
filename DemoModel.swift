import Foundation

// In-memory only. The demo model has no Cache, file-system, network or preference dependency.
struct DemoSample: Identifiable, Equatable {
    let id: Int
    let name: String
    let initiallyMissing: Bool
    static let all = [
        DemoSample(id: 0, name: "Forma", initiallyMissing: true),
        DemoSample(id: 1, name: "Orbit", initiallyMissing: false),
        DemoSample(id: 2, name: "Tempo", initiallyMissing: false),
        DemoSample(id: 3, name: "Atlas", initiallyMissing: true),
        DemoSample(id: 4, name: "Bloom", initiallyMissing: false),
        DemoSample(id: 5, name: "Studio", initiallyMissing: false),
        DemoSample(id: 6, name: "North", initiallyMissing: true),
        DemoSample(id: 7, name: "Daylight", initiallyMissing: false)
    ]
}
struct DemoEdit: Equatable { let png: Data; let style: SafariIconDisplay? }
struct DemoSession {
    private(set) var saved: [Int: DemoEdit] = [:]
    private(set) var staged: [Int: DemoEdit] = [:]
    func current(_ id: Int) -> DemoEdit? { staged[id] ?? saved[id] }
    func missing(_ sample: DemoSample) -> Bool { sample.initiallyMissing && current(sample.id) == nil }
    mutating func edit(_ id: Int, _ value: DemoEdit) {
        guard DemoSample.all.contains(where: { $0.id == id }), !value.png.isEmpty else { return }
        staged[id] = value
    }
    mutating func apply() { saved.merge(staged) { _, new in new }; staged.removeAll() }
    mutating func discard() { staged.removeAll() }
    mutating func reset() { saved.removeAll(); staged.removeAll() }
}
