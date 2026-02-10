# Claude Code - direct mode (tmux'suz, dogrudan terminalde)
# cc             → yeni claude session
# cc <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# cc #N          → listeden numara ile session ac (cc #17)
# cc -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# cc -p <isim>   → session'in son mesajlarini goster (peek)
# cc -p #N       → numara ile peek
#
# Helper: ~/.local/bin/claude-sessions (search|list|peek)
# Bu fonksiyonu ~/.bashrc veya ~/.zshrc dosyasina ekle.
cc() {
    case "$1" in
        -l|--list|l)  claude-sessions list; return ;;
        -p|--peek|p)  claude-sessions peek "$2"; return ;;
    esac

    local work_dir session_id
    work_dir="$(pwd)"
    session_id=""

    if [ -n "$1" ]; then
        local lookup
        lookup="$(claude-sessions search "$1")"
        if [ $? -eq 0 ] && [ -n "$lookup" ]; then
            session_id="${lookup%%|*}"
            work_dir="${lookup#*|}"
        else
            return 1
        fi
    fi

    local claude_args="--dangerously-skip-permissions"
    [ -n "$session_id" ] && claude_args="$claude_args --resume $session_id"

    # Dogrudan calistir (tmux yok)
    cd "$work_dir"
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args
}
