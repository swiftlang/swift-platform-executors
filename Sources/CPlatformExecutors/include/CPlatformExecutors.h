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

#ifndef C_PLATFORM_EXECUTORS_H
#define C_PLATFORM_EXECUTORS_H

#ifdef __linux__
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <pthread.h>
#include <errno.h>

int CPlatformExecutors_pthread_setname_np(pthread_t thread, const char *name);
int CPlatformExecutors_pthread_getname_np(pthread_t thread, char *name, size_t len);

#endif

#include <dlfcn.h>

#ifdef __APPLE__

// Export RTLD_NEXT constant for Swift
static void* const CPlatformExecutors_RTLD_NEXT = RTLD_NEXT;

// Only essential functions that cannot be implemented in Swift
void CPlatformExecutors_dispatchMain(void) __attribute__((noreturn));

#endif

#endif // C_PLATFORM_EXECUTORS_H
