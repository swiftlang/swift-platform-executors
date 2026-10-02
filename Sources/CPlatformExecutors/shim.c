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

// Thread stack size support (all pthread platforms)
#if !defined(_WIN32)

#include <CPlatformExecutors.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <unistd.h>

#define CPLATFORM_EXECUTORS_MIN_THREAD_STACK_SIZE (128 * 1024)

size_t CPlatformExecutors_pthread_normalized_stack_size(size_t requested) {
    // PTHREAD_STACK_MIN is only enough for libc itself (16 KiB on x86_64
    // glibc), too little to run Swift code on the thread, so enforce a
    // floor of our own as well
    size_t minimum = CPLATFORM_EXECUTORS_MIN_THREAD_STACK_SIZE;
#ifdef PTHREAD_STACK_MIN
    // With _GNU_SOURCE on glibc >= 2.34 this is a sysconf call, not a constant
    if ((size_t)PTHREAD_STACK_MIN > minimum) {
        minimum = (size_t)PTHREAD_STACK_MIN;
    }
#endif
    if (requested < minimum) {
        requested = minimum;
    }
    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize > 0) {
        size_t page = (size_t)pageSize;
        size_t remainder = requested % page;
        if (remainder != 0) {
            if (requested > SIZE_MAX - (page - remainder)) {
                // Round down instead of overflowing; pthread_create will fail
                // on such a size anyway
                return requested - remainder;
            }
            requested += page - remainder;
        }
    }
    return requested;
}

size_t CPlatformExecutors_pthread_current_stack_size(void) {
#if defined(__APPLE__)
    return pthread_get_stacksize_np(pthread_self());
#elif defined(__linux__)
    pthread_attr_t attr;
    if (pthread_getattr_np(pthread_self(), &attr) != 0) {
        return 0;
    }
    size_t size = 0;
    if (pthread_attr_getstacksize(&attr, &size) != 0) {
        size = 0;
    }
    pthread_attr_destroy(&attr);
    return size;
#else
    return 0;
#endif
}

#endif // !defined(_WIN32)

// Dispatch executor support (Darwin only)
#ifdef __APPLE__

#include <dispatch/dispatch.h>

void CPlatformExecutors_dispatchMain(void) {
    dispatch_main();
}

#endif // __has_include(<dispatch/dispatch.h>)

// wasm32-unknown-wasip1-threads support
#ifdef __wasi__

#include <CPlatformExecutors.h>

#define CPLATFORM_EXECUTORS_WASI_THREAD_STACK_SIZE (4 * 1024 * 1024)

int CPlatformExecutors_wasi_pthread_create(pthread_t *thread, void *(*start)(void *), void *arg, size_t stackSize) {
    pthread_attr_t attr;
    int result = pthread_attr_init(&attr);
    if (result != 0) {
        return result;
    }
    if (stackSize == 0) {
        stackSize = CPLATFORM_EXECUTORS_WASI_THREAD_STACK_SIZE;
    }
    result = pthread_attr_setstacksize(&attr, stackSize);
    if (result == 0) {
        result = pthread_create(thread, &attr, start, arg);
    }
    pthread_attr_destroy(&attr);
    return result;
}

// wasi-libc declares pthread_setname_np/pthread_getname_np but does not
// define them (no thread names in WASI): names are accepted and dropped.
int CPlatformExecutors_pthread_setname_np(pthread_t thread, const char *name) {
    (void)thread;
    (void)name;
    return 0;
}

int CPlatformExecutors_pthread_getname_np(pthread_t thread, char *name, size_t len) {
    (void)thread;
    (void)name;
    (void)len;
    return -1;
}

#endif // __wasi__
