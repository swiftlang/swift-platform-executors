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

/// Compare UnownedJobs by priority, breaking ties with the sequence number.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
func compareJobsByPriorityAndSequenceNumber(
  lhs: UnownedJob,
  rhs: UnownedJob
) -> Bool {
  if lhs.priority == rhs.priority {
    // If they're the same priority, compare the sequence numbers to
    // ensure this queue gives stable ordering.  We want the lowest
    // sequence number first, but note that we want to handle wrapping.
    let delta = ExecutorJob(lhs).sequenceNumber &- ExecutorJob(rhs).sequenceNumber
    return (delta >> (UInt.bitWidth - 1)) != 0
  }
  return lhs.priority > rhs.priority
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
func compareJobsByPriorityAndID(
  lhs: UnownedJob,
  rhs: UnownedJob
) -> Bool {
  if lhs.priority == rhs.priority {
    // If they're the same priority, compare the sequence numbers to
    // ensure this queue gives stable ordering.  We want the lowest
    // sequence number first, but note that we want to handle wrapping.
    let delta = _getJobTaskId(lhs) &- _getJobTaskId(rhs)
    return (delta >> (UInt.bitWidth - 1)) != 0
  }
  return lhs.priority > rhs.priority
}

/// This is a method from the Concurrency ABI that we are using for fallback job ordering on older deployment
/// targets
@_silgen_name("swift_task_getJobTaskId")
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
func _getJobTaskId(_ job: UnownedJob) -> UInt64
