# Sandy

Create a light weight sandbox to hide `~/.ssh/` and `~/.config/`.

## Usage

### Interactive Shell
Launch an interactive `bash` shell inside the sandbox:
```bash
./sandy
```

### Direct Command Execution
Run a command directly in the sandbox:
```bash
./sandy echo "hello world"
```

### Executing Shell Commands
Run a shell command with shell features (pipes, redirects, built-ins, etc.):
```bash
./sandy -c "echo hello > /dev/null"
# or
./sandy bash -c "ls -la | grep src"
```

## How it works
The sandbox is implemented using **Bubblewrap** (`bwrap`), an unprivileged sandboxing tool for Linux:
1. **Host filesystem mapping**: The host root filesystem `/` is bound directly into the sandbox (`--bind / /`).
2. **Device node access**: The host `/dev` directory is bind-mounted with device permissions enabled (`--dev-bind /dev /dev`), ensuring access to standard nodes like `/dev/null` and pseudo-terminals (`/dev/pts`).
3. **Home directory mapping**: The user's home directory (`$HOME`) is bind-mounted directly into the sandbox (`--bind $HOME $HOME`), making any new file/directory creations or deletions directly visible on the host.
4. **Targeted isolation**:
   - If `~/.ssh` exists, it is overlaid with a temporary, in-memory `tmpfs` filesystem (`--tmpfs $HOME/.ssh`), rendering its host contents inaccessible inside the sandbox.
   - If `~/.config` exists, it is overlaid with a `tmpfs` (`--tmpfs $HOME/.config`), and only whitelisted entries (by default `gtk.*|git|nvim|gh|dconf|meld`) are selectively bind-mounted or symlinked back into the sandbox.

## Sandbox Command Options
You can configure the sandbox behavior when launching it:
* `-N`: Disable the git wrapper (which prevents VFS-isolated paths from appearing as deleted in `git status`).
* `-h`, `--help`: Show the command help message.

## Hiding directories from Git

### Motivation
When `$HOME` is bind-mounted directly, any directories we choose to isolate inside the sandbox (like `.ssh` or non-whitelisted `.config` files) are overlaid with empty `tmpfs` mounts.
If any of these hidden directories (or their resolved host targets, e.g. a symlinked `.ssh` pointing to a folder inside a Git dotfiles repository) are tracked by Git, running `git status` inside the sandbox would normally see these directories as completely empty and report all files inside them as deleted.

### Mechanism
To prevent `git status` from showing these files as deleted inside the sandbox, `sandy` automatically configures a transparent `git` wrapper:
1. **Hidden Paths Tracking**: The script tracks the host-resolved target paths of all hidden directories (e.g. your resolved `.ssh` directory target).
2. **Dynamic Git Wrapper**: If `git` is executed inside the sandbox, the wrapper resolves the root path of the Git repository you are working in (handling options like `-C`, `--git-dir`, and `--work-tree`).
3. **Repository-Specific Skip Worktree**: If the active repository contains any of the hidden paths, the wrapper creates a repository-specific temporary index file in `/tmp` (e.g., `/tmp/sandy-git-index-...`) based on the repository's `.git/index`.
4. It then runs `git update-index --skip-worktree` on all tracked files inside the hidden directories for that temporary index.
5. The wrapper exports `GIT_INDEX_FILE` to point to this temporary index and executes the real `git` binary.

This keeps `git status` output inside the sandbox completely clean and unaffected by VFS-isolated folders, while leaving the host's actual Git repository index completely untouched.

### Disabling the Wrapper
If you need to bypass the wrapper and run Git normally inside the sandbox, use the `-N` option:
```bash
./sandy -N git status
```
