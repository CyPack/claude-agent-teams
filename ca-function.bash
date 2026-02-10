# Claude Agent Teams - tmux swarm mode
# ca             → yeni claude session
# ca <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# ca #N          → listeden numara ile session ac (ca #17)
# ca -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# ca -p <isim>   → session'in son mesajlarini goster (peek)
# ca -p #N       → numara ile peek
#
# Helper: ~/.local/bin/claude-sessions (search|list|peek)
# Bu fonksiyonu ~/.bashrc veya ~/.zshrc dosyasina ekle.
ca() {
    case "$1" in
        -l|--list|l)  claude-sessions list; return ;;
        -p|--peek|p)  claude-sessions peek "$2"; return ;;
    esac

    local work_dir session_id tmux_name
    work_dir="$(pwd)"
    session_id=""
    tmux_name="ca-$(date +%H%M%S)"

    if [ -n "$1" ]; then
        local lookup
        lookup="$(claude-sessions search "$1")"
        if [ $? -eq 0 ] && [ -n "$lookup" ]; then
            session_id="${lookup%%|*}"
            work_dir="${lookup#*|}"
            tmux_name="$1"
        else
            return 1
        fi
    fi

    local claude_args="--dangerously-skip-permissions"
    [ -n "$session_id" ] && claude_args="$claude_args --resume $session_id"

    local tmux_cmd="cd $work_dir && CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args; exec $SHELL"

    if [ -n "$TMUX" ]; then
        tmux new-window -n "$tmux_name" -c "$work_dir" \
            -e CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
            "$tmux_cmd"
    elif tmux has-session -t "$tmux_name" 2>/dev/null; then
        tmux attach-session -t "$tmux_name"
    else
        tmux new-session -s "$tmux_name" -c "$work_dir" \
            -e CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
            "$tmux_cmd"
    fi
}
