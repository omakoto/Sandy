#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <linux/errno.h>

char LICENSE[] SEC("license") = "GPL";

// Task Local Storage map to store the sandbox flag directly in task_struct
struct {
    __uint(type, BPF_MAP_TYPE_TASK_STORAGE);
    __uint(map_flags, BPF_F_NO_PREALLOC);
    __type(key, int);   // task local storage key
    __type(value, u8);  // active flag
} sandboxed_tasks SEC(".maps");

// Temporary map used only to bootstrap the initial sandbox process
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, u32);
    __type(value, u8);
} bootstrap_pids SEC(".maps");

// Fast prefix match helper using __builtin_memcmp
static __always_inline bool matches_prefix(const char *str, int str_len, const char *prefix, int prefix_len) {
    if (str_len < prefix_len)
        return false;
    return __builtin_memcmp(str, prefix, prefix_len) == 0;
}

// 1. Hook into fork (task_alloc) to inherit the sandbox flag
SEC("lsm/task_alloc")
int BPF_PROG(propagate_sandbox, struct task_struct *task) {
    struct task_struct *parent = (struct task_struct *)bpf_get_current_task_btf();
    if (!parent)
        return 0;

    // Check if parent has the sandbox flag
    u8 *parent_active = bpf_task_storage_get(&sandboxed_tasks, parent, 0, 0);
    if (parent_active && *parent_active) {
        // Parent is sandboxed, set the flag on the new child task
        u8 *child_active = bpf_task_storage_get(&sandboxed_tasks, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
        if (child_active) {
            *child_active = 1;
        }
    }
    return 0;
}

// 2. Hook into file opens to enforce restrictions
SEC("lsm/file_open")
int BPF_PROG(restrict_sandbox_files, struct file *file, int mask) {
    struct task_struct *task = (struct task_struct *)bpf_get_current_task_btf();
    if (!task)
        return 0;

    // Check if this task is already marked as sandboxed
    u8 *active = bpf_task_storage_get(&sandboxed_tasks, task, 0, 0);
    bool is_sandboxed = (active && *active);

    // Bootstrap check: if not marked yet, check if this is the initial sandbox process
    if (!is_sandboxed) {
        u32 pid = task->tgid;
        u8 *boot = bpf_map_lookup_elem(&bootstrap_pids, &pid);
        if (boot) {
            // Initialize task storage for the initial process
            u8 *new_active = bpf_task_storage_get(&sandboxed_tasks, task, 0, BPF_LOCAL_STORAGE_GET_F_CREATE);
            if (new_active) {
                *new_active = 1;
                is_sandboxed = true;
            }
            // Immediately delete from bootstrap map to avoid any PID reuse issues
            bpf_map_delete_elem(&bootstrap_pids, &pid);
        }
    }

    if (!is_sandboxed) {
        return 0; // Allow: process is not sandboxed
    }

    // Resolve the absolute path of the file being opened
    char path[256];
    int len = bpf_d_path(&file->f_path, path, sizeof(path));
    if (len < 0) {
        return 0; // Default to allow if path resolution fails
    }

    // Blacklist: ~/.ssh (length 18)
    if (matches_prefix(path, len, "/home/omakoto/.ssh", 18)) {
        return -ENOENT;
    }

    // Whitelist: ~/.config (length 22)
    if (matches_prefix(path, len, "/home/omakoto/.config/", 22)) {
        const char *sub = path + 22;
        int sub_len = len - 22;
        if (matches_prefix(sub, sub_len, "git/", 4) ||
            matches_prefix(sub, sub_len, "nvim/", 5) ||
            matches_prefix(sub, sub_len, "gh/", 3) ||
            matches_prefix(sub, sub_len, "dconf/", 6) ||
            matches_prefix(sub, sub_len, "meld/", 5) ||
            matches_prefix(sub, sub_len, "gtk-3.0/", 8) ||
            matches_prefix(sub, sub_len, "gtk-4.0/", 8)) {
            return 0;
        }
        return -EACCES;
    }

    return 0;
}
