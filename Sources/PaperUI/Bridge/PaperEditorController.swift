import Foundation
import Observation
import PaperKit
import PencilKit
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformViewController = NSViewController
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformView = UIView
#endif

/// The editor's private coordinator (PLAN 6.3). It hosts a `PaperMarkupViewController` as a
/// child, so the child can be rebuilt when the feature set changes, and keeps it in sync with
/// the `Paper` binding and the environment.
@MainActor
final class PaperEditorController: PlatformViewController, PaperMarkupViewController.Delegate {
    private(set) var markupController: PaperMarkupViewController
    private var paper: Binding<Paper>
    private var environment: EnvironmentValues
    private var features: Paper.Features

    // Loop prevention: the controller is written only when the binding's token matches neither.
    private var lastPushedToken: UUID?
    private var lastReceivedToken: UUID?
    private var isPushing = false
    private var flushScheduled = false

    // The tool last pushed from the binding, and how PencilKit reported it back.
    private var pushedTool: (binding: Paper.Tool, readBack: Paper.Tool?)?
    private var observationGeneration = 0

    // Content mode
    private var placement: PaperContentPlacement
    private var zoomRange: ClosedRange<CGFloat>
    private var lastLayoutSize: CGSize = .zero
    private var lastAppliedVisibleRect: CGRect?
    private var userHasAdjustedView = false
    private var isApplyingPlacement = false

    #if os(macOS)
    private var toolbar: MarkupToolbarViewController?
    private var canvasTopConstraint: NSLayoutConstraint?
    #else
    private weak var attachedToolPicker: PKToolPicker?
    #endif

    init(paper: Binding<Paper>, environment: EnvironmentValues) {
        self.paper = paper
        self.environment = environment
        self.features = environment.paperFeatures
        self.placement = environment.paperContentPlacement
        self.zoomRange = environment.paperZoomRange
        self.markupController = PaperMarkupViewController(markup: paper.wrappedValue.markup, supportedFeatureSet: features.featureSet)
        self.lastPushedToken = paper.wrappedValue.token
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Lifecycle

    #if os(macOS)
    override func loadView() {
        view = NSView()
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        installMarkupController()
    }

    #if os(macOS)
    override func viewDidLayout() {
        super.viewDidLayout()
        layoutDidChange()
    }
    #else
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutDidChange()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateToolPicker()
        debugLog("undoManager is the window's:", markupController.undoManager === environment.undoManager,
                 "controller:", markupController.undoManager.map { ObjectIdentifier($0) } as Any,
                 "environment:", environment.undoManager.map { ObjectIdentifier($0) } as Any)
    }
    #endif

    // MARK: Updates from SwiftUI

    func update(paper: Binding<Paper>, environment: EnvironmentValues) {
        self.paper = paper
        self.environment = environment

        if environment.paperFeatures != features {
            features = environment.paperFeatures
            rebuildMarkupController()
        }
        pushPaperIfNeeded()
        markupController.isEditable = environment.isEnabled
        pushToolIfNeeded()

        if environment.paperContentPlacement != placement || environment.paperZoomRange != zoomRange {
            if environment.paperContentPlacement != placement { userHasAdjustedView = false }
            placement = environment.paperContentPlacement
            zoomRange = environment.paperZoomRange
            applyPlacement(previousViewSize: lastLayoutSize)
        }
        updateToolPicker()
    }

    private func pushPaperIfNeeded() {
        let current = paper.wrappedValue
        guard current.token != lastPushedToken, current.token != lastReceivedToken else { return }
        let sizeChanged = markupController.markup?.bounds != current.markup.bounds
        isPushing = true
        markupController.markup = current.markup
        isPushing = false
        lastPushedToken = current.token
        debugLog("pushed paper", current.token)
        if sizeChanged { applyPlacement(previousViewSize: lastLayoutSize) }
    }

    // MARK: Markup controller

    private func installMarkupController() {
        markupController.delegate = self
        markupController.isEditable = environment.isEnabled
        addChild(markupController)
        let canvas: PlatformView = markupController.view
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        let top = canvas.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            top,
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #if os(macOS)
        canvasTopConstraint = top
        #else
        markupController.didMove(toParent: self)
        #endif

        pushedTool = nil
        pushToolIfNeeded()
        observeTool()
    }

    /// The feature set is fixed at init, so a change means a new controller holding the current content.
    private func rebuildMarkupController() {
        let old = markupController
        #if os(macOS)
        removeToolbar()
        #else
        old.willMove(toParent: nil)
        attachedToolPicker?.removeObserver(old)
        attachedToolPicker = nil
        #endif
        old.view.removeFromSuperview()
        old.removeFromParent()
        old.delegate = nil

        markupController = PaperMarkupViewController(markup: paper.wrappedValue.markup, supportedFeatureSet: features.featureSet)
        lastPushedToken = paper.wrappedValue.token
        installMarkupController()
        applyPlacement(previousViewSize: lastLayoutSize)
        debugLog("rebuilt controller for features", features)
    }

    // MARK: Delegate

    nonisolated func paperMarkupViewControllerDidChangeMarkup(_ controller: PaperMarkupViewController) {
        MainActor.assumeIsolated { scheduleFlush() }
    }

    nonisolated func paperMarkupViewControllerDidChangeContentVisibleFrame(_ controller: PaperMarkupViewController) {
        MainActor.assumeIsolated { visibleFrameDidChange() }
    }

    nonisolated func paperMarkupViewControllerDidChangeSelection(_ controller: PaperMarkupViewController) {
        MainActor.assumeIsolated {
            debugLog("selection changed:", markupController.selection.count, "element(s)",
                     "locked:", markupController.selection.filter(isLocked).count)
        }
    }

    /// Coalescing: however many change callbacks arrive in one turn of the run loop, the binding is written once.
    private func scheduleFlush() {
        guard !isPushing, !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushScheduled = false
            self?.flush()
        }
    }

    private func flush() {
        guard let markup = markupController.markup else { return }
        var value = paper.wrappedValue
        guard value.markup != markup else { return }
        value.replaceMarkup(markup)
        lastReceivedToken = value.token
        paper.wrappedValue = value
        debugLog("received paper", value.token, "elements:", markup.subelements.count,
                 "locked:", markup.subelements.filter { $0.allowedInteractions == .readOnly }.count)
    }

    private func isLocked(_ id: MarkupOrderedSet.ElementID) -> Bool {
        markupController.markup?.subelements[id]?.allowedInteractions == .readOnly
    }

    // MARK: Tool

    private func pushToolIfNeeded() {
        guard let binding = environment.paperTool else { return }
        let wanted = binding.wrappedValue
        guard wanted != pushedTool?.binding else { return }
        guard let pkTool = wanted.pkTool else {
            pushedTool = (wanted, nil)
            return
        }
        #if !os(macOS)
        selectToolPickerItem(matching: wanted)
        #endif
        markupController.drawingTool = pkTool
        pushedTool = (wanted, Paper.Tool(markupController.drawingTool))
    }

    private func observeTool() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = markupController.drawingTool
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.observationGeneration else { return }
                self.toolDidChange()
                self.observeTool()
            }
        }
    }

    private func toolDidChange() {
        guard let binding = environment.paperTool, let current = Paper.Tool(markupController.drawingTool) else { return }
        guard current != pushedTool?.readBack, current != binding.wrappedValue else { return }
        pushedTool = (current, current)
        binding.wrappedValue = current
        debugLog("tool from picker:", current)
    }

    // MARK: Content mode

    private func layoutDidChange() {
        let size = view.bounds.size
        guard size != lastLayoutSize, size.width > 0, size.height > 0 else { return }
        let previous = lastLayoutSize
        lastLayoutSize = size
        applyPlacement(previousViewSize: previous)
    }

    /// Puts the page at its resting placement, or, once the user has scrolled or zoomed, keeps
    /// the same page point in view at the same relative zoom.
    private func applyPlacement(previousViewSize: CGSize) {
        let viewSize = lastLayoutSize
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let page = paper.wrappedValue.size.size
        let resting = placement.restingScale(view: viewSize, page: page)

        let rect: CGRect
        let visible = markupController.contentVisibleFrame
        if userHasAdjustedView, previousViewSize.width > 0, visible.width > 0 {
            let previousResting = placement.restingScale(view: previousViewSize, page: page)
            let relativeZoom = (previousViewSize.width / visible.width) / previousResting
            rect = placement.visibleRect(view: viewSize, page: page, center: CGPoint(x: visible.midX, y: visible.midY), relativeZoom: relativeZoom)
        } else {
            rect = placement.restingVisibleRect(view: viewSize, page: page, layoutDirection: environment.layoutDirection)
        }

        isApplyingPlacement = true
        markupController.zoomRange = (zoomRange.lowerBound * resting)...(zoomRange.upperBound * resting)
        markupController.setContentVisibleFrame(rect, animated: false)
        isApplyingPlacement = false
        lastAppliedVisibleRect = markupController.contentVisibleFrame
        debugLog("placement", placement.mode, "view:", viewSize, "resting scale:", resting,
                 "asked:", rect, "got:", markupController.contentVisibleFrame, "zoomRange:", markupController.zoomRange)
        #if !os(macOS)
        debugLog("scroll zoomScale:", markupController.scrollConfiguration.zoomScale)
        #endif
    }

    private func visibleFrameDidChange() {
        guard !isApplyingPlacement, let last = lastAppliedVisibleRect else { return }
        let now = markupController.contentVisibleFrame
        let tolerance: CGFloat = 1
        if abs(now.minX - last.minX) > tolerance || abs(now.minY - last.minY) > tolerance || abs(now.width - last.width) > tolerance {
            userHasAdjustedView = true
        }
    }

    // MARK: Tool picker

    #if os(macOS)
    private func updateToolPicker() {
        let wantsToolbar = environment.paperToolPickerIsPresented?.wrappedValue ?? false
        if wantsToolbar, toolbar == nil {
            let toolbar = MarkupToolbarViewController(supportedFeatureSet: features.featureSet)
            toolbar.delegate = markupController
            toolbar.selectedDrawingTool = markupController.drawingTool
            addChild(toolbar)
            let bar = toolbar.view
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            canvasTopConstraint?.isActive = false
            let top = markupController.view.topAnchor.constraint(equalTo: bar.bottomAnchor)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: view.topAnchor),
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                top,
            ])
            canvasTopConstraint = top
            self.toolbar = toolbar
        } else if !wantsToolbar {
            removeToolbar()
        }
    }

    private func removeToolbar() {
        guard let toolbar else { return }
        toolbar.view.removeFromSuperview()
        toolbar.removeFromParent()
        self.toolbar = nil
        canvasTopConstraint?.isActive = false
        canvasTopConstraint = markupController.view.topAnchor.constraint(equalTo: view.topAnchor)
        canvasTopConstraint?.isActive = true
    }
    #else
    private func updateToolPicker() {
        guard let window = view.window else { return }
        let state = markupController.pencilKitResponderState
        guard let isPresented = environment.paperToolPickerIsPresented else {
            if attachedToolPicker != nil { state.toolPickerVisibility = .hidden }
            return
        }
        let picker = PKToolPicker.perWindow(window)
        if attachedToolPicker !== picker {
            picker.addObserver(markupController)
            picker.addObserver(self)
            picker.colorMaximumLinearExposure = features.maximumHDRExposure
            state.activeToolPicker = picker
            attachedToolPicker = picker
        }
        state.toolPickerVisibility = isPresented.wrappedValue ? .visible : .hidden
        if isPresented.wrappedValue, !markupController.isFirstResponder {
            markupController.becomeFirstResponder()
        }
    }

    /// Selects the picker item for `tool` so the picker shows it. The caller sets the exact tool afterward.
    private func selectToolPickerItem(matching tool: Paper.Tool) {
        guard let picker = attachedToolPicker else { return }
        let item = picker.toolItems.first { item in
            switch (tool, item) {
            case (.ink(let ink, _), let inking as PKToolPickerInkingItem): inking.inkingTool.inkType == ink.kind.inkType
            case (.eraser, is PKToolPickerEraserItem): true
            case (.lasso, is PKToolPickerLassoItem): true
            default: false
            }
        }
        if let item, picker.selectedToolItemIdentifier != item.identifier {
            picker.selectedToolItemIdentifier = item.identifier
        }
    }
    #endif
}

#if !os(macOS)
extension PaperEditorController: PKToolPickerObserver {
    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        guard let isPresented = environment.paperToolPickerIsPresented,
              toolPicker === attachedToolPicker,
              isPresented.wrappedValue != toolPicker.isVisible
        else { return }
        isPresented.wrappedValue = toolPicker.isVisible
    }
}

extension PKToolPicker {
    nonisolated(unsafe) private static let key = malloc(1)!

    /// One picker per window (PLAN 6.3), shared by every editor in it.
    static func perWindow(_ window: UIWindow) -> PKToolPicker {
        if let picker = objc_getAssociatedObject(window, key) as? PKToolPicker { return picker }
        let picker = PKToolPicker()
        objc_setAssociatedObject(window, key, picker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return picker
    }
}
#endif

/// Prints when the `PAPERUI_DEBUG` environment variable is set. Used by the demo's UI checks.
func debugLog(_ items: Any...) {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["PAPERUI_DEBUG"] != nil else { return }
    print("[PaperUI]", items.map { "\($0)" }.joined(separator: " "))
    #endif
}
