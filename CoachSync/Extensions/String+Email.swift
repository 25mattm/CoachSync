/// Guardian-email validation shared by the athlete forms and CSV import.
import Foundation

extension String {
    /// True when this text (already trimmed) is shaped like an address the backend's `@Email`
    /// constraint accepts: one "@", a local part and domain made of the characters it allows, and
    /// no leading, trailing, or doubled dots. A domain without a dot ("user@gmail") is accepted, as
    /// it is on the backend. An address that fails here would be rejected on every sync push,
    /// leaving the athlete — and everything recorded for them — permanently unsynced.
    var isPlausibleEmail: Bool {
        let parts = split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty, local.count <= 64, !domain.isEmpty, domain.count <= 255 else { return false }

        let localSymbols = Set("!#$%&'*+/=?^_`{|}~-.")
        let localOK = local.allSatisfy { $0.isLetter || $0.isNumber || localSymbols.contains($0) }
        let domainOK = domain.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
        guard localOK, domainOK else { return false }

        for part in [local, domain] where part.hasPrefix(".") || part.hasSuffix(".") || part.contains("..") {
            return false
        }
        return domain.split(separator: ".").allSatisfy { !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }
}
