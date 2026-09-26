/// View helpers for adopting newer design-system APIs (e.g. Liquid Glass) behind
/// an availability check, so call sites stay free of `#available` boilerplate.

import SwiftUI

extension View {
    /// Applies `transform` (e.g. a Liquid Glass `.glassEffect`) only on iOS 26+,
    /// returning the view unchanged on earlier OS versions so callers can adopt
    /// new design-system APIs without scattering `#available` checks.
    @ViewBuilder
    func ifAvailableiOS26<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 26, *) {
            transform(self)
        } else {
            self
        }
    }
}
