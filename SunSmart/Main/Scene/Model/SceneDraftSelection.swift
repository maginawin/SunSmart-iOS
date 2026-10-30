import Foundation

/// The entry point, not the number of members, determines whether control is allowed.
enum SceneDeviceSettingsTarget {
    case device(TimedSchedulerNodeIdentity)
    case category([TimedSchedulerNodeIdentity])

    var identities: [TimedSchedulerNodeIdentity] {
        switch self {
        case .device(let identity): return [identity]
        case .category(let identities): return identities
        }
    }
    var liveIdentity: TimedSchedulerNodeIdentity? {
        guard case .device(let identity) = self else { return nil }
        return identity
    }
}

/// Editing ownership shared by selection rows, category actions and parameter sheets.
/// It contains no transport or persistence; the coordinator alone owns saving.
final class SceneDraftSelection {
    struct Candidate {
        let identity: TimedSchedulerNodeIdentity
        let name: String
        let category: String
        let categoryID: UInt16
        let canAdd: Bool
        let defaults: SceneParameters
    }
    let filter = DeviceNameFilterSession()
    private(set) var draft: SceneDraft
    private let initialDraft: SceneDraft
    private var parameterEdit: UUID?
    private var removedParameters: [TimedSchedulerNodeIdentity: SceneParameters] = [:]
    init(draft: SceneDraft) { self.draft = draft; initialDraft = draft }
    /// Compare saved content, not edit revisions or the progress of existing sync tasks.
    var hasUnsavedChanges: Bool {
        draft.number == nil
            || draft.kind != initialDraft.kind
            || draft.name != initialDraft.name
            || draft.imageId != initialDraft.imageId
            || draft.groupParameters != initialDraft.groupParameters
            || draft.deviceMembers != initialDraft.deviceMembers
    }
    var canFinishDeviceSelection: Bool { draft.number != nil || !draft.deviceMembers.isEmpty }
    func filtered(_ candidates: [Candidate]) -> [Candidate] {
        filter.filtered(candidates.filter { $0.canAdd || isSelected($0.identity) || isExisting($0.identity) }, names: { [$0.name, $0.category] })
    }
    /// Display eligibility is deliberately separate from permission to add a member.
    /// Callers supply scene-capable nodes plus retained members, including offline rows.
    func displayed(_ candidates: [Candidate]) -> [Candidate] {
        filter.filtered(candidates, names: { [$0.name, $0.category] })
    }
    func isExisting(_ identity: TimedSchedulerNodeIdentity) -> Bool { draft.sourceConfiguration?.deviceMembers.contains { $0.identity == identity } == true }
    func isSelected(_ identity: TimedSchedulerNodeIdentity) -> Bool { draft.deviceMembers.contains { $0.identity == identity } }
    func setSelected(_ candidate: Candidate, selected: Bool) throws {
        var members = draft.deviceMembers
        if selected {
            guard candidate.canAdd || isExisting(candidate.identity), !isSelected(candidate.identity) else { return }
            let previous = removedParameters[candidate.identity]
                ?? draft.sourceConfiguration?.deviceMembers.first(where: { $0.identity == candidate.identity })?.parameters
            members.append(.init(identity: candidate.identity, parameters: previous ?? candidate.defaults))
        } else {
            removedParameters[candidate.identity] = members.first { $0.identity == candidate.identity }?.parameters
            members.removeAll { $0.identity == candidate.identity }
        }
        try draft.setDeviceMembers(members); invalidateParameterEdit()
    }
    func visibleCategoryIDs(_ names: [UInt16: String], candidates: [Candidate], selecting: Bool) -> [UInt16] {
        let visible = displayed(candidates).filter { selecting || isSelected($0.identity) }
        var ids = Set(visible.map(\.categoryID))
        if selecting { ids.formUnion(names.filter { filter.matches($0.value) }.map(\.key)) }
        return ids.sorted()
    }
    func removeMembers(_ identities: Set<TimedSchedulerNodeIdentity>, confirmed: Bool) throws {
        guard confirmed else { return }
        for member in draft.deviceMembers where identities.contains(member.identity) { removedParameters[member.identity] = member.parameters }
        try draft.setDeviceMembers(draft.deviceMembers.filter { !identities.contains($0.identity) })
        invalidateParameterEdit()
    }
    func selectFiltered(_ candidates: [Candidate], selected: Bool) throws {
        for candidate in filtered(candidates) { try setSelected(candidate, selected: selected) }
    }
    func switchKind(to kind: SceneKind, confirmed: Bool) throws {
        guard confirmed else { return }
        try draft.switchKind(to: kind); removedParameters = [:]; invalidateParameterEdit()
    }
    func setGroupParameters(_ parameters: [UInt16: SceneParameters]) throws {
        try draft.setGroupParameters(parameters); invalidateParameterEdit()
    }
    func apply(_ parameters: SceneParameters, identities: Set<TimedSchedulerNodeIdentity>,
               resolve: (TimedSchedulerNodeIdentity, SceneParameters) -> SceneParameters = { _, value in value }) throws {
        try draft.setDeviceMembers(draft.deviceMembers.map { member in
            guard identities.contains(member.identity) else { return member }
            return .init(identity: member.identity, parameters: resolve(member.identity, parameters))
        })
        invalidateParameterEdit()
    }
    func beginParameterEdit() -> UUID { let token = UUID(); parameterEdit = token; return token }
    func invalidateParameterEdit() { parameterEdit = nil }
    func finishParameterEdit(_ token: UUID, parameters: SceneParameters, identities: Set<TimedSchedulerNodeIdentity>, apply: Bool,
                             resolve: (TimedSchedulerNodeIdentity, SceneParameters) -> SceneParameters = { _, value in value }) throws {
        guard parameterEdit == token else { return }
        parameterEdit = nil
        if apply { try self.apply(parameters, identities: identities, resolve: resolve) }
    }
}

/// Ephemeral feedback for one draft and one preview attempt, never a saved scene status.
struct SceneDevicePreviewState {
    enum Phase: Equatable {
        case recommended, preparing, applying, applied
        case incomplete(successful: Int, failed: Int, offline: Int)
        case interrupted
    }
    private(set) var phase: Phase = .recommended
    private(set) var revision: UUID?
    private(set) var attempt: UUID?
    var isRunning: Bool { attempt != nil }

    @discardableResult
    mutating func update(revision: UUID) -> Bool {
        guard self.revision != revision else { return false }
        self.revision = revision; phase = .recommended; attempt = nil
        return true
    }
    mutating func invalidate() { phase = .recommended; attempt = nil }
    @discardableResult
    mutating func begin(revision: UUID) -> UUID {
        update(revision: revision)
        let token = UUID(); attempt = token; phase = .preparing
        return token
    }
    mutating func sending() { if isRunning { phase = .applying } }
    @discardableResult
    mutating func complete(attempt: UUID, revision: UUID, successful: Int, failed: Int, offline: Int) -> Bool {
        guard self.attempt == attempt, self.revision == revision else { return false }
        self.attempt = nil
        phase = successful > 0 && failed == 0 && offline == 0 ? .applied
            : .incomplete(successful: successful, failed: failed, offline: offline)
        return true
    }
    mutating func interrupt() {
        guard isRunning else { return }
        attempt = nil; phase = .interrupted
    }
}
