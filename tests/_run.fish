# TODO error handling
set -l test_file "$argv[1]"
set -l temp_dir "$argv[2]"
set -l root "$(dirname "$(status filename)")"

mkdir -p "$temp_dir/result"
# TODO path to compiled fish executable
tmux -f /dev/null -S "$temp_dir/tmux" new-session -dPF "#{session_name}" \
    fish --private -i -C "\
        source $root/../functions/fish_bind_count.fish; \
        source $root/../functions/fish_helix_command.fish; \
        source $root/../functions/fish_default_mode_prompt.fish; \
        source $root/../functions/fish_helix_key_bindings.fish; \
        source $root/_init.fish $temp_dir; \
        source $test_file; \
        source $root/_done.fish; \
    " | read -l tmux_session

# Wait for test result file - cross-platform
if command -q inotifywait
    # Linux - inotifywait can monitor before file exists
    inotifywait -t 1 -e close_write "$temp_dir/result/result" >/dev/null 2>&1
else
    # macOS/BSD - poll for file existence (simpler and more reliable)
    for i in (seq 1 10)
        test -f "$temp_dir/result/result" && break
        sleep 0.1
    end
end
# Kill the tmux session using the same socket
tmux -S "$temp_dir/tmux" kill-session -t "$tmux_session" 2>/dev/null
# Also kill any orphaned fish processes from this test
pkill -P (pgrep -f "tmux.*$temp_dir") 2>/dev/null

test ! -e "$temp_dir/fixed" -a ! -e "$temp_dir/failure"
