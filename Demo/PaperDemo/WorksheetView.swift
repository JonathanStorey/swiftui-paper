import CoreTransferable
import PaperUI
import SwiftUI
import UniformTypeIdentifiers

/// Exercises the API through Phase 2: the binding, tool, tool picker, features, content mode,
/// zoom range, `.disabled`, `\.undoManager`, saving and restoring, the stored PDF background,
/// locking, rotation, a `PaperView` thumbnail, and sharing as a PDF.
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
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        PaperEditor(paper: $paper)
            .paperTool($tool)
            .paperToolPicker(isPresented: $showPicker)
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
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
            Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
            Button("Lock All", systemImage: "lock") { paper.lockAll() }
            Button("Rotate Clockwise", systemImage: "rotate.right") { paper.rotate(.clockwise) }
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
