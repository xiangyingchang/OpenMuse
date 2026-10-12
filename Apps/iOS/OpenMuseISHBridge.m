// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 OpenMuse contributors.
//
// This host adapter uses the public host entry points in the pinned iSH fork:
// OpenMinis/ish-arm64, e6521d9cfe9cd48f19917fc3b23aea622ba358b4.

#import "OpenMuseISHBridge.h"
#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

@implementation OpenMuseISHBridge
- (void)executeCommand:(NSString *)command
           rootfsPath:(NSString *)rootfsPath
                mounts:(NSArray<NSDictionary<NSString *, id> *> *)mounts
               timeout:(NSTimeInterval)timeout
     maximumOutputBytes:(NSUInteger)maximumOutputBytes
 browserActionHandler:(OpenMuseISHBrowserActionHandler)browserActionHandler
              progress:(OpenMuseISHProgress)progress
            completion:(OpenMuseISHCompletion)completion {
    (void)command; (void)rootfsPath; (void)mounts; (void)timeout; (void)maximumOutputBytes; (void)browserActionHandler; (void)progress;
    completion([NSData data], 0, NO, NO,
               [NSError errorWithDomain:@"OpenMuseISH" code:4
                               userInfo:@{NSLocalizedDescriptionKey: @"iSH 目前只包含在 iPhone 真机版本中。"}]);
}
- (void)cancelCurrentExecution {}
- (void)prepareForExecution {}
@end

#else

#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netdb.h>
#include <resolv.h>
#include <os/proc.h>
#include <mach/mach.h>
#include <arpa/inet.h>
#import <Network/Network.h>

#define GUEST_ARM64 1
#include "asbestos/frame.h"
#include "kernel/calls.h"
#include "kernel/errno.h"
#include "kernel/fs.h"
#include "kernel/init.h"
#include "kernel/mm.h"
#include "kernel/personality.h"
#include "kernel/signal.h"
#include "kernel/task.h"
#include "kernel/native_offload.h"
#include "fs/dev.h"
#include "fs/devices.h"
#include "fs/path.h"
#include "fs/tty.h"
#define ISH_INTERNAL
#include "fs/fake.h"
#undef ISH_INTERNAL

enum { OpenMuseISHExited = 1, OpenMuseISHCrashed = 2 };

struct OpenMuseISHEvent {
    int type;
    int pid;
    int value;
};

static dispatch_queue_t OpenMuseISHKernelQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("org.openmuse.ish-kernel", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static int OpenMuseISHEventPipe[2] = {-1, -1};
static _Atomic int OpenMuseISHActivePID = -1;
static _Atomic bool OpenMuseISHCancelRequested = false;
static _Atomic int OpenMuseISHExitCode = 0;
static _Atomic bool OpenMuseISHBooted = false;
static _Atomic bool OpenMuseISHRuntimePoisoned = false;
static _Atomic uint64_t OpenMuseISHAvailableMemory = 0;
static _Atomic bool OpenMuseISHCriticalMemoryPressure = false;
static dispatch_source_t OpenMuseISHMemoryTimer;
static dispatch_source_t OpenMuseISHMemoryPressureSource;
static NSString *OpenMuseISHDNSHostPath;
static nw_path_monitor_t OpenMuseISHPathMonitor;
static pthread_mutex_t OpenMuseISHOutputLock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *OpenMuseISHOutput = NULL;
static size_t OpenMuseISHOutputLength = 0;
static size_t OpenMuseISHOutputCapacity = 0;
static size_t OpenMuseISHOutputLimit = 0;
static bool OpenMuseISHOutputTruncated = false;
static pthread_mutex_t OpenMuseISHBrowserHandlerLock = PTHREAD_MUTEX_INITIALIZER;
static OpenMuseISHBrowserActionHandler OpenMuseISHBrowserHandler = nil;
static bool OpenMuseISHBrowserOffloadRegistered = false;

static struct tty *OpenMuseISHConsoleTTYs[8];

extern __thread volatile sig_atomic_t in_jit;
extern __thread volatile uint64_t jit_saved_pc;
extern __thread int ish_thread_marker;
extern void jit_crash_trampoline(void);
extern _Atomic long anon_page_limit;

static const int OpenMuseISHHandledSignals[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP};
static struct sigaction OpenMuseISHPreviousSignals[4];
static struct sigaction OpenMuseISHInstalledSignalAction;
static char OpenMuseISHAlternateSignalStack[64 * 1024];

static void OpenMuseISHUpdateMemoryStatus(void) {
    size_t available = os_proc_available_memory();
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (available == 0 || task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
        return;
    }
    atomic_store_explicit(&OpenMuseISHAvailableMemory, available, memory_order_relaxed);
    ish_set_memory_status(info.phys_footprint + available, available,
                          atomic_load_explicit(&OpenMuseISHCriticalMemoryPressure, memory_order_relaxed));
}

static int OpenMuseISHForkGuard(void) {
    uint64_t available = atomic_load_explicit(&OpenMuseISHAvailableMemory, memory_order_relaxed);
    if (atomic_load_explicit(&OpenMuseISHCriticalMemoryPressure, memory_order_relaxed) ||
        (available > 0 && available < 64ull * 1024 * 1024)) {
        return _EAGAIN;
    }
    return 0;
}

static BOOL OpenMuseISHStartMemoryGovernor(void) {
    size_t available = os_proc_available_memory();
    size_t hostPageSize = (size_t)getpagesize();
    if (available == 0 || hostPageSize == 0) return NO;

    // Keep most of the current iOS headroom for SwiftUI, model responses and
    // the rest of the app. The upstream page counter is in guest pages, but
    // each committed page consumes one host page on iOS.
    long guestPages = (long)((double)available * 0.40 / (double)hostPageSize);
    if (guestPages < 1) guestPages = 1;
    ish_set_anon_page_limit(guestPages);
    ish_set_fork_guard(OpenMuseISHForkGuard);
    ish_set_fork_rate_limit(60, 120);
    OpenMuseISHUpdateMemoryStatus();
    if (!ish_footprint_mode()) return NO;

    if (OpenMuseISHMemoryTimer == nil) {
        OpenMuseISHMemoryTimer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(OpenMuseISHMemoryTimer, DISPATCH_TIME_NOW,
                                  250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(OpenMuseISHMemoryTimer, ^{
            OpenMuseISHUpdateMemoryStatus();
        });
        dispatch_resume(OpenMuseISHMemoryTimer);
    }
    if (OpenMuseISHMemoryPressureSource == nil) {
        OpenMuseISHMemoryPressureSource = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
            DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_event_handler(OpenMuseISHMemoryPressureSource, ^{
            unsigned long flags = dispatch_source_get_data(OpenMuseISHMemoryPressureSource);
            atomic_store_explicit(&OpenMuseISHCriticalMemoryPressure,
                                 (flags & DISPATCH_MEMORYPRESSURE_CRITICAL) != 0,
                                 memory_order_relaxed);
            OpenMuseISHUpdateMemoryStatus();
        });
        dispatch_resume(OpenMuseISHMemoryPressureSource);
    }
    return YES;
}

static int OpenMuseISHConsoleWrite(struct tty *tty, const void *bytes, size_t length, bool blocking) {
    (void)tty;
    (void)blocking;
    if (length == 0) return 0;
    pthread_mutex_lock(&OpenMuseISHOutputLock);
    size_t available = OpenMuseISHOutputLimit > OpenMuseISHOutputLength
        ? OpenMuseISHOutputLimit - OpenMuseISHOutputLength : 0;
    size_t copied = MIN(length, available);
    if (copied > 0 && OpenMuseISHOutputLength + copied > OpenMuseISHOutputCapacity) {
        size_t capacity = OpenMuseISHOutputCapacity == 0 ? 1024 : OpenMuseISHOutputCapacity;
        while (capacity < OpenMuseISHOutputLength + copied) capacity *= 2;
        uint8_t *next = realloc(OpenMuseISHOutput, capacity);
        if (next != NULL) {
            OpenMuseISHOutput = next;
            OpenMuseISHOutputCapacity = capacity;
        } else {
            copied = 0;
            OpenMuseISHOutputTruncated = true;
        }
    }
    if (copied > 0) {
        memcpy(OpenMuseISHOutput + OpenMuseISHOutputLength, bytes, copied);
        OpenMuseISHOutputLength += copied;
    }
    if (copied < length) OpenMuseISHOutputTruncated = true;
    pthread_mutex_unlock(&OpenMuseISHOutputLock);
    return (int)length;
}

static int OpenMuseISHConsoleInit(struct tty *tty) { (void)tty; return 0; }
static void OpenMuseISHConsoleCleanup(struct tty *tty) { (void)tty; }

static struct tty_driver_ops OpenMuseISHConsoleOps = {
    .init = OpenMuseISHConsoleInit,
    .write = OpenMuseISHConsoleWrite,
    .cleanup = OpenMuseISHConsoleCleanup,
};

static struct tty_driver OpenMuseISHConsoleDriver = {
    .ops = &OpenMuseISHConsoleOps,
    .major = TTY_CONSOLE_MAJOR,
    .ttys = OpenMuseISHConsoleTTYs,
    .limit = sizeof(OpenMuseISHConsoleTTYs) / sizeof(OpenMuseISHConsoleTTYs[0]),
};

static void OpenMuseISHWriteEvent(int type, int pid, int value) {
    if (OpenMuseISHEventPipe[1] < 0) return;
    struct OpenMuseISHEvent event = {.type = type, .pid = pid, .value = value};
    (void)write(OpenMuseISHEventPipe[1], &event, sizeof(event));
}

static void OpenMuseISHSendGroupSignal(int pid, int signalNumber) {
    if (pid <= 0) return;
    dispatch_sync(OpenMuseISHKernelQueue(), ^{
        (void)send_group_signal((dword_t)pid, signalNumber, SIGINFO_NIL);
    });
}

static void OpenMuseISHExitHook(struct task *task, int code) {
    int activePID = atomic_load_explicit(&OpenMuseISHActivePID, memory_order_relaxed);
    if (task != NULL && task->pid == activePID) {
        atomic_store_explicit(&OpenMuseISHExitCode, code, memory_order_relaxed);
        OpenMuseISHWriteEvent(OpenMuseISHExited, task->pid, code);
    }
}

static void OpenMuseISHChainSignal(int signalNumber, siginfo_t *info, void *context) {
    size_t index = 0;
    while (index < sizeof(OpenMuseISHHandledSignals) / sizeof(OpenMuseISHHandledSignals[0]) &&
           OpenMuseISHHandledSignals[index] != signalNumber) index++;
    if (index == sizeof(OpenMuseISHHandledSignals) / sizeof(OpenMuseISHHandledSignals[0])) return;
    const struct sigaction previous = OpenMuseISHPreviousSignals[index];
    if (previous.sa_handler == SIG_IGN) return;
    if (previous.sa_handler == SIG_DFL) {
        struct sigaction action = {0};
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        sigaction(signalNumber, &action, NULL);
        raise(signalNumber);
        return;
    }
    if ((previous.sa_flags & SA_SIGINFO) != 0) previous.sa_sigaction(signalNumber, info, context);
    else previous.sa_handler(signalNumber);
}

static void OpenMuseISHGuestCrash(int signalNumber, siginfo_t *info, void *context) {
#if defined(__aarch64__)
    if ((signalNumber == SIGSEGV || signalNumber == SIGBUS) && in_jit) {
        ucontext_t *uc = (ucontext_t *)context;
        uint64_t cpuPointer = uc->uc_mcontext->__ss.__x[1];
        uint64_t x7 = uc->uc_mcontext->__ss.__x[7];
        uint64_t x10 = uc->uc_mcontext->__ss.__x[10];
        uint64_t guestAddress = (x7 - x10) & 0xffffffffffffULL;
        uint64_t esr = uc->uc_mcontext->__es.__esr;
        struct cpu_state *cpu = (struct cpu_state *)(uintptr_t)cpuPointer;
        cpu->segfault_addr = guestAddress;
        cpu->segfault_was_write = (esr & 0x40) != 0;
        cpu->pc = (uint64_t)jit_saved_pc;
        struct fiber_frame *frame = (struct fiber_frame *)(uintptr_t)cpuPointer;
        uc->uc_mcontext->__ss.__sp = frame->jit_exit_sp;
        uc->uc_mcontext->__ss.__pc = (uint64_t)jit_crash_trampoline;
        sigset_t unblock;
        sigemptyset(&unblock);
        sigaddset(&unblock, signalNumber);
        sigprocmask(SIG_UNBLOCK, &unblock, NULL);
        return;
    }
#endif
    if (!ish_thread_marker) {
        OpenMuseISHChainSignal(signalNumber, info, context);
        return;
    }
    atomic_store_explicit(&OpenMuseISHRuntimePoisoned, true, memory_order_relaxed);
    OpenMuseISHWriteEvent(OpenMuseISHCrashed, atomic_load(&OpenMuseISHActivePID), signalNumber);
    // Do not let a guest fault terminate the containing iOS app. A crashed guest
    // thread cannot be resumed safely; the host disables iSH until app restart.
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, NULL);
    for (;;) pause();
}

static void OpenMuseISHDieHandler(const char *message) {
    if (message != NULL) (void)write(STDERR_FILENO, message, strlen(message));
    atomic_store_explicit(&OpenMuseISHRuntimePoisoned, true, memory_order_relaxed);
    OpenMuseISHWriteEvent(OpenMuseISHCrashed, atomic_load(&OpenMuseISHActivePID), SIGABRT_);
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, NULL);
    for (;;) pause();
}

static int OpenMuseISHInstallCrashHandlers(void) {
    static bool installed = false;
    if (installed) return 0;
    stack_t stack = {.ss_sp = OpenMuseISHAlternateSignalStack, .ss_size = sizeof(OpenMuseISHAlternateSignalStack)};
    if (sigaltstack(&stack, NULL) != 0) return -errno;
    OpenMuseISHInstalledSignalAction.sa_sigaction = OpenMuseISHGuestCrash;
    sigemptyset(&OpenMuseISHInstalledSignalAction.sa_mask);
    OpenMuseISHInstalledSignalAction.sa_flags = SA_SIGINFO | SA_ONSTACK;
    size_t installedCount = 0;
    for (size_t index = 0; index < sizeof(OpenMuseISHHandledSignals) / sizeof(OpenMuseISHHandledSignals[0]); index++) {
        if (sigaction(OpenMuseISHHandledSignals[index], &OpenMuseISHInstalledSignalAction,
                      &OpenMuseISHPreviousSignals[index]) != 0) {
            for (size_t rollback = 0; rollback < installedCount; rollback++) {
                sigaction(OpenMuseISHHandledSignals[rollback], &OpenMuseISHPreviousSignals[rollback], NULL);
            }
            return -errno;
        }
        installedCount++;
    }
    extern void (*die_handler)(const char *msg);
    die_handler = OpenMuseISHDieHandler;
    installed = true;
    return 0;
}

static int OpenMuseISHCreateDeviceNodes(void) {
    const struct { const char *path; int major; int minor; } devices[] = {
        {"/dev/tty1", TTY_CONSOLE_MAJOR, 1}, {"/dev/tty2", TTY_CONSOLE_MAJOR, 2},
        {"/dev/tty3", TTY_CONSOLE_MAJOR, 3}, {"/dev/tty4", TTY_CONSOLE_MAJOR, 4},
        {"/dev/tty5", TTY_CONSOLE_MAJOR, 5}, {"/dev/tty6", TTY_CONSOLE_MAJOR, 6},
        {"/dev/tty7", TTY_CONSOLE_MAJOR, 7}, {"/dev/tty", TTY_ALTERNATE_MAJOR, DEV_TTY_MINOR},
        {"/dev/console", TTY_ALTERNATE_MAJOR, DEV_CONSOLE_MINOR},
        {"/dev/ptmx", TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR},
        {"/dev/null", MEM_MAJOR, DEV_NULL_MINOR}, {"/dev/zero", MEM_MAJOR, DEV_ZERO_MINOR},
        {"/dev/full", MEM_MAJOR, DEV_FULL_MINOR}, {"/dev/random", MEM_MAJOR, DEV_RANDOM_MINOR},
        {"/dev/urandom", MEM_MAJOR, DEV_URANDOM_MINOR},
    };
    generic_mkdirat(AT_PWD, "/dev", 0755);
    generic_mkdirat(AT_PWD, "/dev/pts", 0755);
    for (size_t index = 0; index < sizeof(devices) / sizeof(devices[0]); index++) {
        int error = generic_mknodat(AT_PWD, devices[index].path, S_IFCHR | 0666,
                                    dev_make(devices[index].major, devices[index].minor));
        if (error < 0 && error != _EEXIST) return error;
    }
    return 0;
}

static int OpenMuseISHEnsureGuestDirectory(const char *path) {
    char buffer[512];
    size_t length = strlen(path);
    if (length == 0 || length >= sizeof(buffer) || path[0] != '/') return _EINVAL;
    memcpy(buffer, path, length + 1);
    for (char *cursor = buffer + 1; ; cursor++) {
        if (*cursor == '/' || *cursor == '\0') {
            char previous = *cursor;
            *cursor = '\0';
            int error = generic_mkdirat(AT_PWD, buffer, 0755);
            if (error < 0 && error != _EEXIST) return error;
            *cursor = previous;
            if (previous == '\0') break;
        }
    }
    return 0;
}

static int OpenMuseISHEnsureGuestStub(const char *path) {
    char parent[512];
    size_t length = strlen(path);
    if (length == 0 || length >= sizeof(parent) || path[0] != '/') return _EINVAL;
    memcpy(parent, path, length + 1);
    for (char *cursor = parent + 1; *cursor; cursor++) {
        if (*cursor != '/') continue;
        char previous = *cursor;
        *cursor = '\0';
        int error = generic_mkdirat(AT_PWD, parent, 0755);
        *cursor = previous;
        if (error < 0 && error != _EEXIST) return error;
    }
    struct fd *fd = generic_open(path, O_CREAT_ | O_WRONLY_, 0755);
    if (fd == NULL || IS_ERR(fd)) return _EIO;
    fd_close(fd);
    return 0;
}

static void OpenMuseISHSetBrowserActionHandler(OpenMuseISHBrowserActionHandler handler) {
    pthread_mutex_lock(&OpenMuseISHBrowserHandlerLock);
    OpenMuseISHBrowserHandler = [handler copy];
    pthread_mutex_unlock(&OpenMuseISHBrowserHandlerLock);
}

static OpenMuseISHBrowserActionHandler OpenMuseISHCopyBrowserActionHandler(void) {
    pthread_mutex_lock(&OpenMuseISHBrowserHandlerLock);
    OpenMuseISHBrowserActionHandler handler = [OpenMuseISHBrowserHandler copy];
    pthread_mutex_unlock(&OpenMuseISHBrowserHandlerLock);
    return handler;
}

static void OpenMuseISHWriteBrowserJSON(int fd, NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
    if (data == nil) return;
    const uint8_t *bytes = data.bytes;
    size_t remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) break;
        bytes += written;
        remaining -= (size_t)written;
    }
    (void)write(fd, "\n", 1);
}

static BOOL OpenMuseISHParseBrowserInteger(NSString *value, NSNumber **number) {
    const char *raw = value.UTF8String;
    if (raw == NULL || *raw == '\0') return NO;
    char *end = NULL;
    errno = 0;
    long long parsed = strtoll(raw, &end, 10);
    if (errno != 0 || end == raw || *end != '\0') return NO;
    *number = @(parsed);
    return YES;
}

static NSDictionary *OpenMuseISHBrowserInput(int argc, char **argv, NSString **errorMessage) {
    if (argc < 2) {
        *errorMessage = @"Use openmuse-browser-use <action> [options] or --json '<object>'.";
        return nil;
    }
    if (strcmp(argv[1], "--json") == 0) {
        if (argc != 3) {
            *errorMessage = @"--json expects exactly one JSON object argument.";
            return nil;
        }
        NSString *raw = [NSString stringWithUTF8String:argv[2]];
        NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
        id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil] : nil;
        if (![decoded isKindOfClass:NSDictionary.class]) {
            *errorMessage = @"--json must contain a JSON object.";
            return nil;
        }
        return decoded;
    }

    NSMutableDictionary *input = [@{@"action": [NSString stringWithUTF8String:argv[1]],
                                    @"tool_title": @"iSH 浏览器操作"} mutableCopy];
    NSDictionary<NSString *, NSString *> *stringOptions = @{
        @"--query": @"query", @"--url": @"url", @"--selector": @"selector",
        @"--text": @"text", @"--direction": @"direction", @"--item-selector": @"item_selector"
    };
    NSDictionary<NSString *, NSString *> *integerOptions = @{
        @"--amount": @"amount", @"--tab-id": @"tab_id", @"--tab_id": @"tab_id",
        @"--coordinate-x": @"coordinate_x", @"--coordinate_x": @"coordinate_x",
        @"--coordinate-y": @"coordinate_y", @"--coordinate_y": @"coordinate_y",
        @"--max-depth": @"max_depth", @"--scroll-count": @"scroll_count", @"--timeout": @"timeout"
    };
    for (int index = 2; index < argc; index++) {
        NSString *option = [NSString stringWithUTF8String:argv[index]];
        if (option == nil || index + 1 >= argc) {
            *errorMessage = @"Every browser option must have a value.";
            return nil;
        }
        NSString *value = [NSString stringWithUTF8String:argv[++index]];
        NSString *key = stringOptions[option];
        if (key != nil) {
            input[key] = value;
            continue;
        }
        key = integerOptions[option];
        if (key != nil) {
            NSNumber *number = nil;
            if (!OpenMuseISHParseBrowserInteger(value, &number)) {
                *errorMessage = [NSString stringWithFormat:@"%@ expects an integer.", option];
                return nil;
            }
            input[key] = number;
            continue;
        }
        *errorMessage = [NSString stringWithFormat:@"Unsupported browser option: %@", option];
        return nil;
    }
    return input;
}

static int OpenMuseISHBrowserUseMain(int argc, char **argv, int stdinFD, int stdoutFD, int stderrFD) {
    (void)stdinFD;
    static NSString *const help =
        @"openmuse-browser-use <action> [options]\n"
         "Actions: search, navigate, get_readable, get_text, get_page_info, get_backbone, find_elements, click, type, hover, scroll, scroll_and_collect, wait_for_dom_stable, list_tabs, new_tab, close_tab.\n"
         "Options: --query, --url, --selector, --text, --direction up|down, --amount, --tab-id, --coordinate-x, --coordinate-y, --max-depth, --scroll-count, --item-selector, --timeout.\n"
         "Also accepts --json '<browser_use arguments object>'. Tabs are shared with the current conversation's browser_use tool.\n";
    if (argc == 1 || (argc > 1 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0))) {
        NSData *data = [help dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length > 0) (void)write(stdoutFD, data.bytes, data.length);
        return 0;
    }

    NSString *errorMessage = nil;
    NSDictionary *input = OpenMuseISHBrowserInput(argc, argv, &errorMessage);
    if (input == nil) {
        OpenMuseISHWriteBrowserJSON(stdoutFD, @{@"success": @NO, @"error": errorMessage ?: @"Invalid browser arguments."});
        return 2;
    }
    NSData *inputData = [NSJSONSerialization dataWithJSONObject:input options:NSJSONWritingSortedKeys error:nil];
    if (inputData.length == 0 || inputData.length > 8192) {
        OpenMuseISHWriteBrowserJSON(stdoutFD, @{@"success": @NO, @"error": @"Browser arguments exceed the 8 KB limit."});
        return 2;
    }

    OpenMuseISHBrowserActionHandler handler = OpenMuseISHCopyBrowserActionHandler();
    if (handler == nil) {
        OpenMuseISHWriteBrowserJSON(stdoutFD, @{@"success": @NO, @"error": @"The iPhone browser bridge is unavailable in this execution."});
        return 1;
    }
    NSString *rawInput = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
    NSString *rawResult = handler(rawInput);
    NSData *resultData = [rawResult dataUsingEncoding:NSUTF8StringEncoding];
    if (resultData == nil || resultData.length == 0 || resultData.length > 12 * 1024) {
        OpenMuseISHWriteBrowserJSON(stdoutFD, @{@"success": @NO, @"error": @"Browser bridge returned no valid bounded result."});
        return 1;
    }
    const uint8_t *bytes = resultData.bytes;
    size_t remaining = resultData.length;
    while (remaining > 0) {
        ssize_t written = write(stdoutFD, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) break;
        bytes += written;
        remaining -= (size_t)written;
    }
    (void)write(stdoutFD, "\n", 1);
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:resultData options:NSJSONReadingFragmentsAllowed error:nil];
    return [result isKindOfClass:NSDictionary.class] && [result[@"success"] boolValue] ? 0 : 1;
}

/// Mirror OpenMinis: copy the active iOS resolver list into the guest instead
/// of resolving names through getaddrinfo and synthesizing DNS answers. This
/// preserves VPN/fake-IP DNS behavior for the guest's subsequent socket flow.
static BOOL OpenMuseISHWriteSystemDNSFile(void) {
    NSString *hostPath = OpenMuseISHDNSHostPath;
    if (hostPath.length == 0) return NO;

    NSMutableString *resolvConf = [NSMutableString new];
    struct __res_state resolver;
    memset(&resolver, 0, sizeof(resolver));
    int serverCount = 0;
    int written = 0;
    BOOL initialized = res_ninit(&resolver) == 0;
    if (initialized) {
        NSMutableArray<NSString *> *searchDomains = [NSMutableArray new];
        for (int index = 0; index < MAXDNSRCH && resolver.dnsrch[index] != NULL; index++) {
            NSString *domain = [NSString stringWithUTF8String:resolver.dnsrch[index]];
            if (domain.length > 0) [searchDomains addObject:domain];
        }
        if (searchDomains.count > 0) {
            [resolvConf appendFormat:@"search %@\n", [searchDomains componentsJoinedByString:@" "]];
        }

        union res_sockaddr_union servers[NI_MAXSERV];
        serverCount = res_getservers(&resolver, servers, NI_MAXSERV);
        char address[NI_MAXHOST] = {0};
        for (int index = 0; index < serverCount; index++) {
            union res_sockaddr_union server = servers[index];
            if (server.sin.sin_len == 0) continue;
            if (getnameinfo((struct sockaddr *)&server.sin, server.sin.sin_len,
                            address, sizeof(address), NULL, 0, NI_NUMERICHOST) == 0) {
                [resolvConf appendFormat:@"nameserver %s\n", address];
                written++;
            }
        }
        res_nclose(&resolver);
    }

    // This is the same fallback used by the pinned OpenMinis iSH host adapter.
    if ([resolvConf rangeOfString:@"nameserver"].location == NSNotFound) {
        [resolvConf appendString:@"nameserver 8.8.8.8\nnameserver 8.8.4.4\n"];
    }

    NSError *error = nil;
    BOOL saved = [[resolvConf dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:hostPath options:NSDataWritingAtomic error:&error];
    if (!saved) {
        fprintf(stderr, "OpenMuse iSH: could not refresh system DNS (%s/%d): %s\n",
                initialized ? "resolver" : "fallback", written,
                error.localizedDescription.UTF8String ?: "unknown error");
    }
    return saved;
}

static BOOL OpenMuseISHRefreshDNSFile(NSString *rootfsPath) {
    NSString *runtimeDirectory = [rootfsPath stringByDeletingLastPathComponent];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:runtimeDirectory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        fprintf(stderr, "OpenMuse iSH: could not create DNS directory: %s\n",
                error.localizedDescription.UTF8String ?: "unknown error");
        return NO;
    }
    OpenMuseISHDNSHostPath = [runtimeDirectory stringByAppendingPathComponent:@"resolv.conf"];
    return OpenMuseISHWriteSystemDNSFile();
}

static void OpenMuseISHStartNetworkMonitor(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        OpenMuseISHPathMonitor = nw_path_monitor_create();
        if (OpenMuseISHPathMonitor == NULL) return;
        nw_path_monitor_set_update_handler(OpenMuseISHPathMonitor, ^(nw_path_t path) {
            (void)path;
            (void)OpenMuseISHWriteSystemDNSFile();
        });
        nw_path_monitor_set_queue(OpenMuseISHPathMonitor,
                                  dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        nw_path_monitor_start(OpenMuseISHPathMonitor);
    });
}

static int OpenMuseISHBoot(NSString *rootfsPath) {
    if (atomic_load(&OpenMuseISHRuntimePoisoned)) return _EIO;
    if (atomic_load(&OpenMuseISHBooted))
        return OpenMuseISHRefreshDNSFile(rootfsPath) ? 0 : _EIO;
    if (OpenMuseISHEventPipe[0] < 0) {
        if (pipe(OpenMuseISHEventPipe) != 0) return -errno;
        fcntl(OpenMuseISHEventPipe[0], F_SETFL, O_NONBLOCK);
        fcntl(OpenMuseISHEventPipe[1], F_SETFL, O_NONBLOCK);
    }
    NSString *dataPath = [rootfsPath stringByAppendingPathComponent:@"data"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[rootfsPath stringByAppendingPathComponent:@"meta.db"]] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:dataPath]) return _ENOENT;
    if (!OpenMuseISHRefreshDNSFile(rootfsPath)) return _EIO;
    OpenMuseISHStartNetworkMonitor();

    current = NULL;
    int error = mount_root(&fakefs, dataPath.fileSystemRepresentation);
    if (error < 0) return error;
    char canonicalPath[PATH_MAX];
    if (realpath(dataPath.fileSystemRepresentation, canonicalPath) != NULL) {
        fakefs_set_rootfs_data_path(canonicalPath);
    }
    error = become_first_process();
    if (error < 0) { current = NULL; return error; }
    current->thread = pthread_self();

    error = OpenMuseISHCreateDeviceNodes();
    if (error < 0) { current = NULL; return error; }
    generic_mkdirat(AT_PWD, "/proc", 0555);
    generic_mkdirat(AT_PWD, "/var", 0755);
    generic_mkdirat(AT_PWD, "/var/minis", 0755);
    error = do_mount(&procfs, "proc", "/proc", "", 0);
    if (error < 0) { current = NULL; return error; }
    error = do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);
    if (error < 0) { current = NULL; return error; }

    error = fakefs_bind_mount("/etc/resolv.conf", OpenMuseISHDNSHostPath.fileSystemRepresentation, true);
    if (error < 0) { current = NULL; return error; }

    tty_drivers[TTY_CONSOLE_MAJOR] = &OpenMuseISHConsoleDriver;
    set_console_device(TTY_CONSOLE_MAJOR, 1);
    error = create_stdio("/dev/console", TTY_CONSOLE_MAJOR, 1);
    if (error < 0) { current = NULL; return error; }
    exit_hook = OpenMuseISHExitHook;
    error = OpenMuseISHInstallCrashHandlers();
    if (error < 0) { current = NULL; return error; }
    if (!OpenMuseISHStartMemoryGovernor()) { current = NULL; return _ENOMEM; }

    error = OpenMuseISHEnsureGuestStub("/usr/local/bin/openmuse-browser-use");
    if (error < 0) { current = NULL; return error; }
    if (!OpenMuseISHBrowserOffloadRegistered) {
        if (native_offload_add_handler("openmuse-browser-use", OpenMuseISHBrowserUseMain) < 0) {
            current = NULL;
            return _EIO;
        }
        OpenMuseISHBrowserOffloadRegistered = true;
    }

    // iSH maps guest AF_UNIX sockets to host files; keep those files inside
    // the app's temporary container directory instead of the host /tmp.
    extern const char *sock_tmp_prefix;
    NSString *prefix = [NSTemporaryDirectory() stringByAppendingString:@"openmuse-ish-"];
    sock_tmp_prefix = strdup(prefix.fileSystemRepresentation);
    current = NULL;
    atomic_store(&OpenMuseISHBooted, true);
    return 0;
}

static int OpenMuseISHBindMounts(NSArray<NSDictionary<NSString *, id> *> *mounts) {
    for (NSDictionary<NSString *, id> *mount in mounts) {
        NSString *guestPath = mount[@"guestPath"];
        NSString *hostPath = mount[@"hostPath"];
        BOOL readOnly = [mount[@"readOnly"] boolValue];
        if (![guestPath isKindOfClass:NSString.class] ||
            ![hostPath isKindOfClass:NSString.class] ||
            ![guestPath hasPrefix:@"/var/minis/"] ||
            ![[NSFileManager defaultManager] fileExistsAtPath:hostPath]) return _EINVAL;
        int error = OpenMuseISHEnsureGuestDirectory(guestPath.fileSystemRepresentation);
        if (error < 0) return error;
        error = fakefs_bind_mount(guestPath.fileSystemRepresentation,
                                  hostPath.fileSystemRepresentation,
                                  readOnly);
        if (error < 0) return error;
    }
    return 0;
}

static NSData *OpenMuseISHCopyOutput(BOOL *truncated) {
    pthread_mutex_lock(&OpenMuseISHOutputLock);
    NSData *data = [NSData dataWithBytes:OpenMuseISHOutput length:OpenMuseISHOutputLength];
    if (truncated != NULL) *truncated = OpenMuseISHOutputTruncated;
    pthread_mutex_unlock(&OpenMuseISHOutputLock);
    return data;
}

static void OpenMuseISHResetOutput(NSUInteger maximumBytes) {
    pthread_mutex_lock(&OpenMuseISHOutputLock);
    OpenMuseISHOutputLength = 0;
    OpenMuseISHOutputLimit = maximumBytes;
    OpenMuseISHOutputTruncated = false;
    pthread_mutex_unlock(&OpenMuseISHOutputLock);
}

static void OpenMuseISHDrainEvents(void) {
    struct OpenMuseISHEvent ignored;
    while (read(OpenMuseISHEventPipe[0], &ignored, sizeof(ignored)) == sizeof(ignored)) {}
}

static int OpenMuseISHStartCommand(NSString *command, NSArray<NSDictionary<NSString *, id> *> *mounts,
                                   int *pidOut) {
    current = pid_get_task(1);
    if (current == NULL) return _ESRCH;
    int error = OpenMuseISHBindMounts(mounts);
    if (error < 0) { current = NULL; return error; }
    struct fd *workingDirectory = generic_open("/var/minis/workspace", O_RDONLY_ | O_DIRECTORY_, 0);
    if (IS_ERR(workingDirectory)) { current = NULL; return (int)PTR_ERR(workingDirectory); }

    error = become_new_init_child();
    if (error < 0) { fd_close(workingDirectory); current = NULL; return error; }
    fs_chdir(current->fs, workingDirectory);
    // fs_chdir takes ownership of the fd and closes the previous cwd.
    current->group->personality = ADDR_NO_RANDOMIZE_;
    error = create_stdio("/dev/console", TTY_CONSOLE_MAJOR, 1);
    if (error < 0) { current = NULL; return error; }

    const char *argvValues[] = {"/bin/sh", "-lc", command.UTF8String};
    char argv[8192];
    size_t argvLength = 0;
    for (size_t index = 0; index < 3; index++) {
        size_t argumentLength = strlen(argvValues[index]) + 1;
        if (argvLength + argumentLength >= sizeof(argv)) { current = NULL; return _E2BIG; }
        memcpy(argv + argvLength, argvValues[index], argumentLength);
        argvLength += argumentLength;
    }
    argv[argvLength] = '\0';
    const char envp[] = "HOME=/root\0TERM=dumb\0PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\0LANG=C.UTF-8\0OPENMUSE_WORKSPACE=/var/minis/workspace\0\0";
    error = do_execve("/bin/sh", 3, argv, envp);
    if (error < 0) { current = NULL; return error; }
    int pid = current->pid;
    atomic_store(&OpenMuseISHActivePID, pid);
    atomic_store(&OpenMuseISHExitCode, 0);
    if (atomic_load(&OpenMuseISHCancelRequested)) {
        atomic_store(&OpenMuseISHActivePID, -1);
        current = NULL;
        return _EINTR;
    }
    error = task_start(current);
    current = NULL;
    if (error < 0) {
        atomic_store(&OpenMuseISHActivePID, -1);
        return error;
    }
    *pidOut = pid;
    return 0;
}

static BOOL OpenMuseISHWaitForEvent(int timeoutMilliseconds, struct OpenMuseISHEvent *event) {
    struct pollfd descriptor = {.fd = OpenMuseISHEventPipe[0], .events = POLLIN};
    int result;
    do { result = poll(&descriptor, 1, timeoutMilliseconds); } while (result < 0 && errno == EINTR);
    if (result <= 0 || (descriptor.revents & POLLIN) == 0) return NO;
    return read(OpenMuseISHEventPipe[0], event, sizeof(*event)) == sizeof(*event);
}

static void OpenMuseISHUnmount(NSArray<NSDictionary<NSString *, id> *> *mounts) {
    current = pid_get_task(1);
    if (current == NULL) return;
    for (NSDictionary<NSString *, id> *mount in mounts) {
        NSString *guestPath = mount[@"guestPath"];
        if ([guestPath isKindOfClass:NSString.class] && [guestPath hasPrefix:@"/var/minis/"]) {
            fakefs_bind_unmount(guestPath.fileSystemRepresentation);
        }
    }
    current = NULL;
}

@implementation OpenMuseISHBridge

- (void)cancelCurrentExecution {
    atomic_store(&OpenMuseISHCancelRequested, true);
    int pid = atomic_load(&OpenMuseISHActivePID);
    OpenMuseISHSendGroupSignal(pid, SIGTERM_);
}

- (void)prepareForExecution {
    atomic_store(&OpenMuseISHCancelRequested, false);
    atomic_store(&OpenMuseISHActivePID, -1);
}

- (void)executeCommand:(NSString *)command
           rootfsPath:(NSString *)rootfsPath
                mounts:(NSArray<NSDictionary<NSString *, id> *> *)mounts
               timeout:(NSTimeInterval)timeout
     maximumOutputBytes:(NSUInteger)maximumOutputBytes
 browserActionHandler:(OpenMuseISHBrowserActionHandler)browserActionHandler
              progress:(OpenMuseISHProgress)progress
            completion:(OpenMuseISHCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (atomic_load(&OpenMuseISHRuntimePoisoned)) {
            completion([NSData data], 0, NO, NO,
                       [NSError errorWithDomain:@"OpenMuseISH" code:1 userInfo:@{NSLocalizedDescriptionKey: @"iSH 遇到 guest 崩溃；请重新打开 App 后再试。"}]);
            return;
        }
        __block int bootError = 0;
        dispatch_sync(OpenMuseISHKernelQueue(), ^{ bootError = OpenMuseISHBoot(rootfsPath); });
        if (bootError < 0) {
            completion([NSData data], 0, NO, NO,
                       [NSError errorWithDomain:@"OpenMuseISH" code:bootError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"iSH 启动失败（%d）。", bootError]}]);
            return;
        }

        OpenMuseISHDrainEvents();
        OpenMuseISHResetOutput(maximumOutputBytes);
        OpenMuseISHSetBrowserActionHandler(browserActionHandler);
        __block int pid = -1;
        __block int startError = 0;
        dispatch_sync(OpenMuseISHKernelQueue(), ^{
            startError = OpenMuseISHStartCommand(command, mounts, &pid);
        });
        if (startError < 0) {
            OpenMuseISHSetBrowserActionHandler(nil);
            dispatch_sync(OpenMuseISHKernelQueue(), ^{ OpenMuseISHUnmount(mounts); });
            completion([NSData data], 0, NO, NO,
                       [NSError errorWithDomain:@"OpenMuseISH" code:startError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"iSH 无法启动命令（%d）。", startError]}]);
            return;
        }

        struct OpenMuseISHEvent event = {0};
        dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0, timeout) * NSEC_PER_SEC));
        BOOL received = NO;
        size_t lastProgressLength = 0;
        while (!received) {
            dispatch_time_t now = dispatch_time(DISPATCH_TIME_NOW, 0);
            if (now >= deadline) break;
            uint64_t remainingNanoseconds = deadline - now;
            int waitMilliseconds = (int)MIN(250, MAX(1, (remainingNanoseconds + NSEC_PER_MSEC - 1) / NSEC_PER_MSEC));
            received = OpenMuseISHWaitForEvent(waitMilliseconds, &event);
            @autoreleasepool {
                NSData *snapshot = OpenMuseISHCopyOutput(NULL);
                if (snapshot.length > lastProgressLength) {
                    progress(snapshot);
                    lastProgressLength = snapshot.length;
                }
            }
        }
        BOOL timedOut = !received;
        if (!received) {
            OpenMuseISHSendGroupSignal(pid, SIGTERM_);
            received = OpenMuseISHWaitForEvent(500, &event);
            if (!received) {
                OpenMuseISHSendGroupSignal(pid, SIGKILL_);
                received = OpenMuseISHWaitForEvent(1000, &event);
            }
        } else if (event.type == OpenMuseISHExited) {
            // A non-interactive shell can leave background jobs behind. Stop
            // every process in its session before releasing the mounted files.
            OpenMuseISHSendGroupSignal(pid, SIGTERM_);
            usleep(100 * 1000);
            OpenMuseISHSendGroupSignal(pid, SIGKILL_);
        }

        OpenMuseISHSetBrowserActionHandler(nil);

        BOOL guestCrashed = event.type == OpenMuseISHCrashed || atomic_load(&OpenMuseISHRuntimePoisoned);
        BOOL guestDidNotStop = timedOut && !received;
        if (guestDidNotStop) {
            atomic_store(&OpenMuseISHRuntimePoisoned, true);
            guestCrashed = YES;
        }
        if (!guestCrashed) {
            dispatch_sync(OpenMuseISHKernelQueue(), ^{ OpenMuseISHUnmount(mounts); });
        }
        atomic_store(&OpenMuseISHActivePID, -1);
        BOOL truncated = NO;
        NSData *output = OpenMuseISHCopyOutput(&truncated);
        if (output.length > lastProgressLength) progress(output);
        NSError *error = guestDidNotStop
            ? [NSError errorWithDomain:@"OpenMuseISH" code:3 userInfo:@{NSLocalizedDescriptionKey: @"iSH guest 超时后没有及时停止；为避免后台命令继续访问文件，运行环境已停用，请重新打开 App。"}]
            : guestCrashed
            ? [NSError errorWithDomain:@"OpenMuseISH" code:2 userInfo:@{NSLocalizedDescriptionKey: @"iSH guest 崩溃，运行环境已停用；重新打开 App 后可以恢复。"}]
            : nil;
        completion(output, atomic_load(&OpenMuseISHExitCode), timedOut, truncated, error);
    });
}

@end

#endif // TARGET_OS_SIMULATOR
