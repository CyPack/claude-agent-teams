# Claude Code - direct mode (tmux'suz, dogrudan terminalde)
# cc             → yeni claude session
# cc <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# cc #N          → listeden numara ile session ac (cc #17)
# cc -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# cc -p <isim>   → session'in son mesajlarini goster (peek)
# cc -p #N       → numara ile peek
#
# Helper: ~/.local/bin/claude-sessions (search|list|peek)
# Bu fonksiyonu ~/.config/fish/config.fish dosyasina ekle.
function cc
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
                    echo "Kullanim: cc -p <isim>"
                end
                return
        end
    end

    set -l work_dir (pwd)
    set -l session_id ""

    # --- Argumanli: renamed veya unnamed session ara ---
    if test (count $argv) -ge 1
        set -l lookup (claude-sessions search $argv[1])
        if test $status -eq 0 -a -n "$lookup"
            set -l parts (string split '|' $lookup)
            set session_id $parts[1]
            set work_dir $parts[2]
        else
            return 1
        end
    end

    # --- Claude komutu ---
    set -l claude_args --dangerously-skip-permissions
    if test -n "$session_id"
        set -a claude_args --resume $session_id
    end

    # --- Dogrudan calistir (tmux yok) ---
    cd $work_dir
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args
end
