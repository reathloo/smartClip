import Foundation

/// Keyboard selection rules shared by the history view and regression tests.
enum HistoryNavigation {
    static func selected(in ids: [UUID], explicit: UUID?, search: String) -> UUID? {
        if let explicit { return ids.contains(explicit) ? explicit : nil }
        return search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ids.first : nil
    }

    static func moved(in ids: [UUID], explicit: UUID?, search: String, offset: Int) -> UUID? {
        guard !ids.isEmpty else { return nil }
        if let current = selected(in: ids, explicit: explicit, search: search),
           let index = ids.firstIndex(of: current) {
            return ids[min(max(0, index + offset), ids.count - 1)]
        }
        return offset > 0 ? ids.first : ids.last
    }
}
