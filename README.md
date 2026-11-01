# SwiftUI Paper

A SwiftUI-native API for PaperKit and Apple Pencil markup.

```swift
import PaperUI

PaperEditor(paper: $paper)
    .paperTool($tool)
    .paperToolPicker(isPresented: $showPicker)
    .paperContentMode(.fitWidth, anchor: .top)
```

- [docs/PLAN.md](docs/PLAN.md): the API specification and build plan
- [docs/SDK-FINDINGS.md](docs/SDK-FINDINGS.md): what the iOS 27 SDK and the UI checks established
- `Sources/PaperUI`: `Model/`, `Views/`, `Modifiers/`, `Bridge/`, `Output/`, `Samples/`
- `Demo/PaperDemo.xcodeproj`: an iPad app exercising the API. Launch arguments `-reset`, `-sample`, and `-sampleLocked` pick the starting page, and the `PAPERUI_DEBUG` environment variable turns on coordinator logging

Run the tests with `swift test` (macOS) or `xcodebuild test -scheme SwiftUIPaper -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`.
