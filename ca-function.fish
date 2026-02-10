# Claude Agent Teams - tmux swarm mode
# ca             → yeni claude session (tmux icinde)
# ca <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# ca #N          → listeden numara ile session ac (ca #17)
# ca -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# ca -p <isim>   → session'in son mesajlarini goster (peek)
# ca -p #N       → numara ile peek
#
# Helper: ~/.local/bin/claude-sessions (search|list|peek)
# Bu fonksiyonu ~/.config/fish/config.fish dosyasina ekle.
function ca
    # --- Flags ---
    if test (count $argv) -ge 1
        switch $argv[1]
            case -l --list l
                claude-sessions list
                return
            case -p --peek p
                if test (count $argv) -ge 2
                    claude-sessions peek $argv[2]
                else
                    echo "Kullanim: ca -p <isim>"
                end
                return
        end
    end

    set -l work_dir (pwd)
    set -l session_id ""
    set -l tmux_name "ca-"(date +%H%M%S)

    # --- Argumanli: renamed veya unnamed session ara ---
    if test (count $argv) -ge 1
        set -l lookup (claude-sessions search $argv[1])
        if test $status -eq 0 -a -n "$lookup"
            set -l parts (string split '|' $lookup)
            set session_id $parts[1]
            set work_dir $parts[2]
            set tmux_name $argv[1]
        else
            return 1
        end
    end

    # --- Claude komutu ---
    set -l claude_args --dangerously-skip-permissions
    if test -n "$session_id"
        set -a claude_args --resume $session_id
    end

    set -l tmux_cmd "cd $work_dir && CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args; exec fish"

    # --- tmux ---
    if test -n "$TMUX"
        tmux new-window -n $tmux_name -c "$work_dir" \
            -e CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
            "$tmux_cmd"
    else if tmux has-session -t "$tmux_name" 2>/dev/null
        tmux attach-session -t "$tmux_name"
    else
        tmux new-session -s $tmux_name -c "$work_dir" \
            -e CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
            "$tmux_cmd"
    end
end
