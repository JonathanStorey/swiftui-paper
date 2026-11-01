import PaperKit
import PencilKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Selection, scrolling, geometry, input, ruler, adornments, the insertion menu, the picker
/// accessory, and borrowed SwiftUI environment (PLAN 3.1–3.4).
extension PaperEditorController {
    func updateInteraction() {
        pushSelectionIfNeeded()
        performScrollRequestIfNeeded()
        applyInput()
        applyBorrowedEnvironment()
        pushAdornmentsIfNeeded()
        #if !os(macOS)
        markupController.isRulerActive = environment.paperRulerActive
        updateInsertionMenu()
        updateToolPickerAccessory()
        #endif
    }

    // MARK: Selection

    /// The controller's selection as element IDs, locked elements removed.
    ///
    /// Lasso selections of strokes show up in `selectedMarkup` but not in `selection`
    /// (SDK-FINDINGS E.5), so both are read.
    private var currentSelection: Paper.Selection {
        var ids = markupController.selection
        ids.formUnion(markupController.selectedMarkup.subelements.ids)
        let unlocked: [Paper.Element.ID] = ids.compactMap { isLocked($0) ? nil : Paper.Element.ID($0) }
        return Paper.Selection(unlocked)
    }

    func selectionDidChange() {
        let selection = currentSelection
        guard selection != lastSelection else { return }
        lastSelection = selection
        if let binding = environment.paperSelection, binding.wrappedValue != selection {
            binding.wrappedValue = selection
        }
        let handlers = environment.paperEvents.selection
        if !handlers.isEmpty {
            let content = Paper(markup: markupController.selectedMarkup)
            for handler in handlers { handler(selection, content) }
        }
        debugLog("selection:", selection.ids.count, "element(s)")
    }

    private func pushSelectionIfNeeded() {
        guard let binding = environment.paperSelection else { return }
        let wanted = binding.wrappedValue
        guard wanted != lastSelection else { return }
        let unlocked: [MarkupOrderedSet.ElementID] = wanted.ids.compactMap { isLocked($0.raw) ? nil : $0.raw }
        markupController.selection = Set(unlocked)
        lastSelection = currentSelection
        // Locked or missing IDs are dropped; write back what the editor actually selected.
        if lastSelection != wanted {
            DispatchQueue.main.async { [weak self] in
                guard let self, let binding = self.environment.paperSelection else { return }
                binding.wrappedValue = self.lastSelection
            }
        }
        debugLog("pushed selection:", unlocked.count, "→ editor has", lastSelection.ids.count)
    }

    // MARK: Scroll position and geometry

    private func performScrollRequestIfNeeded() {
        guard let request = environment.paperScrollPosition?.wrappedValue.request,
              request.id != handledScrollRequest,
              lastLayoutSize.width > 0
        else { return }
        handledScrollRequest = request.id
        let animated = !environment.accessibilityReduceMotion
        let visible = markupController.contentVisibleFrame

        let target: CGRect
        switch request.target {
        case .fit:
            userHasAdjustedView = false
            applyPlacement(previousViewSize: lastLayoutSize)
            return
        case .rect(let rect, let anchor, let zoom):
            target = zoom ? rect : Self.rect(keepingSizeOf: visible, aligning: rect, anchor: anchor ?? .center)
        case .match(let match):
            target = Self.rect(keepingSizeOf: visible, aligning: match.bounds, anchor: .center)
        case .selection(let selection):
            let frames = paper.wrappedValue.elements.filter { selection.ids.contains($0.id) }.map(\.frame)
            guard let union = frames.first.map({ frames.dropFirst().reduce($0) { $0.union($1) } }) else { return }
            target = union.insetBy(dx: -24, dy: -24)
        }
        userHasAdjustedView = true
        markupController.setContentVisibleFrame(target, animated: animated)
        debugLog("scroll request", request.target, "→", target, "got:", markupController.contentVisibleFrame)
    }

    /// A rect the size of `visible` that puts `rect`'s anchor point at the same point of the view.
    static func rect(keepingSizeOf visible: CGRect, aligning rect: CGRect, anchor: UnitPoint) -> CGRect {
        let point = CGPoint(x: rect.minX + rect.width * anchor.x, y: rect.minY + rect.height * anchor.y)
        return CGRect(x: point.x - visible.width * anchor.x, y: point.y - visible.height * anchor.y,
                      width: visible.width, height: visible.height)
    }

    /// Visible-frame callbacks arrive many times per scroll; report once per run-loop turn.
    func scheduleGeometryReport() {
        guard !geometryReportScheduled else { return }
        geometryReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.geometryReportScheduled = false
            self?.reportGeometry()
        }
    }

    private func reportGeometry() {
        let visible = markupController.contentVisibleFrame
        guard visible.width > 0, lastLayoutSize.width > 0 else { return }
        if let binding = environment.paperScrollPosition, binding.wrappedValue.visibleRect != visible {
            binding.wrappedValue.visibleRect = visible
        }
        let handlers = environment.paperEvents.geometry
        guard !handlers.isEmpty else { return }
        let page = paper.wrappedValue.size.size
        let absolute = lastLayoutSize.width / visible.width
        let resting = placement.restingScale(view: lastLayoutSize, page: page)
        let geometry = PaperGeometry(
            zoomScale: absolute / resting,
            visibleRect: visible,
            contentSize: CGSize(width: page.width * absolute, height: page.height * absolute)
        )
        for handler in handlers { handler(geometry) }
    }

    // MARK: Input and borrowed environment

    private func applyInput() {
        let input = environment.paperInput
        #if !os(macOS)
        switch input.direct {
        case .automatic:
            markupController.directTouchAutomaticallyDraws = true
        case .draw:
            markupController.directTouchAutomaticallyDraws = false
            markupController.directTouchMode = .drawing
        case .select:
            markupController.directTouchAutomaticallyDraws = false
            markupController.directTouchMode = .selection
        }
        #endif
        if defaultPointerMode == nil { defaultPointerMode = markupController.indirectPointerTouchMode }
        let pointer: PaperMarkupViewController.TouchMode = switch input.pointer {
        case .automatic: defaultPointerMode ?? .selection
        case .draw: .drawing
        case .select: .selection
        }
        if markupController.indirectPointerTouchMode != pointer {
            markupController.indirectPointerTouchMode = pointer
        }
    }

    /// `.scrollDisabled` and `.scrollIndicators` (PLAN 3.4). `.disabled` is applied in `update`.
    private func applyBorrowedEnvironment() {
        let scroll = markupController.scrollConfiguration
        if scroll.isScrollEnabled != environment.isScrollEnabled {
            scroll.isScrollEnabled = environment.isScrollEnabled
        }
        var axes: PaperMarkupViewController.ScrollConfiguration.Axis = []
        if Self.shows(environment.horizontalScrollIndicatorVisibility) { axes.insert(.horizontal) }
        if Self.shows(environment.verticalScrollIndicatorVisibility) { axes.insert(.vertical) }
        if scroll.visibleScrollIndicators != axes {
            scroll.visibleScrollIndicators = axes
        }
    }

    private static func shows(_ visibility: ScrollIndicatorVisibility) -> Bool {
        visibility != .hidden && visibility != .never
    }

    // MARK: Adornments

    private func pushAdornmentsIfNeeded() {
        guard let wanted = environment.paperAdornments?.adornments.wrappedValue else {
            if pushedAdornments != nil {
                markupController.adornments = []
                pushedAdornments = nil
            }
            return
        }
        guard wanted != pushedAdornments else { return }
        markupController.adornments = wanted.map(\.markupAdornment)
        pushedAdornments = wanted
    }

    func adornmentDidMove(_ id: UUID, anchor: MarkupAdornment.Anchor) {
        guard let binding = environment.paperAdornments?.adornments,
              let markup = markupController.markup,
              let location = anchor.location(in: markup),
              let index = binding.wrappedValue.firstIndex(where: { $0.id == id })
        else { return }
        var adornments = binding.wrappedValue
        adornments[index].location = location
        pushedAdornments = adornments
        binding.wrappedValue = adornments
        debugLog("adornment moved:", id, location)
    }
}

extension PaperAdornment {
    var markupAdornment: MarkupAdornment {
        let configuration: MarkupAdornment.ImageConfiguration = switch image {
        case .default: .default
        case .systemImage(let name): .systemImage(name)
        #if os(macOS)
        case .image(let cgImage): .image(NSImage(cgImage: cgImage, size: .zero))
        #else
        case .image(let cgImage): .image(UIImage(cgImage: cgImage))
        #endif
        }
        return MarkupAdornment(
            id: id, anchor: .canvas(location: location), imageConfiguration: configuration,
            dragRegion: dragRegion == .canvas ? .canvas : .fixed, scalesWithZoom: scalesWithZoom
        )
    }
}

extension Paper.Element.ID {
    init(_ raw: MarkupOrderedSet.ElementID) {
        self.init(raw: raw)
    }
}

// MARK: - Insertion menu and picker accessory (iOS, visionOS)

#if !os(macOS)
extension PaperEditorController: @preconcurrency MarkupEditViewController.Delegate, UIPopoverPresentationControllerDelegate {
    func updateInsertionMenu() {
        let wantsMenu = environment.paperInsertionMenuIsPresented?.wrappedValue ?? false
        if wantsMenu, insertionMenu == nil, view.window != nil {
            let menu = MarkupEditViewController(supportedFeatureSet: features.featureSet)
            menu.delegate = self
            menu.modalPresentationStyle = .popover
            if let popover = menu.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.minY + 8, width: 1, height: 1)
                popover.permittedArrowDirections = .up
                popover.delegate = self
            }
            insertionMenu = menu
            present(menu, animated: !environment.accessibilityReduceMotion)
        } else if !wantsMenu, let menu = insertionMenu {
            insertionMenu = nil
            menu.dismiss(animated: !environment.accessibilityReduceMotion)
        }
    }

    private func insertionMenuDidFinish() {
        insertionMenu?.dismiss(animated: !environment.accessibilityReduceMotion)
        insertionMenu = nil
        environment.paperInsertionMenuIsPresented?.wrappedValue = false
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        insertionMenu = nil
        environment.paperInsertionMenuIsPresented?.wrappedValue = false
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }

    // Forwarded to the markup controller, which inserts at a suggested frame, then the menu closes.

    func markupEditViewController(_ menu: MarkupEditViewController, insertNewShape type: ShapeConfiguration.Shape) {
        markupController.markupEditViewController(menu, insertNewShape: type)
        insertionMenuDidFinish()
    }

    func markupEditViewControllerInsertNewTextbox(_ menu: MarkupEditViewController) {
        markupController.markupEditViewControllerInsertNewTextbox(menu)
        insertionMenuDidFinish()
    }

    func markupEditViewController(_ menu: MarkupEditViewController, insertNewLineWithStartMarker lineStartMarker: Bool, endMarker lineEndMarker: Bool) {
        markupController.markupEditViewController(menu, insertNewLineWithStartMarker: lineStartMarker, endMarker: lineEndMarker)
        insertionMenuDidFinish()
    }

    func markupEditViewController(_ menu: MarkupEditViewController, insertNewContents toInsert: PaperMarkup) {
        markupController.markupEditViewController(menu, insertNewContents: toInsert)
        insertionMenuDidFinish()
    }

    func updateToolPickerAccessory() {
        guard let picker = attachedToolPickerForAccessory else { return }
        guard let accessory = environment.paperToolPickerAccessory else {
            if accessoryAction != nil {
                picker.accessoryItem = nil
                accessoryAction = nil
                accessoryAppearance = nil
            }
            return
        }
        accessoryAction = accessory.action
        let title = accessory.title.resolvedForUIKit
        let appearance = accessory.systemImage + "|" + title
        guard appearance != accessoryAppearance || picker.accessoryItem == nil else { return }
        accessoryAppearance = appearance
        let item = UIBarButtonItem(
            image: UIImage(systemName: accessory.systemImage),
            primaryAction: UIAction { [weak self] _ in self?.accessoryAction?() }
        )
        item.accessibilityLabel = title
        picker.accessoryItem = item
    }
}

extension LocalizedStringKey {
    /// The key's text for UIKit, which can't take a `LocalizedStringKey`. Looked up in the main bundle.
    var resolvedForUIKit: String {
        let key = Mirror(reflecting: self).children.first { $0.label == "key" }?.value as? String ?? ""
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
#endif
