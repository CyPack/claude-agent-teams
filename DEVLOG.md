# Claude Agent Teams - Development Log

> Bu dokuman `ca` komutunun sifirdan nasil gelistirildigini, karsilasilan sorunlari,
> troubleshooting surecini ve final mimariyi anlatir.

---

## Motivasyon

Bir tweet goruldu: Claude Code Agent Teams ile tmux icinde multi-agent swarm calistiriliyor.
Her agent kendi tmux pane'inde paralel calisiyor. Bunu kurmak ve session yonetimini
kolaylastirmak icin `ca` komutu gelistirildi.

**Hedef:** Tek komutla Claude Code session'larini bulup resume edebilmek.

---

## Kronolojik Gelistirme Sureci

### Phase 1: Temel Kurulum

1. **tmux config** olusturuldu (`~/.tmux.conf`)
   - Mouse destegieklendi (Ghostty terminal ile uyumlu)
   - Catppuccin renk temasi
   - Pane resize keybinding'leri (H/J/K/L)

2. **Env variable** ayarlandi
   - `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
   - `settings.json`'a programatik ekleme denendi → hook korumasi engelledi → manuel eklendi

3. **Ilk `ca` fonksiyonu** yazildi (fish shell)
   - `ca` → yeni tmux session + claude
   - `ca fractal` → session bul + resume

### Phase 2: Session Lookup — Yanlis Alan Problemi

**Ilk yaklasim:** JSONL dosyalarinda `"type":"summary"` + `"summary"` alani araniyordu.

**Sorun:** `ca nvidia` ve `ca fractal` calismiyordu. Session bulunamiyordu.

**Root Cause Analizi (Derin Arastirma):**
- `/rename` komutu `"type":"summary"` DEGIL, `"type":"custom-title"` olusturuyor
- `"summary"` alani otomatik olusturulan baslik (Claude'un kendisi yaziyor)
- `"custom-title"` alani kullanicinin `/rename` ile verdigi isim

**JSONL kayit yapisi:**
```json
{"type":"custom-title","customTitle":"nvidia"}     ← /rename ile
{"type":"summary","summary":"GPU driver setup..."}  ← otomatik
```

**Fix:** Arama `"type":"custom-title"` + `"customTitle"` alanina cevrildi.

### Phase 3: CWD (Working Directory) Problemi

**Sorun:** `claude --resume <UUID>` project-scoped. Yanlis dizinden calistirilirsa
"No conversation found" hatasi veriyor.

**Ornek:**
- nvidia session `/home/user/Git/sync` dizininde olusturuldu
- `ca nvidia` `/home/user`'dan calistirilinca → bulunamadi

**Fix:** JSONL'den `"cwd"` alani okunuyor, `cd <cwd>` yapildiktan sonra resume ediliyor.

### Phase 4: Session Dizini (isdir) Problemi

**Sorun:** `ca bosluk` calismiyordu. Script session dizininin varligini kontrol ediyordu
(`os.path.isdir()`), ama kisa session'lar icin Claude Code dizin olusturmuyor.

**Kanit:** Claude Code'un kendi `/resume` ekraninda bosluk gorunuyordu (Screenshot ile dogrulandi).

**Fix:** `os.path.isdir()` kontrolu kaldirildi. JSONL dosyasi yeterli, dizin gerekli degil.

### Phase 5: Inline Python → Ayri Script

**Sorun:** Fish fonksiyonu icinde 2 ayri Python blogu vardi — tekrar eden kod, zor bakım.

**Fix:** `~/.local/bin/claude-sessions` Python helper scripti olusturuldu.
Fish fonksiyonu sadece bu scripti cagiriyor.

```
ca nvidia
  → claude-sessions search nvidia   (Python)
  → UUID|CWD doner
  → tmux new-session + claude --resume
```

### Phase 6: tmux Duplicate Session

**Sorun:** `ca nvidia` ikinci kez calistirilinca:
```
duplicate session: nvidia
```

**Neden:** tmux ayni isimde iki session'a izin vermiyor. Eski kod sadece `new-session` yapiyordu.

**Fix:**
```fish
if tmux has-session -t "$tmux_name" 2>/dev/null
    tmux attach-session -t "$tmux_name"   ← varsa attach
else
    tmux new-session -s $tmux_name ...     ← yoksa olustur
end
```

### Phase 7: stdout/stderr Karisma Bug'i

**Sorun:** `ca guru` yazildiginda (session yok) hicbir sey olmuyordu — ne hata ne tmux.

**Root Cause:**
1. `claude-sessions search guru` basarisiz → hata mesajini **stdout**'a yaziyordu
2. Fish fonksiyonu stdout'u `$lookup` degiskenine aliyordu
3. `$lookup` dolu (hata metni) → `test -n "$lookup"` TRUE
4. `string split '|' $lookup` → cop veri (UUID|CWD degil, hata metni)
5. Bozuk UUID ile tmux + claude calistiriliyordu → sessiz hata

**Fix:**
1. Tum hata mesajlari `stderr`'e yonlendirildi (`eprint()` fonksiyonu)
2. Fish fonksiyonuna `$status -eq 0` kontrolu eklendi

```python
def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
```

```fish
set -l lookup (claude-sessions search $argv[1])
if test $status -eq 0 -a -n "$lookup"   ← exit code + output kontrolu
```

### Phase 8: Title'siz Session'lar

**Sorun:** `ca -l` sadece 138 unnamed session gosteriyordu. Feb 7-9 arasi session'lar
listede yoktu.

**Root Cause:** Bu session'larda ne `custom-title` ne `summary` vardi. Claude Code
her session'a summary olusturmuyor.

**Fix:** Title fallback zinciri eklendi:
```
1. custom-title  (/rename ile verilen isim)
2. summary       (otomatik baslik)
3. ilk user mesaji (ilk 60 karakter)
```

```python
def _extract_first_user_text(f):
    """JSONL'den ilk user mesajinin text'ini cek."""
    ...
```

### Phase 9: Unnamed Session Resume

**Sorun:** `ca T4FServer` calismiyordu — sadece renamed session'lar araniyordu.

**Fix:** `find_match()` fonksiyonu tum session'larda ariyor, oncelik sirasi:
1. Renamed exact match (nvidia == nvidia)
2. Renamed partial match (nvi ⊂ nvidia)
3. Unnamed exact match
4. Unnamed partial match

### Phase 10: Liste Limiti

**Baslangic:** 20 unnamed session gosteriliyordu
**Guncelleme 1:** 50'ye cikarildi
**Guncelleme 2:** 100'e cikarildi (renamed + unnamed toplam)

### Phase 11: Context Display — Proje Tag'leri ve Noise Filter

**Sorun:** Unnamed session'larin basliklari ilk user mesajindan geliyordu — genelde
cryptic ve anlamsiz (ornegin "merhaba", "devam et"). Session'in ne hakkinda oldugu anlasilmiyordu.

**Cozumler:**
1. **Son user mesaji (context):** Ilk mesaj yerine son kullanici mesaji gosteriliyor — session'in
   mevcut durumunu daha iyi yansitir
2. **Proje tag'leri:** `[project]` tag'i CWD'den cikariliyor. Home dizini icin `~` gosterilmez,
   sadece farkli projelerde tag gorunur (alan tasarrufu)
3. **Noise filter:** "This session is being continued..." ve "[Request interrupted..." gibi
   teknik mesajlar filtreleniyor

**Yeni fonksiyonlar:**
```python
_NOISE_PREFIXES = ("This session is being continued", "[Request interrupted")
def _is_noise(text): ...
def _project_name(cwd): ...
```

**`find_match()` guncellemesi:** Artik context alaninda da arama yapar
(title > context > last_ai sirasiyla).

### Phase 12: AI Son Yanit ve Dinamik Terminal Genisligi

**Kullanici istegi:** "AI'in verdigi son cevabi gosterir mi? Chat en son nerede stop olmus
onu gormek icin. Sutun yapisini daha genis gorebilirsek daha iyi olur."

**Cozumler:**
1. **`_get_msg_text(d)`:** Unified text extractor — hem user hem assistant JSONL entry'lerinden
   text cikarir (onceden ayri fonksiyonlar vardi)
2. **`last_asst_text` tracking:** `scan_sessions()` dongusunde assistant mesajlari da izleniyor
3. **`shutil.get_terminal_size()`:** Terminal genisligi dinamik olarak alinir, description
   kolonu tum ekrani kullanir
4. **AI response oncelikli:** Listede AI'in son yaniti gosterilir (session nerede kaldi),
   yoksa son user mesaji fallback olarak kullanilir

**Yeni fonksiyon:** `_term_width()` — `shutil.get_terminal_size().columns` wrapper

### Phase 13: Numarali Liste ve `ca #N` ile Acma

**Sorun:** Kullanici `ca -l` ile unnamed session'lari goruyor ama onlari nasil acacagini
bilmiyor. AI response'unda arama yapmak belirsiz (mevcut session da eslesiyor).

**Cozum:** Her session'a numara atandi (`#1`, `#2`, ...). `ca #17` veya `ca 17` ile
direkt acilir.

**Implementasyon:**
- `cmd_list()`: Global `idx` sayaci ile her satira numara yaziyor
- `find_match()`: `#N` veya saf sayi pattern'i algilayip ordered list'ten buluyor
- `cmd_peek()` ve `cmd_search()` de `find_match()` kullandigi icin otomatik destekliyor

```python
num_str = name.lstrip("#")
if num_str.isdigit():
    ordered = renamed + unnamed[:show_count]
    n = int(num_str)
    if 1 <= n <= len(ordered):
        return ordered[n - 1], all_sessions, scanned_dirs
```

### Phase 14: Renamed Session'larda Tarih Sola

**Kullanici istegi:** Renamed session'larin tarihleri unnamed'lerle ayni formatta (sol tarafta)
gosterilsin — tutarli layout.

**Onceki format:** `#N  isim  tarih  boyut  AI yanit`
**Yeni format:** `#N  tarih  isim  boyut  AI yanit`

### Phase 15: `cc` — Direct Mode (tmux'suz)

`ca` ile birebir ayni session lookup/list/peek — ama tmux olmadan, dogrudan terminalde.
Fish ve Bash versiyonlari eklendi. Shorthand flag'ler (`l`, `p`) tire olmadan da calisir.

### TODO: Aktif Pane Border Iyilestirmesi

**Bulgu:** Claude Code agent pane'lerini spawn ederken pane seviyesinde kendi
`pane-border-format` degerini set ediyor. tmux option resolution sirasi
Pane > Window > Global oldugu icin bizim global config eziliyor.

- Ana pane (fish shell): global config'i inherit eder — calisiyor
- Agent pane'leri: Claude Code explicit override yapiyor — bizim format gorulmuyor

**Olasi cozumler (uygulanmadi):**
1. `after-split-window` tmux hook ile her yeni pane'de pane-level format'i sil
2. Agent spawn sonrasi manuel reset komutu
3. `ca` fonksiyonuna post-spawn reset entegre et

**Referans:** tmux 3.5a, `show-options -p -t %N` ile pane-level override kontrol edilebilir.

### Phase 16: Configurable Sort Order ve Session Limit

**Kullanici istegi:** Siralama yonu (bottom-up / top-down) ve gosterilecek session sayisi
kullanici tarafindan ayarlanabilir olsun. Farkli kullanicilar farkli tercihler yapabilsin.

**Cozum:** `~/.config/claude-sessions.json` config dosyasi.
```json
{"sort": "bottom-up", "limit": 100}
```

| Ayar | Degerler | Default |
|------|----------|---------|
| `sort` | `"bottom-up"` (en yeni altta) / `"top-down"` (en yeni ustte) | `bottom-up` |
| `limit` | pozitif sayi (20, 50, 100...) | `100` |

**Implementasyon:**
- `_load_config()` fonksiyonu her `list` cagirisinda JSON okur
- `find_match()` da limit degerini config'den alir (#N numaralama tutarli kalir)
- Dosya yoksa veya bozuksa default degerler kullanilir
- Agent-friendly: AI JSON dosyasini okuyup yazarak ayarlari degistirebilir

---

## Final Mimari

### Dosya Yapisi

```
~/.local/bin/claude-sessions          # Python helper (search|list|peek)
~/.config/claude-sessions.json        # Config (siralama, limit)
~/.config/fish/config.fish            # Fish shell ca/cc fonksiyonlari
~/.tmux.conf                          # tmux ayarlari
~/.claude/projects/*/                 # Claude Code session JSONL dosyalari
~/.claude/settings.json               # Claude Code ayarlari
```

### Veri Akisi

```
ca nvidia
  │
  ├── claude-sessions search nvidia
  │     │
  │     ├── ~/.claude/projects/*/*.jsonl   ← TUM proje dizinleri taranir
  │     │
  │     ├── Satir satir JSON parse:
  │     │     "type":"custom-title" → /rename ismi
  │     │     "type":"summary"      → otomatik baslik
  │     │     ilk user mesaji       → fallback baslik
  │     │     "cwd"                 → calisma dizini
  │     │
  │     ├── Eslesme onceligi:
  │     │     renamed exact > renamed partial > unnamed exact > unnamed partial
  │     │
  │     ├── stdout: UUID|CWD  (basarili)
  │     └── stderr: hata mesaji (basarisiz, exit 1)
  │
  ├── Fish fonksiyonu:
  │     $status -eq 0 → parse UUID|CWD
  │     $status -ne 0 → return 1 (hata stderr'de gorulur)
  │
  └── tmux:
        ├── tmux icinde → new-window
        ├── session var → attach
        └── session yok → new-session
              └── cd <CWD> && claude --resume <UUID>
```

### Komutlar

| Komut | Aciklama |
|-------|----------|
| `ca` | Yeni Claude session, **tmux icinde** |
| `ca nvidia` | "nvidia" session'i bul (renamed veya unnamed), tmux'ta resume et |
| `ca #17` | Listeden 17. session'i tmux'ta ac (numara ile) |
| `ca l` / `ca -l` | Tum session'lari listele (numarali, AI son yanit) |
| `ca p nvidia` / `ca -p nvidia` | Session'in son 6 mesajini goster |
| `cc` | Yeni Claude session, **dogrudan terminalde** (tmux'suz) |
| `cc nvidia` | "nvidia" session'i bul, direkt resume et |
| `cc #17` | Listeden 17. session'i direkt ac |
| `cc l` / `cc -l` | Ayni liste (ca -l ile birebir ayni) |
| `cc p #5` / `cc -p #5` | 5. session'in mesajlarini goster |

### Error Handling

| Durum | Davranis |
|-------|----------|
| Session bulunamadi | stderr'e detayli rapor: aranan dizin, taranan dosya sayisi, mevcut session'lar |
| CWD dizini yok | stderr'e uyari, en yakin parent dizin gosterilir, home'dan resume edilir |
| tmux duplicate | Mevcut session'a attach olur |
| JSONL bozuk | try/except ile atlanir |
| claude-sessions yok | fish "command not found" verir |

### JSONL Yapisi (Claude Code)

Claude Code her session'i su formatta saklar:
```
~/.claude/projects/<proje-dizini-encoded>/<UUID>.jsonl
```

Proje dizini encoding ornegi:
```
/home/user           → -home-user
/home/user/Git/sync  → -home-user-Git-sync
```

JSONL icindeki onemli satirlar:
```json
{"type":"user","message":{"content":[{"type":"text","text":"merhaba"}]},"cwd":"/home/user"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Merhaba!"}]}}
{"type":"custom-title","customTitle":"nvidia"}
{"type":"summary","summary":"GPU driver installation and config"}
{"type":"agent-name","agentName":"nvidia","sessionId":"..."}
```

**Kritik bilgi:**
- `/rename nvidia` → `{"type":"custom-title","customTitle":"nvidia"}` olusturur
- Otomatik baslik → `{"type":"summary","summary":"..."}` olusturur
- Bunlar FARKLI alanlar! Arama onceligi: custom-title > summary > ilk user mesaji

---

## Troubleshooting Rehberi

### `ca` komutu bulunamadi
```bash
# Fish
source ~/.config/fish/config.fish

# Bash/Zsh
source ~/.bashrc  # veya ~/.zshrc
```

### `claude-sessions` bulunamadi
```bash
# Script var mi?
ls -la ~/.local/bin/claude-sessions

# PATH'te mi?
echo $PATH | tr ':' '\n' | grep local

# Fish PATH ekleme
fish_add_path ~/.local/bin

# Bash/Zsh PATH ekleme
export PATH="$HOME/.local/bin:$PATH"
```

### Session bulunamiyor
```bash
# Tum renamed session'lari gor
claude-sessions list

# Detayli arama
claude-sessions search "isim" 2>&1

# JSONL dosyasini manuel kontrol et
python3 -c "
import json
for line in open('~/.claude/projects/-home-user/UUID.jsonl'):
    d = json.loads(line)
    if d.get('type') in ('custom-title', 'summary'):
        print(d)
"
```

### tmux sorunlari
```bash
# Session'lari gor
tmux ls

# Duplicate temizle
tmux kill-session -t nvidia

# Mouse calismiyorsa
tmux set -g mouse on

# Config reload
tmux source-file ~/.tmux.conf
```

### Claude resume hatasi
```
No conversation found with session ID: <UUID>
```
**Neden:** Yanlis dizinden calistirildi. `claude --resume` project-scoped.
**Cozum:** `ca` fonksiyonu zaten JSONL'den CWD'yi okuyup dogru dizine gidiyor.
Manuel resume icin: `cd <dogru-dizin> && claude --resume <UUID>`

---

## Ogrenilenler (Lessons Learned)

1. **`/rename` != `summary`**: Claude Code'un JSONL yapisinda iki farkli baslik alani var.
   Bu ayrim dokumante edilmemis, deneme-yanilma ile bulundu.

2. **stdout/stderr ayirimi kritik**: Shell fonksiyonlari command substitution ile
   stdout'u yakalayinca, hata mesajlari stdout'a giderse parsing bozulur.

3. **`os.path.isdir()` yaniltici**: Claude Code session dizini olmadan da resume edebiliyor.
   JSONL dosyasi yeterli.

4. **Title fallback gerekli**: Tum session'larda summary olmayabiliyor.
   Ilk user mesaji guvenilir bir fallback.

5. **tmux session isimleri unique olmali**: Ayni isimde ikinci `new-session` "duplicate" verir.
   Onceden `has-session` kontrolu gerekli.

6. **`claude --resume` project-scoped**: Dogru dizinden calistirilmali.
   JSONL'deki `cwd` alani bu bilgiyi sagliyor.

7. **Noise filtering zorunlu**: Claude Code'un teknik mesajlari ("This session is being
   continued...", "[Request interrupted...") context alanini kirletiyor.

8. **AI son yaniti en faydali context**: Session listesinde en bilgilendirici bilgi AI'in
   son cevabi — session nerede kaldi hemen goruluyor.

9. **Numara ile erişim essential**: Text search belirsiz olabilir (ayni kelime birden fazla
   session'da). Numarali liste + `#N` erişim en guvenilir yontem.

10. **Dinamik terminal genisligi**: Sabit kolon genislikleri dar terminallerde bozuluyor.
    `shutil.get_terminal_size()` ile adaptif layout onemli.

---

## Referanslar

| Kaynak | Aciklama |
|--------|----------|
| `~/.claude/projects/` | Claude Code session deposu |
| `~/.claude/settings.json` | Claude Code ayarlari |
| Claude Code `/rename` | Session isimlendirme komutu |
| Claude Code `/resume` | Session listeleme/resume ekrani |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Agent Teams env variable |
| tmux | Terminal multiplexer |
| Ghostty | GPU-accelerated terminal (test edilen) |

---

## Repo ve Paylasim

- **GitHub Repo:** https://github.com/CyPack/claude-agent-teams
- **GitHub Gist:** https://gist.github.com/CyPack/735eca1dca19bf1ac158aa3d02b26a62

---

*Gelistirme sureci: 2026-02-06 ~ 2026-02-09*
*Fish + Bash/Zsh uyumlu | Ghostty/Alacritty/Kitty/iTerm2 test edildi*
