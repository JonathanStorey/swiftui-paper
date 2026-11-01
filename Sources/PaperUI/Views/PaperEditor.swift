import PDFKit
import SwiftUI

/// An editable sheet of paper, bound to a `Paper` value the app owns.
///
/// ```swift
/// PaperEditor(paper: $paper)
///     .paperTool($tool)
///     .paperToolPicker(isPresented: $showPicker)
///     .paperContentMode(.fitWidth, anchor: .top)
/// ```
///
/// The editor fills the space offered. Its ideal size is the paper size. Drawing and editing are
/// undoable through `\.undoManager`. Use `.disabled(true)` for a read-only, zoomable page.
public struct PaperEditor<Background: View>: View {
    @Binding private var paper: Paper
    private let background: Background

    public init(paper: Binding<Paper>, @ViewBuilder on background: () -> Background) {
        self._paper = paper
        self.background = background()
    }

    public var body: some View {
        PaperEditorRepresentable(paper: $paper)
    }
}

extension PaperEditor where Background == PaperBackgroundView {
    /// An editor showing the background stored in the paper, if any.
    public init(paper: Binding<Paper>) {
        self.init(paper: paper) { PaperBackgroundView() }
    }
}

/// The background a `Paper` stores. Drawn by the editor behind its elements.
public struct PaperBackgroundView: View {
    init() {}

    public var body: some View {
        // Phase 2 renders `Paper.background` through the editor's `contentView`.
        EmptyView()
    }
}
