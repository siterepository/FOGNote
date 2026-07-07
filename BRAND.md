# FOGNote Brand Identity

**Positioning:** clarity emerging from fog. Calm, local, private — your notes and your calls, on your Mac, nowhere else.

**Tagline:** *Evernote × Apple Notes, merged.*
**Voice:** short, direct, no cloud-hype. Feature names are plain words (Recordings, Templates, Trash).

## Logo

Folded note page emerging from three fog bands. The page = the note; the fog = everything unprocessed that FOGNote turns into clarity (search, transcripts, summaries).

| Asset | File | Use |
|---|---|---|
| App icon | `Assets/brand/icon.svg` → `Assets/FOGNote.icns` | Dock, Finder |
| Mark (color) | `Assets/brand/logo.svg` | README, web, 16–512 px |
| Mark (mono) | `Assets/brand/logo-mono.svg` | Menu bar, single-color contexts (`currentColor`) |
| Wordmark lockup | `Assets/brand/wordmark.svg` | Headers, marketing |

Rules: don't rotate, recolor the fog bands individually, or place the color mark on saturated backgrounds. Mono mark on anything non-neutral.

## Color

| Role | Hex | Usage |
|---|---|---|
| Fog Blue (primary) | `#6B9FD4` | Accent, links, active states, tags |
| Deep Fog | `#4F7FB4` | Strokes, pressed states |
| Mist Purple | `#8B7FB3` | Templates, secondary highlights |
| Signal Amber | `#F59E0B` | Reminders, highlights, "urgent" |
| Lock Red | `#FF6B6B` | Locked notes, destructive |
| Record Red | `#E5484D` | Recording state |
| Fog ramp | `#FFFFFF → #E8E8E7 → #D1D1CF → #8B8B89 → #4A4A48` | Surfaces, borders, secondary text |

Backgrounds: system (`.background`) — never hardcode; the app is native light/dark.

## Typography

SF Pro via system fonts only. Titles 22 pt bold, note list 13/11 pt, editor body 14 pt, UI captions 10–11 pt. No custom fonts.

## Iconography

SF Symbols only: `note.text`, `book.closed`, `folder.circle`, `tag`, `magnifyingglass.circle`, `pin`, `lock`, `doc.text.image`, `checkmark.circle`, `bell.badge`, `clock.arrow.circlepath`, `waveform.circle` (recordings), `record.circle` (record), `sparkles` (AI summary).
