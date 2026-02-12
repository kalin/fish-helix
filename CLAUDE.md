# Fish-Helix Development Guide

## Project Overview

**fish-helix** brings Helix/Vim-style modal editing to the Fish shell command line. It provides:
- Normal, Visual, and Insert modes
- Helix-compatible key bindings (hjkl, w/b/e word motions, gg/G, etc.)
- Visual selections with yank/paste operations
- Find/till operations (f/F/t/T)

**Current Status (as of 2025-10-30):**
- ✅ Core functionality works in Fish 4.0+
- ✅ Test suite runs reliably on macOS and Linux
- ⚠️ 15 tests failing, 2 broken (known implementation gaps)
- ⚠️ Some multi-line command editing issues

## How The Test System Works

### Architecture

Tests use **tmux + Fish in private mode** to simulate interactive sessions:

```
run-tests script
  ↓
  For each test file:
    ↓
    _run.fish
      ↓
      1. Start tmux session with fish --private -i
      2. Source fish-helix functions
      3. Source _init.fish (test framework)
      4. Source test file (simulates keypresses)
      5. Wait 1.5s for fish to initialize
      6. Send F12 to finalize test
      7. Poll for result file (up to 1s)
      8. Kill tmux session
      9. Check result/failure/fixed/broken files
```

### Key Test Files

**`tests/_init.fish`** - Test framework initialization
- Defines test functions: `_input`, `_buffer`, `_cursor`, `_selection`, `_mode`
- Sets up F9/F11/F12 key bindings:
  - **F9** (`\e[20~`) - Runs a `check` to verify expected state
  - **F11** (`\e[23~`) - Switches to Normal mode (like Escape)
  - **F12** (`\e[24~`) - Calls `validate` and creates result file
- Variable `$tmux` points to tmux socket for sending keys

**`tests/_run.fish`** - Test runner
- Creates tmux session with unique socket
- Sources all fish-helix functions
- Waits 1.5s for initialization (critical timing!)
- Sends F12 via tmux send-keys
- Polls for `$temp_dir/result/result` file (up to 1s)
- **IMPORTANT**: Test MUST create result file or it's considered a timeout/failure
- Checks for failure markers: `$temp_dir/failure`, `$temp_dir/fixed`, `$temp_dir/broken`

**`tests/_done.fish`** - Test finalization
- **NOT USED ANYMORE** - F12 is sent from `_run.fish` instead
- Previously sent F12 during `-C` init, but that was too early

**`run-tests`** - Main test runner
- Runs `_example_test.fish` first - if it fails, exits immediately
- Then runs all other tests
- Outputs progress for each test
- Final summary: "N tests finished. X failed and Y broken."

### Test File Format

Example (`tests/word-motions/w-through-newline.fish`):
```fish
# Key input:
_input hello Line world Line ! Normal gg ww
# Expected state:
_cursor 10
_selection world
```

**Special _input sequences:**
- `Normal` → Sends F11 (switch to Normal mode)
- `Line` → Sends F11 then 'o' (Normal mode + open line below)
- Everything else → Sent as literal keystrokes via `tmux send-keys`

**Test assertions:**
- `_buffer <expected>` - Check commandline buffer contents
- `_cursor <position>` - Check cursor position (0-indexed)
- `_selection <expected>` - Check selected text
- `_mode <mode>` - Check fish_bind_mode (default/visual/insert)
- `_line <number>` - Check current line number

**`--broken` flag:**
- `_cursor --broken 4` means "we know this fails, expected value is 4"
- Test won't report failure if it matches the broken expectation
- Used to track known bugs without failing the test suite

### Critical Timing Issues

1. **Fish initialization takes time**: Must wait 1.5s before sending F12
2. **Queued vs Immediate commands**:
   - `commandline -f <action>` = queued (executes after current command)
   - `commandline -C <position>` = immediate cursor positioning
   - Mixing these can cause race conditions
3. **Key sequence timing**: When tests send multiple keys rapidly (e.g., `gg ww`), there can be timing issues where the second command arrives before the first completes

## What We Accomplished (Oct 2025 Session)

### Fixed Test Suite for Fish 4.0 + macOS

**Commit: `3c40f91` - "Fix test suite for Fish 4.0 and macOS compatibility"**

#### Problem 1: Deprecated `-k` Flag (Fish 4.0 Breaking Change)
Fish 4.0 removed the `-k` flag for key bindings. Had to convert to escape sequences:

**Before (Fish 3.x):**
```fish
bind -k f12 validate
bind -k f9 check
bind -k f11 ''
```

**After (Fish 4.0+):**
```fish
bind \e\[24~ validate   # F12
bind \e\[20~ check      # F9
bind \e\[23~ ''         # F11
```

**Files changed:** `tests/_init.fish`

#### Problem 2: F12 Sent Too Early
Originally `_done.fish` was sourced in the `-C` initialization command, sending F12 before fish was ready.

**Fix:**
- Don't source `_done.fish` in `-C` command
- Wait 1.5s after tmux session starts
- Then send F12 from outside: `tmux send-keys -t "$session" F12`

**Files changed:** `tests/_run.fish`

#### Problem 3: False Positives
Tests were passing even when they didn't actually run because the script only checked for *absence* of failure files.

**Fix:**
Added explicit check that result file MUST exist:
```fish
test -f "$temp_dir/result/result" || begin
    echo "ERROR: Test timed out - result file not created" >&2
    exit 1
end
```

**Files changed:** `tests/_run.fish`

#### Problem 4: Platform-Specific Dependencies
Tests required `inotifywait` (Linux) or `fswatch` (macOS) for file watching.

**Fix:**
Simple polling works everywhere:
```fish
sleep 0.5  # Let fish initialize
tmux send-keys -t "$session" F12
# Poll for result file
for i in (seq 1 10)
    test -f "$temp_dir/result/result" && break
    sleep 0.1
end
```

**Files changed:** `tests/_run.fish`, `README.md`

#### Problem 5: No Test Progress Output
Tests ran silently, hard to debug.

**Fix:**
Uncommented success/failure messages in `run-tests`:
```fish
echo "Test $test_file has succeeded." >&2
echo "Test $test_file has failed:" >&2
```

**Files changed:** `run-tests`

### Additional Fix: Case-Collision Cleanup

**Commit: `4a0bf3b` - "Remove duplicate test files with incorrect case"**

Accidentally created lowercase duplicates during testing:
- `p-left.fish` vs `P-left.fish`
- `p-right.fish` vs `P-right.fish`
- `t-enter.fish` vs `T-enter.fish`
- `a.fish` vs `A.fish`
- `i.fish` vs `I.fish`

On case-insensitive filesystems (macOS), Git couldn't check out both versions, causing collisions. Removed the incorrect lowercase duplicates.

## Current Test Results (Baseline)

**Overall:** 49 tests finished. **15 failed** and **2 broken**.

### Categories of Failures

#### 1. Buffer Operations (9 failures)
**Pattern:** Yank (copy) and paste operations don't work correctly

**Failing tests:**
- `tests/buffer/y-left.fish` - Yank operation
- `tests/buffer/p-empty.fish` - Paste after yank
- `tests/buffer/p-eof.fish` - Paste at end of file
- `tests/buffer/P-left.fish` - Paste before (capital P)
- `tests/buffer/P-right.fish` - Paste before (capital P)
- `tests/buffer/R-left.fish` - Replace operation
- `tests/buffer/R-right.fish` - Replace operation
- `tests/buffer/dp.fish` - Delete and paste
- `tests/buffer/dp-old.fish` - Delete and paste (old test)

**Common symptoms:**
- Selection is empty when it should contain text
- Buffer content missing pasted text
- Cursor at wrong position (often 0 or end)

**Example failure (`p-eof.fish`):**
```
Input: 123 Normal %c asdf Normal p
Expected: asdf123 (paste "123" after "asdf")
Actual: asdf (paste didn't work)
```

**Root cause speculation:**
- `%c` sequence (select all + copy) may not be working
- Fish's killring might not be getting populated
- The test uses `fish_helix_command yank` which calls `commandline -f kill-selection yank`
- May be a macOS-specific issue with clipboard integration
- Tests might be using wrong key sequence (should use `%y` instead of `%c`?)

**Key code locations:**
- `functions/fish_helix_command.fish:__fish_helix_yank` (line ~380)
- `functions/fish_helix_command.fish:__fish_helix_paste_before` (line ~390)
- `functions/fish_helix_command.fish:__fish_helix_paste_after` (line ~400)

#### 2. Word Motion Issues (2 failures)

**Failing tests:**
- `tests/word-motions/w-through-newline.fish`
- `tests/word-motions/w-until-newlines.fish`

**Pattern:** Multi-line word motions and `gg` interactions

**Example (`w-through-newline.fish`):**
```
Buffer:
hello
world
!

Input: gg ww
Expected: cursor at 10 (the 'd' in world), selection "world"
Actual: cursor at 12, selection "!"
```

**Observation from manual testing:**
- `ww` works fine when manually tested in the shell
- `gg` works on single-line buffers
- `gg` does NOT work on multi-line buffers when manually tested
- This suggests the issue is with `gg`, not `ww`

**Root cause:**
`goto_file_start` implementation uses `commandline -f beginning-of-buffer` which is a **queued action**. On multi-line buffers, this doesn't work correctly.

**Attempted fix (FAILED):**
Changed to `commandline -C 0` (immediate cursor positioning), but this broke other things and still didn't fix multi-line behavior.

**Key code location:**
- `functions/fish_helix_command.fish:__fish_helix_goto_line` (line ~277)

#### 3. Find/Till Operations (2 failures)

**Failing tests:**
- `tests/ft/alt-period-extends.fish`
- `tests/ft/count-f.fish`

**Pattern:** Selection not working with find operations

**Example (`alt-period-extends.fish`):**
```
Expected selection: asdasda
Actual selection: '' (empty)
```

**Root cause:** Likely related to the broader selection/visual mode issues

#### 4. Large Count Edge Case (1 failure)

**Failing test:**
- `tests/l-huge-count.fish`

**Symptoms:**
```
Input: 0123456789 Normal 9999l
Expected: cursor at 10, selection ''
Actual: cursor at 0, selection '0'
```

**Root cause:** Count handling when count > buffer length

#### 5. Goto Operations (1 failure)

**Failing test:**
- `tests/goto/gs-at-whitespace-line.fish`

**Symptoms:**
```
Expected: cursor at 1
Actual: cursor at 5
```

### Broken Tests (Expected Failures)

**2 broken tests** (marked with `--broken` in test files):
- `tests/ft/f-space-inclusive.fish` - Known issue with find-space operation
- `tests/ft/t-stop.fish` - Known issue with till operation

These are tracked as known bugs but don't cause test suite failure.

### Fixed Tests

**1 fixed test:**
- `tests/word-motions/w-at-newlines-and-eof.fish` - Was broken, now works

## Common Patterns & Root Causes

### Pattern 1: Visual Mode Selections Are Empty
**Affected:** 9+ tests

Many tests show `Selection content: '' (expected)` where a selection should exist.

**Possible causes:**
1. `begin-selection` not being called at the right time
2. Visual mode not properly tracking selection bounds
3. Race condition between mode switching and selection setup

**Key functions to investigate:**
- `__fish_helix_extend_by_mode` - Should call `begin-selection` in default mode
- `__fish_helix_extend_by_command` - Handles selection extension

### Pattern 2: Queued vs Immediate Commands
**Affected:** gg, goto operations

`commandline -f <action>` queues actions to run after the current command completes. This causes timing issues when:
1. Multiple commands sent rapidly (test infrastructure)
2. Mixing with immediate commands like `commandline -C`

**Actions that are queued:**
- `beginning-of-buffer`
- `end-of-buffer`
- `down-line`, `up-line`
- `begin-selection`, `end-selection`
- etc.

**Actions that are immediate:**
- `commandline -C <pos>` - Set cursor
- `commandline <text>` - Set buffer
- `set fish_bind_mode <mode>` - Change mode

### Pattern 3: Test Infrastructure vs Real Usage
**Key finding:** Some things work in manual testing but fail in tests

**Example:** `ww` works perfectly when manually tested, but fails in `w-through-newline.fish` test.

**Reasons:**
1. **Timing:** Tests send keys rapidly; manual testing has natural delays
2. **Initialization:** Tests might not wait long enough for all bindings to load
3. **tmux interaction:** Sending keys via `tmux send-keys` may behave differently than actual keypresses

**Recommendation:** Don't immediately trust test failures - verify with manual testing first.

## Key Implementation Details

### File Structure

```
fish-helix/
├── functions/
│   ├── fish_helix_command.fish       # Core command implementations
│   ├── fish_helix_key_bindings.fish  # Key binding definitions
│   ├── fish_bind_count.fish          # Count modifier handling (e.g., 3w)
│   └── fish_default_mode_prompt.fish # Mode indicator in prompt
├── tests/
│   ├── _init.fish                    # Test framework
│   ├── _run.fish                     # Test runner
│   ├── _done.fish                    # Test finalization (unused now)
│   ├── _example_test.fish            # Critical test - must pass
│   └── {category}/                   # Test files by category
│       ├── buffer/                   # Buffer operations
│       ├── word-motions/             # w, b, e motions
│       ├── goto/                     # gg, G, gh, gl operations
│       ├── ft/                       # f, F, t, T find operations
│       └── ia/                       # Insert mode operations
└── run-tests                         # Main test script
```

### How Modes Work

Fish has `$fish_bind_mode` variable:
- `default` = Normal mode (Helix terminology)
- `visual` = Visual mode
- `insert` = Insert mode

Mode switching:
```fish
# Insert → Normal
bind -M insert \e "set fish_bind_mode default; commandline -f begin-selection repaint-mode"

# Normal → Visual
bind -M default v repaint-mode

# Visual → Normal
bind -M visual \e repaint-mode
```

### How Selections Work

Fish has built-in selection support via `commandline -f begin-selection`:

1. Press `v` in Normal mode → enters Visual mode
2. Movement commands extend selection
3. `commandline -f begin-selection` marks current position as selection start
4. Moving cursor extends selection from that point
5. `commandline --current-selection` returns selected text

**Critical function:**
```fish
function __fish_helix_extend_by_mode
    if test $fish_bind_mode = default
        commandline -f begin-selection
    end
end
```

This gets called after most movement commands to start/extend selections in Normal mode.

### How Counts Work

Press digits before a command (e.g., `3w` = move forward 3 words):

1. `fish_bind_count.fish` tracks the count in `$fish_bind_count`
2. Each digit appends to the count: `3` then `2` = 32
3. Commands call `fish_bind_count -r` to read and reset
4. Returns 1 if count was 0 (default multiplier)

### How Find/Till Works

`f<char>` = find character, `t<char>` = till (before) character:

1. Bind lowercase letters to prompt for the character
2. Use `__fish_helix_find_char` function
3. Searches in buffer using sed/grep
4. Moves cursor to match

## Known Issues & Quirks

### Issue 1: gg Doesn't Work on Multi-line
**Symptoms:** In actual shell use, `gg` works on single-line commands but not multi-line.

**Expected:** Cursor should go to first character of first line.

**Actual:** Cursor stays at current position or goes to wrong place.

**Investigation needed:**
- Check if `commandline -f beginning-of-buffer` works correctly on multi-line
- May need to use `commandline -C 0` for immediate positioning
- But previous attempt to fix this broke other things

### Issue 2: Clipboard/Yank Might Be macOS-Specific
**Symptoms:** All yank/paste tests fail.

**Speculation:**
- Fish's `commandline -f yank` might not integrate with system clipboard on macOS
- Or the test infrastructure doesn't preserve the killring correctly
- Or tests are using the wrong key sequences

**Evidence:**
- Need to test manually: type text, select with `v`, press `y`, move elsewhere, press `p`
- Check if it works with actual keypresses vs test simulation

### Issue 3: Test Timing Is Fragile
**Symptoms:** Some tests might fail intermittently or only in test environment.

**Root cause:** 1.5 second wait might not be enough on slower machines.

**Mitigation:** Test suite has generous timeouts, but could be increased if needed.

### Issue 4: Example Test Blocks All Other Tests
**Symptoms:** If `_example_test.fish` fails, `run-tests` exits immediately.

**Reason:** It's meant to catch fundamental breakage early.

**Current status:** Example test currently fails on multi-line behavior, so full test suite doesn't run unless you skip it.

**Workaround:** Comment out the example test check in `run-tests` lines 7-12.

## Development Workflow

### Running Tests

```bash
# Run all tests
./run-tests

# Run specific test
fish ./tests/_run.fish ./tests/word-motions/w-through-newline.fish /tmp/test-output

# Check test output
cat /tmp/test-output/out
```

### Manual Testing

1. Install fish-helix functions:
```bash
cp functions/*.fish ~/.config/fish/functions/
```

2. Start new fish shell (or `exec fish`)

3. Test commands:
```fish
# Type some text
echo hello

# Press Escape (or F11 in tests) to enter Normal mode
# Try: gg, w, v, etc.
```

4. Check mode in prompt - should show indicator

### Debugging Tips

1. **Add debug output:**
```fish
echo "DEBUG: cursor at $(commandline -C)" >&2
```

2. **Check what's in the buffer:**
```fish
set -l buf (commandline)
echo "Buffer: $(string escape -- "$buf")" >&2
```

3. **Verify mode:**
```fish
echo "Mode: $fish_bind_mode" >&2
```

4. **Test timing:** Add `sleep` between commands to see if timing matters

5. **Check queued commands:** Use `commandline -C` to see immediate cursor position vs what queued commands will do

### Making Changes

1. Edit `functions/*.fish`
2. Reload fish: `exec fish`
3. Test manually first
4. Then run test suite
5. Commit with descriptive message

## Next Steps & Recommendations

### Immediate Priorities

#### 1. Fix `gg` on Multi-line Buffers (HIGH PRIORITY)
**Why:** This blocks several tests and is core functionality.

**Approach:**
1. Investigate why `commandline -f beginning-of-buffer` doesn't work on multi-line
2. Try alternative approaches:
   - Calculate position 0 explicitly
   - Use line navigation: `commandline -f beginning-of-buffer beginning-of-line`
   - Set cursor immediately: `commandline -C 0` but ensure selections work
3. Test manually with multi-line commands
4. If fixed, may resolve `w-through-newline` test too

**Files to modify:** `functions/fish_helix_command.fish:__fish_helix_goto_line`

#### 2. Investigate Yank/Paste Operations (HIGH PRIORITY)
**Why:** 9 tests failing, core functionality broken.

**Approach:**
1. Manual test: Does yank/paste work in real shell?
   ```fish
   # Type: hello world
   # Press: Escape, gg, vw (select "hello")
   # Press: y (yank)
   # Press: w (move to "world")
   # Press: p (paste)
   # Expected: "hellohello world"
   ```
2. If it works manually but tests fail → test infrastructure issue
3. If it doesn't work manually:
   - Check if `commandline -f yank` populates killring
   - Check if `fish_clipboard_copy` is needed
   - Look for macOS-specific issues
4. Check test sequences - is `%c` the right way to copy?
   - Maybe should be `%` then `y` (select all, then yank)
   - Not `%c` (select all, change - which deletes and enters insert)

**Files to investigate:**
- `functions/fish_helix_command.fish:__fish_helix_yank`
- `functions/fish_helix_command.fish:__fish_helix_paste_after`
- `functions/fish_helix_command.fish:__fish_helix_paste_before`
- Test files using `%c` - are they using the right sequence?

#### 3. Fix Selection Issues (MEDIUM PRIORITY)
**Why:** Many tests show empty selections.

**Approach:**
1. Verify `__fish_helix_extend_by_mode` is being called
2. Check if `begin-selection` is getting called at the right time
3. Manual test:
   ```fish
   # Type: hello world
   # Press: Escape, gg, vw
   # Check: Is "hello" highlighted/selected?
   # Press: d
   # Expected: "hello" deleted, leaving " world"
   ```
4. If selections work manually → test infrastructure timing issue
5. If selections don't work → core implementation bug

**Files to investigate:**
- `functions/fish_helix_command.fish:__fish_helix_extend_by_mode`
- `functions/fish_helix_key_bindings.fish` - visual mode bindings

### Medium-Term Goals

#### 4. Improve Test Reliability
**Actions:**
- Consider increasing wait times for slower machines
- Add optional debug mode to tests (show what keys are being sent)
- Better error messages when tests timeout
- Consider making example test non-blocking (warn but continue)

#### 5. Document Helix vs fish-helix Differences
**Actions:**
- Create a compatibility matrix
- Document intentional differences
- Mark `--broken` tests that won't be fixed

#### 6. Add More Manual Test Cases
**Actions:**
- Create a manual test checklist
- Document expected behavior for each operation
- Compare with actual Helix editor behavior

### Long-Term Ideas

#### 7. Improve Multi-line Editing
**Why:** This is where most issues appear.

**Actions:**
- Research how other shells handle multi-line modal editing
- Consider alternative approaches to line navigation
- May need to rethink queued vs immediate commands

#### 8. Consider Test Infrastructure Alternatives
**Why:** Current tmux-based approach has timing issues.

**Alternatives:**
- Unit tests for individual functions (not full integration)
- Expect-style testing with delays
- Record/replay approach for consistent timing

#### 9. macOS vs Linux Differences
**Actions:**
- Test on Linux to see if issues are macOS-specific
- Document platform-specific behavior
- Consider platform-specific workarounds if needed

## Quick Reference

### Running a Single Test
```bash
cd /tmp/fish-helix  # or your clone location
temp=$(mktemp -d)
fish ./tests/_run.fish ./tests/word-motions/w-through-newline.fish "$temp" 2>&1
cat "$temp/out"  # See results
```

### Test File Format Quick Reference
```fish
# Input simulation
_input hello Normal ww

# Assertions
_buffer "expected buffer content"
_cursor 10  # 0-indexed position
_selection "expected selected text"
_mode default  # or visual, insert
_line 2  # line number (1-indexed)

# Mark known failures
_cursor --broken 5  # We know it's wrong, should be 5
```

### Key Escape Sequences
```fish
F9:  \e[20~  # Check assertion
F11: \e[23~  # Normal mode (test only)
F12: \e[24~  # Finalize test (validate)
```

### Important Test Invariants
1. Tests MUST create `$temp_dir/result/result` file or they fail
2. Tests run in isolated tmux sessions with unique sockets
3. Fish runs in `--private` mode (no history)
4. 1.5 second initialization delay is CRITICAL
5. All test output goes to `$temp_dir/out`

## Troubleshooting

### "Test timed out - result file not created"
- Fish didn't initialize in time (increase sleep in `_run.fish`)
- F12 key binding not working (check escape sequences)
- Test crashed before calling validate

### Tests pass but behavior wrong in shell
- Test infrastructure has different timing than real use
- Test might be checking wrong things
- Verify manually before trusting test

### "collision" warning when cloning
- Case-sensitivity issue (macOS vs Linux)
- Check for duplicate files with different cases
- Use `git ls-tree -r HEAD --name-only | sort -f | uniq -d -i`

### All tests suddenly failing
- Check if Fish version changed
- Verify functions installed: `ls ~/.config/fish/functions/fish_helix*`
- Check for breaking changes in fish-helix bindings

## Additional Resources

- **Fish Shell Documentation:** https://fishshell.com/docs/current/
- **Helix Editor:** https://helix-editor.com/
- **Original fish-helix:** https://github.com/sshilovsky/fish-helix
- **Your fork:** https://github.com/kalin/fish-helix

## Session Notes

**Last updated:** 2025-10-30

**Current state:**
- Test suite works reliably on macOS + Fish 4.0
- 49 tests run, 15 fail, 2 broken (consistent baseline)
- Core functionality works but has rough edges
- Multi-line editing needs work

**What to tackle first:** Fix `gg` on multi-line buffers, then investigate yank/paste operations.

Good luck! 🚀