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
///
/// `init(paper:)` shows the background stored in the paper. The `on:` forms show a background the
/// app manages itself, such as pages of a large shared PDF, and take precedence over a stored one.
public struct PaperEditor<Background: View>: View {
    @Binding private var paper: Paper
    private let source: EditorBackground

    /// An editor over any SwiftUI view, framed to the page.
    public init(paper: Binding<Paper>, @ViewBuilder on background: () -> Background) {
        self._paper = paper
        self.source = .view(AnyView(background()))
    }

    private init(paper: Binding<Paper>, source: EditorBackground) {
        self._paper = paper
        self.source = source
    }

    public var body: some View {
        PaperEditorRepresentable(paper: $paper, background: source)
    }
}

extension PaperEditor where Background == PaperBackgroundView {
    /// An editor showing the background stored in the paper, if any.
    public init(paper: Binding<Paper>) {
        self.init(paper: paper, source: .stored)
    }
}

extension PaperEditor where Background == Image {
    /// An editor over an image stretched to the page.
    public init(paper: Binding<Paper>, on image: Image) {
        self.init(paper: paper, source: .view(AnyView(image.resizable())))
    }
}

extension PaperEditor where Background == PDFPageView {
    /// An editor over a PDF page, drawn sharp at every zoom.
    public init(paper: Binding<Paper>, on page: PDFPage) {
        self.init(paper: paper, source: .pdfPage(page))
    }
}

/// Where the editor's background comes from.
enum EditorBackground {
    case stored
    case pdfPage(PDFPage)
    case view(AnyView)
}
