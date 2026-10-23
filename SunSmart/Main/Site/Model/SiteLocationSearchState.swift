import Foundation

/// Confirmed identity and transient query are independent. Tickets reject late A→B→A results.
struct SiteLocationSearchState {
    struct Ticket: Equatable { let generation: UInt64; let context: String; let query: String }
    private(set) var selectedID: String?
    private(set) var isExpanded = false
    private(set) var query = ""
    private(set) var context: String
    private var generation: UInt64 = 0

    init(selectedID: String? = nil, context: String) { self.selectedID = selectedID; self.context = context }
    var ticket: Ticket { Ticket(generation: generation, context: context, query: query) }

    mutating func beginSearch() {
        guard !isExpanded else { return }
        generation &+= 1; isExpanded = true; query = ""
    }

    mutating func updateQuery(_ text: String, isComposing: Bool) {
        guard isExpanded, !isComposing else { return }
        generation &+= 1; query = text
    }

    func accepts(_ ticket: Ticket) -> Bool { isExpanded && ticket == self.ticket }

    mutating func select(id: String) {
        guard isExpanded else { return }
        selectedID = id
        dismiss()
    }

    mutating func dismiss() { generation &+= 1; isExpanded = false; query = "" }

    mutating func replaceSelection(id: String?, context: String) {
        dismiss(); selectedID = id; self.context = context
    }
}
