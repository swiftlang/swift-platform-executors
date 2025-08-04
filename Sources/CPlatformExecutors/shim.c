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

#ifdef __linux__

#include <CPlatformExecutors.h>
#include <pthread.h>

int CPlatformExecutors_pthread_setname_np(pthread_t thread, const char *name) {
    return pthread_setname_np(thread, name);
}

int CPlatformExecutors_pthread_getname_np(pthread_t thread, char *name, size_t len) {
#ifdef __ANDROID__
    // https://android.googlesource.com/platform/bionic/+/8a18af52d9b9344497758ed04907a314a083b204/libc/bionic/pthread_setname_np.cpp#51
    if (thread == pthread_self()) {
        return TEMP_FAILURE_RETRY(prctl(PR_GET_NAME, name)) == -1 ? -1 : 0;
    }

    char comm_name[64];
    snprintf(comm_name, sizeof(comm_name), "/proc/self/task/%d/comm", pthread_gettid_np(thread));
    int fd = TEMP_FAILURE_RETRY(open(comm_name, O_CLOEXEC | O_RDONLY));

    if (fd == -1) return -1;

    ssize_t n = TEMP_FAILURE_RETRY(read(fd, name, len));
    close(fd);
    if (n == -1) return -1;

    // The kernel adds a trailing '\n' to the /proc file,
    // so this is actually the normal case for short names.
    if (n > 0 && name[n - 1] == '\n') {
        name[n - 1] = '\0';
        return 0;
    }

    if (n >= 0 && len <= SSIZE_MAX && n == (ssize_t)len) return 1;

    name[n] = '\0';
    return 0;
#else
    return pthread_getname_np(thread, name, len);
#endif
}

#endif

// Dispatch executor support (Darwin only)
#ifdef __APPLE__

#include <dispatch/dispatch.h>

void CPlatformExecutors_dispatchMain(void) {
    dispatch_main();
}

#endif // __has_include(<dispatch/dispatch.h>)
