# fish-helix
helix key bindings for fish

**This fork is updated for Fish 4.0+ compatibility.** For Fish 3.x, use the [original repository](https://github.com/sshilovsky/fish-helix).

# Installation

Dependencies: **fish >= 4.0**, GNU tools¹, perl.

1. Copy `functions` directory as `~/.config/fish/functions`.
2. Run `fish_helix_key_bindings`.

To undo, run `fish_default_key_bindings`.

¹ Should work with POSIX, but untested. Report any issues.

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

# Tests

1. Install tmux and inotify-tools.
2. Run `run-tests` script

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
