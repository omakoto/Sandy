# Sandy eBPF Module

This subdirectory contains an alternative implementation of the `sandy` file access isolation using Linux **eBPF (Extended Berkeley Packet Filter)**. 

Specifically, it uses **LSM BPF** (Linux Security Modules via BPF) to intercept the `file_open` security hook inside the kernel. This allows us to hide or restrict access to specific folders (like `~/.ssh` and non-whitelisted paths under `~/.config`) dynamically for specified process IDs, without modifying the filesystem layout, mount namespaces, or directory symlinks.

### Motivation & Benefits
- **No Git Deletion Side Effects**: Because file access is blocked by returning error codes (`ENOENT` or `EACCES`) at the kernel VFS layer rather than by overlaying empty directories via `tmpfs`, the actual directories on the host remain fully intact. Consequently, `git status` inside a Git repository (like your dotfiles) works normally and does not report hidden folders as deleted.
- **Nested Sandbox Compatibility**: Since it does not use bubblewrap or namespaces, it has no nesting constraints and can run on top of any other sandbox environment (like `antigravity-cli`'s sandbox, Docker, etc.).
- **Unprivileged Writing**: Once the eBPF program is loaded by root, the PID control map permissions are set to `666`, allowing unprivileged CLI tools to register and deregister their sandboxed process IDs.

---

### System Requirements
1. **Linux Kernel 5.7+** (with LSM BPF support enabled).
2. **BTF (BPF Type Format) Enabled**: Ensure `/sys/kernel/btf/vmlinux` exists.
3. **LSM BPF Enabled**: `bpf` must be listed in `/sys/kernel/security/lsm` (or enabled in kernel boot options: `lsm=landlock,lockdown,yama,integrity,bpf`).
4. **Build Tools**: `clang`, `llvm`, `make`, and `bpftool`.

---

### Building and Loading

To build the program, mount the BPF filesystem, load it, and set map permissions:

```bash
# Run the install script (requires root)
sudo ./install.sh
```

This will:
1. Generate `vmlinux.h` from your running kernel.
2. Compile `sandy_lsm.bpf.c` to `sandy_lsm.bpf.o`.
3. Mount the BPF filesystem if not already mounted.
4. Load the LSM program and pin it to `/sys/fs/bpf/sandy/sandy_lsm`.
5. Pin the PIDs hash map to `/sys/fs/bpf/sandy/sandboxed_pids` and set permissions to `666`.

To unload:
```bash
sudo rm -rf /sys/fs/bpf/sandy
```

---

### Testing

Verify the kernel-level restrictions by running the test script:

```bash
sudo ./test.sh
```

The test script:
1. Spawns a background shell process.
2. Registers its process ID (PID) in the `/sys/fs/bpf/sandy/sandboxed_pids` map.
3. Runs commands inside that process to test:
   - Reading normal directories (PASSED).
   - Reading `~/.ssh/config` (should fail with `No such file or directory` / `ENOENT`).
   - Reading `~/.config/git/config` (whitelisted, should succeed).
   - Reading a non-whitelisted `.config` directory (should fail with `Permission denied` / `EACCES`).
4. Unregisters the PID and cleans up.

---

### Integrating with a Sandbox
To enforce these file restrictions on any process or sandbox:
1. Load the eBPF module via `sudo ./install.sh`.
2. Write the target shell's process ID (PID) into the BPF map:
   ```bash
   # Format the PID as 4-byte little-endian hex bytes and write it to the map
   pid=$$
   key_bytes=$(printf "%08x" $pid | sed 's/\(..\)\(..\)\(..\)\(..\)/\4 \3 \2 \1/')
   bpftool map update pinned /sys/fs/bpf/sandy/sandboxed_pids key $key_bytes value 01
   ```
3. Run the target commands.
4. Clean up on exit:
   ```bash
   bpftool map delete pinned /sys/fs/bpf/sandy/sandboxed_pids key $key_bytes
   ```
