# fish-helix
helix key bindings for fish

**This fork is updated for Fish 4.0+ compatibility.** For Fish 3.x, use the [original repository](https://github.com/sshilovsky/fish-helix).

# Installation

**Dependencies:**
- **fish >= 4.0**
- **GNU sed** (see platform-specific instructions below)
- **perl**

**Installing GNU sed:**
- **macOS:** `brew install gnu-sed`
- **Linux:** Usually pre-installed. If not:
  - Debian/Ubuntu: `sudo apt-get install sed`
  - Fedora/RHEL: `sudo dnf install sed`
  - Arch: `sudo pacman -S sed`
- **BSD:** `pkg install gsed` (FreeBSD) or `pkgin install gsed` (NetBSD)

The functions auto-detect and use `gsed` on macOS/BSD and `sed` on Linux.

**Installation Steps:**

1. Copy the function files to your fish functions directory:
   ```bash
   cp functions/*.fish ~/.config/fish/functions/
   ```

2. Activate helix key bindings (choose one):

   **Option A - Try it out (current session only):**
   ```fish
   fish_helix_key_bindings
   ```

   **Option B - Make it permanent:**

   Add this line to `~/.config/fish/config.fish`:
   ```fish
   fish_helix_key_bindings
   ```
   Then restart your shell or run `source ~/.config/fish/config.fish`

**To undo:** Run `fish_default_key_bindings` (or remove the line from config.fish for permanent removal).

## Fish 4.0 Compatibility

This fork includes the following fixes for Fish 4.0:
- Removed deprecated `-k` flag syntax for key bindings
- Fixed tilde expansion bug that caused parse errors
- Worked around Fish 4.0 parser bug with capital F escape sequences

### Known Limitations

Due to a Fish 4.0 parser bug, the following key combinations are not available:
- `F` + `Escape` (cancel "find previous char" operation)
- `F` + `Enter` (find previous to newline)

All other helix key bindings work normally (~95% functionality).

## Cross-Platform Compatibility

The functions automatically detect the correct `sed` command:
- **macOS**: Uses `gsed` (GNU sed) if available
- **Linux**: Uses standard `sed`

If `gsed` is not found on macOS, you'll receive a helpful error message with installation instructions. The detection happens lazily on first use and is cached for the session, so there's no performance overhead.

# Tests

**Requirements:**
- **tmux** - Session management for tests

**Run tests:**
```bash
./run-tests
```

The test suite uses simple polling for cross-platform compatibility (no external file-watching tools required).

# Configuration

`fish_helix_command` function provides some helix-like actions. Use it for custom bindings.

## IMPORTANT!!!

When defining your own bindings using fish_helix_command, be aware that it can break
stuff sometimes.

It is safe to define a binding consisting of a lone call to fish_helix_command.
Calls to other functions and executables are allowed along with it, granted they don't mess
with fish's commandline buffer.

Mixing multiple fish_helix_commandline and commandline calls in one binding MAY trigger issues.
Nothing serious, but don't be surprised. Just test it.
