import Foundation

/// A value a test changes and a store hook reads: the hooks are `@Sendable`, because a refresh writer calls them off the main thread.
final class TestBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
