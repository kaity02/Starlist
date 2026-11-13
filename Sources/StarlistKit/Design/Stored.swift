import SwiftUI

/// View-local state, under another name.
///
/// In the macOS 27 SDK, writing `@State` invokes a compiler macro whose plugin
/// ships only with Xcode. This alias points at the same underlying SwiftUI type
/// without going through the macro, so the project builds with just the
/// Command Line Tools (and still builds the same way under Xcode).
typealias Stored<Value> = SwiftUI.State<Value>
