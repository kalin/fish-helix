# TODO error handling
set -l test_file "$argv[1]"
set -l temp_dir "$argv[2]"
set -l root "$(dirname "$(status filename)")"

mkdir -p "$temp_dir/result"
# TODO path to compiled fish executable
# Start fish session with test setup, but DON'T send the finalize key yet
tmux -f /dev/null -S "$temp_dir/tmux" new-session -dPF "#{session_name}" \
    fish --private -i -C "\
        source $root/../functions/fish_bind_count.fish; \
        source $root/../functions/fish_helix_command.fish; \
        source $root/../functions/fish_default_mode_prompt.fish; \
        source $root/../functions/fish_helix_key_bindings.fish; \
        source $root/_init.fish $temp_dir; \
        source $test_file; \
    " | read -l tmux_session

# Give fish time to fully initialize and become ready to receive keys
# This needs to be generous enough for slower machines
sleep 1.5

# NOW send the F12 key to finalize the test (same as _done.fish did)
tmux -f /dev/null -S "$temp_dir/tmux" send-keys -t "$tmux_session" F12

# Wait for test result file - simple polling works on all platforms
# Poll for up to 1 second (10 iterations × 0.1s)
# Tests complete almost instantly once F12 is received
for i in (seq 1 10)
    test -f "$temp_dir/result/result" && break
    sleep 0.1
end
# Kill the tmux session using the same socket
tmux -S "$temp_dir/tmux" kill-session -t "$tmux_session" 2>/dev/null

# Test MUST have completed (result file exists) to be valid
# Otherwise we have a timeout/false-positive
test -f "$temp_dir/result/result" || begin
    echo "ERROR: Test timed out - result file not created" >&2
    exit 1
end

# Now check if test passed or had expected failures
test ! -e "$temp_dir/fixed" -a ! -e "$temp_dir/failure"
