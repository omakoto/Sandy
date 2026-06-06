# Sandy

Create a light weight sandbox to hide `~/.ssh/` and `~/.config/`.

## Usage

### Interactive Shell
Launch an interactive `bash` shell inside the sandbox:
```bash
./sandy.sh
```

### Direct Command Execution
Run a command directly in the sandbox:
```bash
./sandy.sh echo "hello world"
```

### Executing Shell Commands
Run a shell command with shell features (pipes, redirects, built-ins, etc.):
```bash
./sandy.sh -c "echo hello > /dev/null"
# or
./sandy.sh bash -c "ls -la | grep src"
```

## How it works
The sandbox is implemented using **Bubblewrap** (`bwrap`), an unprivileged sandboxing tool for Linux:
1. **Host filesystem mapping**: The host root filesystem `/` is bound directly into the sandbox (`--bind / /`).
2. **Device node access**: The host `/dev` directory is bind-mounted with device permissions enabled (`--dev-bind /dev /dev`), ensuring access to standard nodes like `/dev/null` and pseudo-terminals (`/dev/pts`).
3. **Home directory masking**: The user's home directory (`$HOME`) is overlaid with an empty, in-memory `tmpfs` filesystem.
4. **Targeted population**: The script loops through all files and folders in the host `$HOME`. For each entry:
   - If it is `.ssh` or `.config`, it is skipped (leaving it non-existent in the sandbox).
   - If it is a symlink, it is recreated inside the sandbox via the `--symlink` option.
   - For all other entries, they are bind-mounted (`--bind`) to make them visible and writable inside the sandbox.
