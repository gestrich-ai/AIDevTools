import SwiftUI

public extension View {
    func diffListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}
