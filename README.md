# Claude Code Agent Teams - Complete Setup Guide

> Multi-agent swarm orchestration with tmux. Her agent kendi pane'inde paralel calisir.
> Bu dosya agent-friendly'dir: bir AI agent'a verildiginde adim adim kurulum yapabilir.

![cc l - session list](https://raw.githubusercontent.com/CyPack/claude-agent-teams/main/screenshot.png)

---

## Gereksinimler

| Gereksinim | Minimum | Kontrol | Kurulum |
|------------|---------|---------|---------|
| Claude Code | >= 2.1.32 | `claude --version` | `npm install -g @anthropic-ai/claude-code` |
| tmux | >= 3.2 | `tmux -V` | Asagida |
| Python 3 | >= 3.8 | `python3 --version` | `claude-sessions` helper icin gerekli |
| Model | Opus 4.6 onerilen | - | Sonnet da calisir |
| Terminal | Ghostty, Alacritty, Kitty, iTerm2 | - | VS Code terminal **calismaz** |

### tmux Kurulum

```bash
# Fedora/RHEL
sudo dnf install tmux

# Ubuntu/Debian
sudo apt install tmux

# macOS
brew install tmux

# Arch
sudo pacman -S tmux
```

---

## Mimari: `ca` Komutu Nasil Calisiyor?

### Veri Kaynagi

Claude Code her konusmayi JSONL formatinda saklar:

```
~/.claude/projects/<proje-dizini>/<UUID>.jsonl
```

Her JSONL dosyasi satir satir JSON icerir:
- `"type":"user"` — kullanici mesajlari (ilk ve son mesaj izlenir)
- `"type":"assistant"` — Claude yanitleri (son yanit izlenir)
- `"type":"custom-title"` — `/rename` ile verilen isim (ANAHTAR ALAN)
- `"type":"summary"` — otomatik olusturulan baslik
- `"cwd"` — session'in calistigi dizin

> **KRITIK:** `/rename` komutu `"type":"custom-title"` + `"customTitle"` alani olusturur.
> `"type":"summary"` FARKLI bir alan — otomatik baslik, `/rename` degil.

### Arama Akisi

```
ca nvidia                             (veya ca #17)
  |
  +-- claude-sessions search nvidia     (Python helper)
  |     |
  |     +-- ~/.claude/projects/*/       <-- TUM proje dizinlerini tarar
  |     |     +-- her JSONL satir satir okunur
  |     |
  |     +-- #N → listeden numara ile bul
  |     +-- text → arama onceligi:
  |     |     renamed exact > renamed partial > renamed context > renamed ai
  |     |     unnamed exact > unnamed partial > unnamed context > unnamed ai
  |     +-- stdout: UUID|CWD
  |
  +-- tmux new-session/attach
        +-- cd <CWD> && claude --resume <UUID>
```

### Dosya Yapisi

```
~/.local/bin/claude-sessions          # Python helper (search|list|peek)
~/.config/claude-sessions.json        # Config (siralama, limit)
~/.config/ghostty/config              # Ghostty terminal ayarlari
~/.config/fish/config.fish            # Fish shell ca/cc fonksiyonlari
~/.tmux.conf                          # tmux ayarlari (mouse, renkler)
~/.claude/settings.json               # Claude Code ayarlari (env)
~/.claude/projects/*/                 # Session JSONL dosyalari
```

---

## Adim 1: tmux Config

```bash
cat > ~/.tmux.conf << 'EOF'
# =============================================================================
# TMUX CONFIG - Agent Teams Optimized
# =============================================================================

# Mouse - tam destek (pane secim, resize, scroll)
set -g mouse on

# Terminal - modern terminal uyumu
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-ghostty:RGB"
set -ag terminal-overrides ",alacritty:RGB"
set -ag terminal-overrides ",xterm-kitty:RGB"
set -ag terminal-overrides ",xterm-256color:RGB"

# Pane border - aktif pane belirgin
set -g pane-border-style "fg=#45475a"
set -g pane-active-border-style "fg=#89b4fa,bold"
set -g pane-border-lines heavy

# Pane resize - Ctrl+B sonra H/J/K/L ile 5px boyutlandir
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Status bar
set -g status-style "bg=#1e1e2e,fg=#cdd6f4"
set -g status-left "#[fg=#89b4fa,bold] #S "
set -g status-right "#[fg=#a6e3a1] %H:%M "
set -g window-status-current-style "fg=#f5c2e7,bold"

# Pane numaralari (Ctrl+B q ile goster)
set -g display-panes-time 3000
set -g display-panes-colour "#45475a"
set -g display-panes-active-colour "#89b4fa"

# Performance
set -g focus-events on
set -sg escape-time 0
set -g history-limit 50000
EOF
```

tmux icindeysen reload et:

```bash
tmux source-file ~/.tmux.conf
```

---

## Adim 1b: Ghostty Config (Ghostty Kullanicilariysa)

Split view'da mouse hangi pane'in uzerindeyse focus otomatik oraya gecer — ekstra tiklamaya gerek kalmaz.

Repo'daki [`ghostty.conf`](ghostty.conf) dosyasindaki ayarlari `~/.config/ghostty/config` dosyasina ekle:

```bash
# Ghostty config dizini yoksa olustur
mkdir -p ~/.config/ghostty

# Ayari ekle (zaten varsa atlayabilirsin)
cat >> ~/.config/ghostty/config << 'EOF'

# Mouse - split view'da focus follows mouse
focus-follows-mouse = true
EOF
```

> **Not:** Ghostty'yi yeniden baslat veya config reload et (`Cmd+,`).
> Bu ayar Ghostty split'leri ve tmux pane'leri icin de ise yarar.

---

## Adim 2: claude-sessions Helper Script

Bu Python script tum arama, listeleme ve peek islemlerini yapar.
`ca`/`cc` fonksiyonlari bunu cagirir — inline Python yok, temiz mimari.

> **Not:** Guncel kod her zaman repo'daki [`claude-sessions`](claude-sessions) dosyasindadir.
> Asagidaki inline kod referans icin verilmistir.

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/claude-sessions << 'PYEOF'
#!/usr/bin/env python3
"""Claude Code session lookup - session'lari bulur, listeler, gosterir.

Usage:
    claude-sessions search <name>    # UUID|CWD doner (ca fonksiyonu icin)
    claude-sessions list             # tum session'lari listeler
    claude-sessions peek <name>      # session'in son mesajlarini gosterir
"""

import json, os, glob, sys, time, shutil

PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
CONFIG_PATH = os.path.expanduser("~/.config/claude-sessions.json")

# --- Config ---
# ~/.config/claude-sessions.json:
# {
#   "sort": "bottom-up",   ← "bottom-up" (yeni altta) veya "top-down" (yeni ustte)
#   "limit": 100           ← listede gosterilecek max session sayisi
# }
_DEFAULT_CONFIG = {"sort": "bottom-up", "limit": 100}


def _load_config():
    """Config dosyasini oku. Yoksa default deger kullan."""
    cfg = dict(_DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH) as f:
            user = json.load(f)
        if user.get("sort") in ("bottom-up", "top-down"):
            cfg["sort"] = user["sort"]
        if isinstance(user.get("limit"), int) and user["limit"] > 0:
            cfg["limit"] = user["limit"]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass
    return cfg

# ANSI colors
C_RESET = "\033[0m"
C_CYAN = "\033[1;36m"
C_YELLOW = "\033[0;33m"
C_WHITE = "\033[0;37m"
C_RED = "\033[1;31m"
C_DIM = "\033[2m"
C_GREEN = "\033[0;32m"
C_BLUE = "\033[0;34m"
C_MAGENTA = "\033[0;35m"


_NOISE_PREFIXES = (
    "This session is being continued",
    "[Request interrupted",
)


def _get_msg_text(d):
    """Parsed JSONL entry'sinden (user veya assistant) text'i cek."""
    msg = d.get("message", {})
    if not isinstance(msg, dict):
        return ""
    content = msg.get("content", "")
    if isinstance(content, list):
        for c in content:
            if isinstance(c, dict) and c.get("type") == "text":
                text = c.get("text", "").strip()
                if text:
                    return text
    elif isinstance(content, str) and content.strip():
        return content.strip()
    return ""


def _is_noise(text):
    """Teknik/meta mesajlari filtrele."""
    return not text or text.startswith("<") or any(text.startswith(p) for p in _NOISE_PREFIXES)


def _project_name(cwd):
    """CWD'den proje ismini cek."""
    home = os.path.expanduser("~")
    if not cwd or cwd.rstrip("/") == home.rstrip("/"):
        return "~"
    return os.path.basename(cwd.rstrip("/")) or "~"


def _term_width():
    """Terminal genisligini al."""
    return shutil.get_terminal_size().columns


def scan_sessions(renamed_only=True):
    """JSONL dosyalarini tarayip session'lari doner."""
    results = []
    for projdir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        for f in glob.glob(os.path.join(projdir, "*.jsonl")):
            sid = os.path.basename(f).replace(".jsonl", "")
            try:
                cwd = ""
                custom_title = ""
                summary_title = ""
                first_user_text = ""
                last_user_text = ""
                last_asst_text = ""

                for line in open(f):
                    try:
                        d = json.loads(line)
                    except:
                        continue
                    if not cwd and d.get("cwd"):
                        cwd = d["cwd"]
                    if d.get("type") == "custom-title":
                        custom_title = d.get("customTitle", "")
                    if d.get("type") == "summary":
                        summary_title = d.get("summary", "")
                    if d.get("type") == "user":
                        text = _get_msg_text(d)
                        if not _is_noise(text):
                            if not first_user_text:
                                first_user_text = text
                            last_user_text = text
                    if d.get("type") == "assistant":
                        text = _get_msg_text(d)
                        if text and not text.startswith("<"):
                            last_asst_text = text

                is_renamed = bool(custom_title)
                if renamed_only and not is_renamed:
                    continue

                # Title: custom > summary > ilk user mesaji
                display_title = (custom_title or summary_title
                                 or first_user_text[:60].replace("\n", " "))
                if not display_title:
                    continue

                project = _project_name(cwd) if cwd else "~"

                # Context: son user mesaji (arama icin)
                context = last_user_text.replace("\n", " ")[:120] if last_user_text else ""
                # Last AI response (session nerede kaldi)
                last_ai = last_asst_text.replace("\n", " ")[:200] if last_asst_text else ""

                results.append({
                    "title": display_title,
                    "sid": sid,
                    "cwd": cwd or os.path.expanduser("~"),
                    "mtime": os.path.getmtime(f),
                    "size": os.path.getsize(f) / 1024,
                    "path": f,
                    "projdir": projdir,
                    "renamed": is_renamed,
                    "project": project,
                    "context": context,
                    "last_ai": last_ai,
                })
            except:
                pass
    results.sort(key=lambda x: -x["mtime"])
    return results


def find_match(name):
    """Isimle eslesme bul. #N ile numara, yoksa title + context + last_ai arar."""
    all_sessions = scan_sessions(renamed_only=False)
    scanned_dirs = set()
    for projdir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        scanned_dirs.add(projdir)

    # #N veya saf sayi → liste numarasiyla bul
    num_str = name.lstrip("#")
    if num_str.isdigit():
        renamed = [s for s in all_sessions if s["renamed"]]
        unnamed = [s for s in all_sessions if not s["renamed"]]
        cfg = _load_config()
        show_count = max(0, cfg["limit"] - len(renamed))
        ordered = renamed + unnamed[:show_count]
        n = int(num_str)
        if 1 <= n <= len(ordered):
            return ordered[n - 1], all_sessions, scanned_dirs
        return None, all_sessions, scanned_dirs

    search = name.lower()
    renamed = [s for s in all_sessions if s["renamed"]]
    unnamed = [s for s in all_sessions if not s["renamed"]]

    # Oncelik: renamed > unnamed
    # Her pool icinde: exact title > partial title > context (user) > last_ai (assistant)
    for pool in [renamed, unnamed]:
        exact = [s for s in pool if s["title"].lower() == search]
        if exact:
            return exact[0], all_sessions, scanned_dirs
        partial = [s for s in pool if search in s["title"].lower()]
        if partial:
            return partial[0], all_sessions, scanned_dirs
        ctx_match = [s for s in pool if search in s.get("context", "").lower()]
        if ctx_match:
            return ctx_match[0], all_sessions, scanned_dirs
        ai_match = [s for s in pool if search in s.get("last_ai", "").lower()]
        if ai_match:
            return ai_match[0], all_sessions, scanned_dirs

    return None, all_sessions, scanned_dirs


def eprint(*args, **kwargs):
    """stderr'e yaz."""
    print(*args, file=sys.stderr, **kwargs)


def print_not_found(name, sessions, scanned_dirs):
    """Agent-friendly 'bulunamadi' mesaji (stderr'e)."""
    eprint(f"\n  {C_RED}Session '{name}' bulunamadi.{C_RESET}\n")
    eprint(f"  {C_DIM}Aranan dizin:{C_RESET}  {PROJECTS_DIR}/")
    eprint(f"  {C_DIM}Taranan proje:{C_RESET}  {len(scanned_dirs)} dizin")
    jsonl_count = sum(1 for d in scanned_dirs for _ in glob.glob(os.path.join(d, "*.jsonl")))
    eprint(f"  {C_DIM}Taranan JSONL:{C_RESET}  {jsonl_count} dosya")
    eprint(f"  {C_DIM}Aranan alan:{C_RESET}   title + context icinde \"{name}\"")
    eprint()
    renamed = [s for s in sessions if s.get("renamed")]
    if renamed:
        eprint(f"  {C_GREEN}Renamed session'lar:{C_RESET}")
        for s in renamed[:10]:
            ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(s["mtime"]))
            eprint(f"    {C_CYAN}{s['title']:20s}{C_RESET}  {ts}")
    recent = [s for s in sessions if not s.get("renamed")][:5]
    if recent:
        eprint(f"\n  {C_DIM}Son unnamed session'lar:{C_RESET}")
        for s in recent:
            ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(s["mtime"]))
            title = s["title"][:40]
            eprint(f"    {C_WHITE}{title:42s}{C_RESET}  {ts}")
    eprint(f"\n  {C_DIM}Ipucu: ca -l ile tum session'lari gor.{C_RESET}")
    eprint()


def print_cwd_warning(match):
    """CWD dizini yoksa agent-friendly uyari (stderr'e)."""
    cwd = match["cwd"]
    if os.path.isdir(cwd):
        return False
    eprint(f"\n  {C_YELLOW}CWD dizini bulunamadi!{C_RESET}\n")
    eprint(f"  {C_DIM}Session:{C_RESET}      {C_CYAN}{match['title']}{C_RESET}")
    eprint(f"  {C_DIM}UUID:{C_RESET}         {match['sid']}")
    eprint(f"  {C_DIM}JSONL:{C_RESET}        {match['path']}")
    eprint(f"  {C_DIM}Kayitli CWD:{C_RESET}  {C_RED}{cwd}{C_RESET}  <- bu dizin artik yok")
    eprint()
    parts = cwd.rstrip("/").split("/")
    for i in range(len(parts), 0, -1):
        parent = "/".join(parts[:i]) or "/"
        if os.path.isdir(parent):
            eprint(f"  {C_DIM}En yakin mevcut parent:{C_RESET}  {C_GREEN}{parent}{C_RESET}")
            break
    eprint(f"\n  {C_DIM}Ipucu: Session ~ (home) dizininden resume edilecek.{C_RESET}")
    eprint()
    return True


def cmd_search(name):
    """Session ara, UUID|CWD dondur. #N ile numara ile de acilabilir."""
    match, sessions, scanned_dirs = find_match(name)
    if not match:
        print_not_found(name, sessions, scanned_dirs)
        sys.exit(1)

    cwd = match["cwd"]
    if not os.path.isdir(cwd):
        print_cwd_warning(match)
        cwd = os.path.expanduser("~")

    print(f'{match["sid"]}|{cwd}')


def cmd_list():
    """Tum session'lari listele — renamed ve unnamed."""
    cfg = _load_config()
    sort_order = cfg["sort"]      # "bottom-up" veya "top-down"
    limit = cfg["limit"]          # max gosterilecek session

    all_sessions = scan_sessions(renamed_only=False)
    if not all_sessions:
        print(f"\n  {C_YELLOW}Hic session bulunamadi.{C_RESET}\n")
        return

    renamed = [s for s in all_sessions if s["renamed"]]
    unnamed = [s for s in all_sessions if not s["renamed"]]
    tw = _term_width()

    def fmt_size(kb):
        return f"{kb:.0f}K" if kb < 1024 else f"{kb/1024:.1f}M"

    def proj_tag(s):
        p = s["project"]
        if p == "~":
            return "", 0
        tag_text = p[:16]
        return f"{C_BLUE}[{tag_text}]{C_RESET} ", len(tag_text) + 3

    show_count = max(0, limit - len(renamed))

    # Pre-index: #1 = en yeni renamed
    renamed_items = [(i + 1, s) for i, s in enumerate(renamed)]
    unnamed_items = [(len(renamed) + i + 1, s) for i, s in enumerate(unnamed[:show_count])]

    def print_renamed():
        if not renamed:
            return
        print(f"\n  {C_GREEN}Renamed Sessions ({len(renamed)}){C_RESET}  {C_DIM}— ca <isim> veya ca #N ile resume et{C_RESET}\n")
        items = reversed(renamed_items) if sort_order == "bottom-up" else renamed_items
        for idx, s in items:
            ts = time.strftime("%m-%d %H:%M", time.localtime(s["mtime"]))
            size = fmt_size(s["size"])
            tag, tag_len = proj_tag(s)
            desc_width = max(20, tw - 46 - tag_len)
            ai = s["last_ai"][:desc_width] if s["last_ai"] else s["context"][:desc_width]
            print(f"  {C_DIM}{idx:>3d}{C_RESET} {ts}  {size:>5s}  {C_CYAN}{s['title']:18s}{C_RESET}  {tag}{C_DIM}{ai}{C_RESET}")

    def print_unnamed():
        if not unnamed:
            return
        remaining = len(unnamed) - show_count
        if sort_order == "bottom-up" and remaining > 0:
            print(f"\n  {C_DIM}... ve {remaining} eski session daha{C_RESET}")
        print(f"\n  {C_DIM}Other Sessions ({len(unnamed)}){C_RESET}  {C_DIM}— ca #N ile ac | /rename ile isimlendir{C_RESET}\n")
        items = reversed(unnamed_items) if sort_order == "bottom-up" else unnamed_items
        for idx, s in items:
            ts = time.strftime("%m-%d %H:%M", time.localtime(s["mtime"]))
            size = fmt_size(s["size"])
            tag, tag_len = proj_tag(s)
            desc_width = max(20, tw - 26 - tag_len)
            ai = s["last_ai"][:desc_width] if s["last_ai"] else (s["context"] or s["title"])[:desc_width]
            print(f"  {C_DIM}{idx:>3d}{C_RESET} {ts}  {size:>5s}  {tag}{C_WHITE}{ai}{C_RESET}")
        if sort_order == "top-down" and remaining > 0:
            print(f"  {C_DIM}... ve {remaining} session daha{C_RESET}")

    # bottom-up: unnamed (eski->yeni) sonra renamed (eski->yeni), en yeni en altta
    # top-down:  renamed (yeni->eski) sonra unnamed (yeni->eski), en yeni en ustte
    if sort_order == "bottom-up":
        print_unnamed()
        print_renamed()
    else:
        print_renamed()
        print_unnamed()

    print(f"\n  {C_DIM}Toplam: {len(all_sessions)} session ({len(renamed)} renamed, {len(unnamed)} unnamed){C_RESET}")
    print()


def cmd_peek(name):
    """Session'in son kullanici/asistan mesajlarini goster."""
    match, sessions, scanned_dirs = find_match(name)
    if not match:
        print_not_found(name, sessions, scanned_dirs)
        sys.exit(1)

    messages = []
    for line in open(match["path"]):
        try:
            d = json.loads(line)
        except:
            continue
        t = d.get("type", "")
        if t not in ("user", "assistant"):
            continue
        text = _get_msg_text(d)
        if text and not text.startswith("<"):
            role = "USER" if t == "user" else "ASST"
            messages.append((role, text))

    ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(match["mtime"]))
    tw = _term_width()
    cwd_ok = os.path.isdir(match["cwd"])
    cwd_line = match["cwd"] if cwd_ok else f'{C_RED}{match["cwd"]}  (dizin yok!){C_RESET}'
    print(f'\n  {C_CYAN}{match["title"]}{C_RESET}  ({ts})  {C_BLUE}{match.get("project", "")}{C_RESET}')
    print(f'  {cwd_line}')
    print(f'  {"─" * min(70, tw - 4)}')

    preview_width = max(40, tw - 10)
    for role, text in messages[-6:]:
        preview = text[:preview_width].replace("\n", " ")
        color = C_YELLOW if role == "USER" else C_WHITE
        print(f"  {color}{role:4s}{C_RESET}  {preview}")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "search" and len(sys.argv) >= 3:
        cmd_search(sys.argv[2])
    elif cmd == "list":
        cmd_list()
    elif cmd == "peek" and len(sys.argv) >= 3:
        cmd_peek(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
PYEOF
chmod +x ~/.local/bin/claude-sessions
```

---

## Adim 3: Fish Shell `ca` Fonksiyonu

`~/.config/fish/config.fish` dosyasina ekle:

```fish
# Claude Agent Teams - tmux swarm mode
# ca             → yeni claude session (tmux icinde)
# ca <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# ca #N          → listeden numara ile session ac (ca #17)
# ca -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# ca -p <isim>   → session'in son mesajlarini goster (peek)
# ca -p #N       → numara ile peek
#
# Helper: ~/.local/bin/claude-sessions (search|list|peek)
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
```

### Bash / Zsh Versiyonu

`~/.bashrc` veya `~/.zshrc` dosyasina ekle:

```bash
# Claude Agent Teams - tmux swarm mode
# ca             → yeni claude session
# ca <isim>      → session'i title ile bulup resume et (renamed + unnamed)
# ca #N          → listeden numara ile session ac (ca #17)
# ca -l          → tum session'lari listele (numarali, AI son yanit, son 100)
# ca -p <isim>   → session'in son mesajlarini goster (peek)
# ca -p #N       → numara ile peek
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
```

---

## Adim 3b: `cc` Fonksiyonu — Direct Mode (tmux'suz)

`ca` ile birebir ayni session lookup/list/peek — ama tmux olmadan, dogrudan terminalde calisir.

### Fish

```fish
# Claude Code - direct mode (tmux'suz, dogrudan terminalde)
# cc             → yeni claude session
# cc <isim>      → session'i resume et
# cc #N          → listeden numara ile ac
# cc l / cc p    → list / peek (tire olmadan da calisir)
function cc
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

    set -l claude_args --dangerously-skip-permissions
    if test -n "$session_id"
        set -a claude_args --resume $session_id
    end

    cd $work_dir
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args
end
```

### Bash / Zsh

```bash
# Claude Code - direct mode (tmux'suz, dogrudan terminalde)
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

    cd "$work_dir"
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude $claude_args
}
```

---

## Adim 3c: Config Dosyasi (Opsiyonel)

`claude-sessions` davranisini ayarlamak icin:

```bash
cat > ~/.config/claude-sessions.json << 'EOF'
{
  "sort": "bottom-up",
  "limit": 100
}
EOF
```

| Ayar | Degerler | Default | Aciklama |
|------|----------|---------|----------|
| `sort` | `"bottom-up"` / `"top-down"` | `bottom-up` | En yeni altta veya ustte |
| `limit` | pozitif sayi | `100` | Listede gosterilecek max session |

> **Agent-friendly:** Config dosyasi yoksa default degerler kullanilir.
> Bir AI agent JSON dosyasini okuyup yazarak ayarlari degistirebilir.

---

## Adim 4: Kalici Env Variable (Opsiyonel)

`ca` fonksiyonu zaten env variable'i set eder. Her Claude baslatmada aktif olsun istersen:

### Fish
```fish
# ~/.config/fish/config.fish
set -gx CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1
```

### Bash / Zsh
```bash
# ~/.bashrc veya ~/.zshrc
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

---

## Kullanim

### Komutlar

| Komut | Ne Yapar |
|-------|----------|
| `ca` | Yeni Claude session, **tmux icinde** |
| `ca nvidia` | "nvidia" session'i bul, tmux'ta resume et |
| `ca #17` | Listeden 17. session'i tmux'ta ac |
| `ca l` / `ca -l` | Tum session'lari listele (numarali, AI son yanit) |
| `ca p nvidia` / `ca -p nvidia` | Session'in son 6 mesajini goster |
| `cc` | Yeni Claude session, **dogrudan terminalde** (tmux'suz) |
| `cc nvidia` | "nvidia" session'i bul, direkt resume et |
| `cc #17` | Listeden 17. session'i direkt ac |
| `cc l` / `cc -l` | Ayni liste (ca -l ile birebir ayni) |
| `cc p #5` / `cc -p #5` | 5. session'in mesajlarini goster |

### Session Workflow

```bash
# 1. Yeni proje baslat
ca
# Claude acilir, calis...
/rename fractal           # Claude icinde session'i isimlendir (bir kere yeterli)
# Ctrl+B d                → tmux'tan ayril

# 2. Session'a geri don
ca fractal                # JSONL'den bulur, dogru dizine gider, resume eder

# 3. Baska projeye gec
ca nvidia                 # nvidia session'i bulur, onun dizinine gider

# 4. Listeleme ve peek
ca -l                     # tum session'lar (renamed + unnamed, numarali)
ca -p fractal             # fractal'in son mesajlarina bak
ca -p #12                 # 12. session'in mesajlarina bak

# 5. Unnamed session acma (numara ile)
ca -l                     # listeyi gor, numara not et
ca #17                    # 17. session'i resume et
```

### Liste Ozellikleri

`ca -l` ciktisi:
- **Numarali satirlar** — her session'a `#N` atanir, `ca #N` ile acilir
- **AI son yaniti** — session'in son durumu gorunur (nerede kaldi)
- **Proje tag'leri** — `[project]` home disindaki projeler icin gosterilir
- **Dinamik genislik** — terminal boyutuna gore description kolonu ayarlanir
- **Renamed + Unnamed** — ust kisimda renamed, alt kisimda unnamed (toplam 100)

### Agent Team Baslatma

Claude acilinca dogal dilde team iste:

```
Create an agent team with 3 teammates:
- Teammate 1 (backend): Refactor src/api/ endpoints
- Teammate 2 (frontend): Update src/components/ to match new API
- Teammate 3 (tester): Write integration tests for all changes
Each teammate should own distinct files. Use delegate mode.
```

Her teammate otomatik olarak kendi tmux pane'inde acilir.

### tmux Navigasyon

| Islem | Mouse | Klavye |
|-------|-------|--------|
| Pane sec | Tikla | `Ctrl+B` → ok tuslari |
| Pane resize | Border'i surukle | `Ctrl+B` → `H/J/K/L` |
| Pane zoom (fullscreen) | — | `Ctrl+B` → `z` |
| Scroll | Mouse wheel | `Ctrl+B` → `[` → ok tuslari |
| tmux'tan ayril | — | `Ctrl+B` → `d` |
| Session'a geri don | — | `ca isim` |
| Tum session'lari gor | — | `tmux ls` |
| Session kapat | — | `tmux kill-session -t isim` |

---

## Error Handling

### Session bulunamadi

```
❯ ca yokbirsey

  Session 'yokbirsey' bulunamadi.

  Aranan dizin:   ~/.claude/projects/
  Taranan proje:  21 dizin
  Taranan JSONL:  458 dosya
  Aranan alan:    title + context icinde "yokbirsey"

  Renamed session'lar:
    tmux             2026-02-06 17:54
    nvidia           2026-02-06 13:49
    fractal          2026-02-06 13:36

  Ipucu: ca -l ile tum session'lari gor.
```

### CWD dizini artik yok

```
  CWD dizini bulunamadi!

  Session:       test-project
  UUID:          abc-123-def
  JSONL:         ~/.claude/projects/-home-user/abc.jsonl
  Kayitli CWD:   /home/user/Projects/silinmis-proje  ← bu dizin artik yok

  En yakin mevcut parent:  /home/user/Projects

  Ipucu: Session ~ (home) dizininden resume edilecek.
```

### tmux duplicate session

tmux ayni isimde iki session'a izin vermez. `ca nvidia` ikinci kez cagirildiginda:
- tmux session "nvidia" zaten varsa → `attach` olur (hata vermez)
- tmux session yoksa → yeni olusturur

---

## Ornek Senaryolar

**Paralel Refactoring:**
```
Create an agent team with 4 teammates:
- Backend: Refactor all API endpoints to use async/await
- Frontend: Update React components for new API responses
- Tests: Write comprehensive test coverage
- Reviewer: Code review all changes (read-only, opus model)
```

**Paralel Arastirma:**
```
Create an agent team with 3 teammates:
- Teammate 1: Research auth best practices for our stack
- Teammate 2: Audit current codebase for security issues
- Teammate 3: Document all existing API endpoints
```

**Bug Hunting:**
```
Create an agent team with 2 teammates:
- Teammate 1: Analyze error logs and stack traces in /var/log/
- Teammate 2: Review recent git commits for regression
```

---

## Karar Matrisi

| Senaryo | Yontem | Neden |
|---------|--------|-------|
| Tek hizli arastirma | **Subagent** (Task tool) | Hafif, hizli, ucuz |
| Paralel multi-file refactoring | **Agent Team** | Koordinasyon gerekli |
| Cross-layer feature (API+UI+test) | **Agent Team** | Birbirine bagli is |
| 50+ dosya batch migration | **Headless** (`claude -p &`) | Max paralellik |
| Basit sequential gorev | **Tek session** | Overhead gereksiz |

---

## Best Practices

1. **Her teammate'e DISTINCT dosyalar ver** — merge conflict onlenir
2. **Lead delegate mode kullansin** — koordine etsin, implement etmesin
3. **Kisa isimler ver** — `ca api`, `ca ui`, `ca test`
4. **`/rename` bir kere yeterli** — session'i isimlendir, sonra `ca isim` ile don
5. **`Ctrl+B d` ile ayril** — session arka planda yasar
6. **2-3 teammate yeterli** — her biri ayri maliyet

---

## Troubleshooting

| Sorun | Neden | Cozum |
|-------|-------|-------|
| `ca` bulunamadi | Shell config yuklu degil | `source ~/.config/fish/config.fish` |
| `claude-sessions` bulunamadi | Script yok veya PATH'te degil | `chmod +x ~/.local/bin/claude-sessions` + PATH kontrol |
| Pane'ler acilmiyor | tmux icinde degilsin | `echo $TMUX` — bos olmamali |
| Mouse calismiyor | tmux config yuklu degil | `tmux set -g mouse on` |
| Session bulunamiyor | `/rename` yapilmamis veya text eslesmiyor | `ca -l` ile listele, `ca #N` ile numara ile ac |
| duplicate session | Ayni isimde tmux session var | `ca` otomatik attach olur, sorun yok |
| CWD dizini yok | Proje dizini silinmis | Home'dan resume edilir, uyari gosterilir |
| Claude kapaninca tmux kapandi | Alias hatali | `ca` fonksiyonu `exec fish` ile shell'e dusurur |

---

## Agent Icin Kurulum Kontrol Listesi

```
[ ] tmux kurulu ve >= 3.2
[ ] ~/.tmux.conf olusturuldu
[ ] ~/.local/bin/claude-sessions olusturuldu ve +x
[ ] Ghostty: focus-follows-mouse = true (Ghostty kullanicilariysa)
[ ] Shell config'e ca fonksiyonu eklendi (fish veya bash/zsh)
[ ] ca komutu calisiyor (yeni terminal'den test)
[ ] ca -l renamed session'lari listeliyor
[ ] ca <isim> dogru session'i bulup resume ediyor
[ ] tmux mouse calisiyor
[ ] Agent Teams aktif (pane'ler otomatik aciliyor)
```

---

## Diger Dokumanlar

- **[DEVLOG.md](DEVLOG.md)** — Gelistirme sureci, troubleshooting, bug fix'ler, mimari kararlar

---

*Claude Code Agent Teams Guide — 2026-02-09*
*Fish + Bash/Zsh uyumlu | Ghostty/Alacritty/Kitty/iTerm2 destekli*
