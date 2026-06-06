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
* `-h`, `--help`: Show the command help message.
