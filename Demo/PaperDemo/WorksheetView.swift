import CoreTransferable
import PaperUI
import SwiftUI
import UniformTypeIdentifiers

/// Exercises the API through Phase 3: the binding, tool, tool picker, features, content mode,
/// zoom range, `.disabled`, `\.undoManager`, saving and restoring, the stored PDF background,
/// locking, rotation, a `PaperView` thumbnail, sharing as a PDF, and, in the inspector, every
/// interaction modifier: selection, scroll position, geometry, drawing events, inserting,
/// removing, input modes, the ruler, custom tools, the picker accessory, the insertion menu,
/// adornments, and `.scrollDisabled`.
struct WorksheetView: View {
    @State private var paper = DemoStore.load()
    @State private var tool: Paper.Tool = .pen(.black, width: 3)
    @State private var showPicker = true
    @State private var isReadOnly = false
    @State private var allowText = true
    @State private var contentMode: PaperContentMode = .fit
    @State private var lastSaved: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var showThumbnail = true
    @State private var showInspector = false

    // Phase 3
    @State private var selection = Paper.Selection()
    @State private var selectedContentCount = 0
    @State private var position = PaperScrollPosition()
    @State private var zoomPercent = 100
    @State private var strokesBegun = 0
    @State private var showInsertionMenu = false
    @State private var directInput: PaperTouchMode = .automatic
    @State private var rulerActive = false
    @State private var scrollDisabled = false
    @State private var adornments: [PaperAdornment] = []
    @State private var adornmentTaps = 0
    @State private var accessoryTaps = 0
    @Environment(\.undoManager) private var undoManager

    static let pickerItems = PaperToolPickerItem.standard + [.custom(id: "stamp", name: "Stamp", systemImage: "seal")]

    var body: some View {
        PaperEditor(paper: $paper)
            .paperTool($tool)
            .paperToolPicker(isPresented: $showPicker, items: Self.pickerItems)
            .paperToolPickerAccessory("Accessory", systemImage: "star") { accessoryTaps += 1 }
            .paperSelection($selection)
            .onPaperSelectionChange { _, content in selectedContentCount = content.elements.count }
            .paperScrollPosition($position)
            .onPaperGeometryChange(for: Int.self, of: { Int(($0.zoomScale * 100).rounded()) }) { _, new in zoomPercent = new }
            .onPaperDrawingBegan { strokesBegun += 1 }
            .paperInsertionMenu(isPresented: $showInsertionMenu)
            .paperAdornments($adornments) { _ in adornmentTaps += 1 }
            .paperInput(direct: directInput)
            .paperRulerActive(rulerActive)
            .scrollDisabled(scrollDisabled)
            .paperFeatures(allowText ? .latest : Paper.Features.latest.removing(.text))
            .paperContentMode(contentMode, anchor: .top)
            .paperZoomRange(0.5...6)
            .disabled(isReadOnly)
            .ignoresSafeArea(edges: .bottom)
            .background(.gray.opacity(0.15))
            .navigationTitle("Worksheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .top) { status }
            .overlay(alignment: .topTrailing) {
                if showThumbnail {
                    PaperView(paper)
                        .frame(width: 120)
                        .shadow(radius: 4)
                        .padding()
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("thumbnail")
                }
            }
            .onChange(of: paper) { scheduleSave() }
            .inspector(isPresented: $showInspector) { inspector }
    }

    // MARK: Inspector (plain buttons, so every control works with simulated taps)

    private var inspector: some View {
        Form {
            Section("Selection") {
                LabeledContent("Selected", value: "\(selection.ids.count) (content \(selectedContentCount))")
                Button("Select All Unlocked") { selection = Paper.Selection(paper.elements.filter { !$0.isLocked }.map(\.id)) }
                Button("Clear Selection") { selection.clear() }
                Button("Delete Selected", role: .destructive) { paper.remove(selection.ids) }
                Button("Scroll to Selection") { position.scrollTo(selection: selection) }
            }
            Section("Scroll and zoom") {
                LabeledContent("Zoom", value: "\(zoomPercent)%")
                LabeledContent("Visible", value: position.visibleRect.map(Self.describe) ?? "–")
                Button("Zoom to Top-Left Quarter") {
                    position.scrollTo(rect: CGRect(origin: .zero, size: CGSize(width: paper.size.size.width / 2, height: paper.size.size.height / 2)))
                }
                Button("Zoom to Fit") { position.zoomToFit() }
                Toggle("Scroll Disabled", isOn: $scrollDisabled)
            }
            Section("Insert") {
                Button("Rectangle") {
                    paper.insertShape(.roundedRectangle(cornerRadius: 12), style: .init(stroke: .blue, fill: nil, lineWidth: 3), in: CGRect(x: 72, y: 500, width: 200, height: 100))
                }
                Button("Arrow Line") {
                    paper.insertLine(from: CGPoint(x: 320, y: 520), to: CGPoint(x: 520, y: 600), style: .init(stroke: .red, lineWidth: 3), endArrow: true)
                }
                Button("Text") {
                    paper.insertText(AttributedString("Name: ____________"), in: CGRect(x: 72, y: 640, width: 300, height: 30))
                }
                Button("Image") {
                    if let image = Self.symbolImage("seal.fill") { paper.insertImage(image, in: CGRect(x: 420, y: 640, width: 60, height: 60)) }
                }
                Button("Insertion Menu…") { showInsertionMenu = true }
            }
            Section("Input") {
                Picker("Finger", selection: $directInput) {
                    Text("Auto").tag(PaperTouchMode.automatic)
                    Text("Draw").tag(PaperTouchMode.draw)
                    Text("Select").tag(PaperTouchMode.select)
                }
                .pickerStyle(.segmented)
                Toggle("Ruler", isOn: $rulerActive)
                Button("Use Stamp (custom tool)") { tool = .custom(id: "stamp") }
                LabeledContent("Tool", value: Self.describe(tool))
                LabeledContent("Strokes begun", value: "\(strokesBegun)")
                LabeledContent("Accessory taps", value: "\(accessoryTaps)")
            }
            Section("Adornments") {
                Button("Add Badge") {
                    adornments.append(PaperAdornment(location: CGPoint(x: 300 + 30 * Double(adornments.count), y: 300),
                                                     image: .systemImage("bubble.left.fill"), dragRegion: .canvas))
                }
                Button("Remove Badges") { adornments.removeAll() }
                LabeledContent("Badges", value: "\(adornments.count), taps \(adornmentTaps)")
                ForEach(adornments) { LabeledContent("Badge", value: "\(Int($0.location.x)), \(Int($0.location.y))") }
            }
            Section("Page") {
                Toggle("Tool Picker", isOn: $showPicker)
                Toggle("Read Only", isOn: $isReadOnly)
                Toggle("Thumbnail", isOn: $showThumbnail)
                Button("Unlock All") { paper.unlockAll() }
                #if DEBUG
                Button("New Worksheet") { paper = DemoStore.worksheet }
                #endif
            }
        }
        .inspectorColumnWidth(300)
    }

    private static func symbolImage(_ name: String) -> CGImage? {
        let renderer = ImageRenderer(content: Image(systemName: name).font(.system(size: 120)).foregroundStyle(.orange))
        renderer.scale = 2
        return renderer.cgImage
    }

    private static func describe(_ tool: Paper.Tool) -> String {
        switch tool {
        case .ink(let ink, let width): "\(ink.kind) \(Int(width)) pt"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .custom(let id): "custom: \(id)"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
            Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
            Button("Lock All", systemImage: "lock") { paper.lockAll() }
            Button("Rotate Clockwise", systemImage: "rotate.right") { paper.rotate(.clockwise) }
            Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
            ShareLink(item: PDFExport(paper: paper), preview: SharePreview("Worksheet.pdf")) {
                Label("Share PDF", systemImage: "square.and.arrow.up")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Compared by kind, because the system picker writes back its own widths and colors.
            Picker("Tool", selection: toolChoice) {
                Label("Pen", systemImage: "pencil.tip").tag(ToolChoice.pen)
                Label("Marker", systemImage: "highlighter").tag(ToolChoice.marker)
                Label("Eraser", systemImage: "eraser").tag(ToolChoice.eraser)
                Label("Lasso", systemImage: "lasso").tag(ToolChoice.lasso)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("toolPicker")

            Menu("Options", systemImage: "ellipsis.circle") {
                Picker("Content Mode", selection: $contentMode) {
                    Text("Fit").tag(PaperContentMode.fit)
                    Text("Fill").tag(PaperContentMode.fill)
                    Text("Fit Width").tag(PaperContentMode.fitWidth)
                    Text("Fit Height").tag(PaperContentMode.fitHeight)
                }
                Toggle("Tool Picker", isOn: $showPicker)
                Toggle("Read Only", isOn: $isReadOnly)
                Toggle("Allow Text", isOn: $allowText)
                Toggle("Thumbnail", isOn: $showThumbnail)
                Divider()
                #if DEBUG
                Button("New Worksheet", systemImage: "doc.text") { paper = DemoStore.worksheet }
                #endif
                Button("Unlock All", systemImage: "lock.open") { paper.unlockAll() }
                Button("Clear Page", systemImage: "trash", role: .destructive) { paper = Paper(size: .letter) }
            }
            .accessibilityIdentifier("options")
        }
    }

    private var toolChoice: Binding<ToolChoice?> {
        Binding {
            ToolChoice(tool)
        } set: { choice in
            if let choice { tool = choice.tool }
        }
    }

    private var status: some View {
        HStack {
            Text(paper.isEmpty ? "Empty page" : "Content in \(Self.describe(paper.contentBounds))")
            Spacer()
            if let lastSaved {
                Text("Saved \(lastSaved, format: .dateTime.hour().minute().second())")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = paper
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                try await DemoStore.save(snapshot)
                lastSaved = .now
            } catch {
                print("Save failed:", error)
            }
        }
    }

    private static func describe(_ rect: CGRect) -> String {
        "x \(Int(rect.minX))–\(Int(rect.maxX)), y \(Int(rect.minY))–\(Int(rect.maxY))"
    }
}

/// Shares the paper as a file named Worksheet.pdf rather than as anonymous PDF data.
struct PDFExport: Transferable {
    let paper: Paper

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            let url = URL.temporaryDirectory.appending(path: "Worksheet.pdf")
            try await export.paper.pdfData().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum ToolChoice: Hashable {
    case pen, marker, eraser, lasso

    init?(_ tool: Paper.Tool) {
        switch tool {
        case .ink(let ink, _) where ink.kind == .pen: self = .pen
        case .ink(let ink, _) where ink.kind == .marker: self = .marker
        case .eraser: self = .eraser
        case .lasso: self = .lasso
        default: return nil
        }
    }

    var tool: Paper.Tool {
        switch self {
        case .pen: .pen(.black, width: 3)
        case .marker: .marker(.red)
        case .eraser: .eraser
        case .lasso: .lasso
        }
    }
}

/// Saves the paper with `dataRepresentation()` and restores it on launch.
///
/// Launch arguments: `-reset` starts from a blank page, `-sample` loads `Paper.sample`, `-worksheet`
/// loads it over `Paper.samplePDF`, and
/// `-sampleLocked` loads it with every stroke locked (for the eraser and lasso UI check). In DEBUG,
/// `-writePDF` also writes `Worksheet.pdf` to Documents on every save.
enum DemoStore {
    static let url = URL.documentsDirectory.appending(path: "Worksheet.swiftpaper")

    static func load() -> Paper {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("-sample") { return .sample }
        if arguments.contains("-worksheet") { return worksheet }
        if arguments.contains("-sampleLocked") {
            var paper = Paper.sample
            paper.lockAll()
            return paper
        }
        #endif
        if arguments.contains("-reset") { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return Paper(size: .letter) }
        do {
            return try Paper(dataRepresentation: data)
        } catch {
            print("Restore failed:", error)
            return Paper(size: .letter)
        }
    }

    #if DEBUG
    /// The ruled sample PDF with two strokes on it.
    static var worksheet: Paper {
        var paper = Paper.samplePDF
        paper.append(.sample)
        return paper
    }
    #endif

    static func save(_ paper: Paper) async throws {
        let data = try await paper.dataRepresentation()
        try data.write(to: url, options: .atomic)
        #if DEBUG
        // UI checks: the same bytes the Share PDF button sends.
        if ProcessInfo.processInfo.arguments.contains("-writePDF") {
            try await paper.pdfData().write(to: URL.documentsDirectory.appending(path: "Worksheet.pdf"), options: .atomic)
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        PaperEditor(paper: .constant(.sample))
            .paperContentMode(.fitWidth, anchor: .top)
    }
}
