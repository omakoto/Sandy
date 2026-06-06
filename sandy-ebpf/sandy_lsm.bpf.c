#include <vmlinux.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

// BPF Map to track process IDs that are sandboxed
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 10240);
    __type(key, u32);   // PID
    __type(value, u8);  // Active flag
} sandboxed_pids SEC(".maps");

// Fast prefix match helper
static __always_inline bool has_prefix(const char *str, const char *prefix) {
    while (*prefix) {
        if (*str != *prefix)
            return false;
        str++;
        prefix++;
    }
    return true;
}

SEC("lsm/file_open")
int BPF_PROG(restrict_sandbox_files, struct file *file, int mask) {
    // 1. Check if the current process is inside the sandbox.
    // If the PID is not in our BPF map, allow access.
    u32 pid = bpf_get_current_pid_tgid() >> 32;
    u8 *active = bpf_map_lookup_elem(&sandboxed_pids, &pid);
    if (!active) {
        return 0; // Allow: process is not sandboxed
    }

    // 2. Resolve the absolute path of the file being opened
    char path[256];
    int len = bpf_d_path(&file->f_path, path, sizeof(path));
    if (len < 0) {
        return 0; // If path resolution fails, default to allow
    }

    // 3. Blacklist: Disallow any access to ~/.ssh
    if (has_prefix(path, "/home/omakoto/.ssh")) {
        return -ENOENT; // Returns "No such file or directory"
    }

    // 4. Whitelist: Block all under ~/.config except whitelisted subdirectories
    if (has_prefix(path, "/home/omakoto/.config/")) {
        if (has_prefix(path, "/home/omakoto/.config/git/") ||
            has_prefix(path, "/home/omakoto/.config/nvim/") ||
            has_prefix(path, "/home/omakoto/.config/gh/") ||
            has_prefix(path, "/home/omakoto/.config/dconf/") ||
            has_prefix(path, "/home/omakoto/.config/meld/") ||
            has_prefix(path, "/home/omakoto/.config/gtk-3.0/") ||
            has_prefix(path, "/home/omakoto/.config/gtk-4.0/")) {
            return 0; // Allow whitelisted paths
        }
        return -EACCES; // Block all other configurations with "Permission Denied"
    }

    return 0; // Allow all other system paths
}
