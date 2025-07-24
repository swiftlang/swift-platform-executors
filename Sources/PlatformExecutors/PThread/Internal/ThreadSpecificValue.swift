final class ThreadSpecificVariable<Value: AnyObject> {
  // the actual type in there is `Box<(ThreadSpecificVariable<T>, T)>` but we can't use that as C functions can't capture (even types)
  private typealias BoxedType = Box<(AnyObject, AnyObject)>

  internal class Key {
    private var underlyingKey: PThread.ThreadSpecificKey

    internal init(destructor: @escaping PThread.ThreadSpecificKeyDestructor) {
      self.underlyingKey = PThread.allocateThreadSpecificValue(destructor: destructor)
    }

    deinit {
      PThread.deallocateThreadSpecificValue(self.underlyingKey)
    }

    func get() -> UnsafeMutableRawPointer? {
      PThread.getThreadSpecificValue(self.underlyingKey)
    }

    func set(value: UnsafeMutableRawPointer?) {
      PThread.setThreadSpecificValue(key: self.underlyingKey, value: value)
    }
  }

  private let key: Key

  /// Initialize a new `ThreadSpecificVariable` without a current value (`currentValue == nil`).
  init() {
    self.key = Key(destructor: {
      Unmanaged<BoxedType>.fromOpaque(($0 as UnsafeMutableRawPointer?)!).release()
    })
  }

  /// Initialize a new `ThreadSpecificVariable` with `value` for the calling thread. After calling this, the calling
  /// thread will see `currentValue == value` but on all other threads `currentValue` will be `nil` until changed.
  ///
  /// - Parameters:
  ///   - value: The value to set for the calling thread.
  convenience init(value: Value) {
    self.init()
    self.currentValue = value
  }

  /// The value for the current thread.
  @available(
    *,
     noasync,
     message: "threads can change between suspension points and therefore the thread specific value too"
  )
  var currentValue: Value? {
    get {
      self.get()
    }
    set {
      self.set(newValue)
    }
  }

  /// Get the current value for the calling thread.
  func get() -> Value? {
    guard let raw = self.key.get() else { return nil }
    // parenthesize the return value to silence the cast warning
    return (Unmanaged<BoxedType>
      .fromOpaque(raw)
      .takeUnretainedValue()
      .value.1 as! Value)
  }

  /// Set the current value for the calling threads. The `currentValue` for all other threads remains unchanged.
  func set(_ newValue: Value?) {
    if let raw = self.key.get() {
      Unmanaged<BoxedType>.fromOpaque(raw).release()
    }
    self.key.set(value: newValue.map { Unmanaged.passRetained(Box((self, $0))).toOpaque() })
  }
}

extension ThreadSpecificVariable: @unchecked Sendable where Value: Sendable {}
