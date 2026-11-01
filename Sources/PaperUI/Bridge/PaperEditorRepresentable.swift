import SwiftUI

#if os(macOS)
struct PaperEditorRepresentable: NSViewControllerRepresentable {
    @Binding var paper: Paper

    func makeNSViewController(context: Context) -> PaperEditorController {
        PaperEditorController(paper: $paper, environment: context.environment)
    }

    func updateNSViewController(_ controller: PaperEditorController, context: Context) {
        controller.update(paper: $paper, environment: context.environment)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: PaperEditorController, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: paper.size.size)
    }
}
#else
struct PaperEditorRepresentable: UIViewControllerRepresentable {
    @Binding var paper: Paper

    func makeUIViewController(context: Context) -> PaperEditorController {
        PaperEditorController(paper: $paper, environment: context.environment)
    }

    func updateUIViewController(_ controller: PaperEditorController, context: Context) {
        controller.update(paper: $paper, environment: context.environment)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: PaperEditorController, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: paper.size.size)
    }
}
#endif
