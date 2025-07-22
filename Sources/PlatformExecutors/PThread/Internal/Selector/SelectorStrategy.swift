//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The strategy used for the `Selector`.
enum SelectorStrategy {
  /// Block until there is some IO ready to be processed or the `Selector` is explicitly woken up.
  case block

  /// Try to select all ready IO at this point in time without blocking at all.
  case now
}
