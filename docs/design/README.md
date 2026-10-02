# Ataste design (exported from Claude Design)

The source of truth for every screen, for developers without Claude Design access.

| Path | What |
|---|---|
| `frames/` | One PNG per screen at 2x (402 × 874 pt phone frames; 1 design px = 1 pt). File names are the design's screen ids, e.g. `2-1-Home.png`, `5-9-Payment-board.png`. Start here. |
| `boards/` | The original boards. Open any `.dc.html` in Chrome or Safari (works offline except the web fonts). Exact sizes, colours, fonts and copy are in the HTML; `ataste-art.js` holds the shared pieces (tags, avatars, nav, tab bar, marquee). |
| `boards/Ataste Design System.dc.html` | Colours, type scale, spacing, radii, buttons, tags, fields, cards, states. Maps to `AtasArtisan/Shared/Brand.swift` and `Components.swift`. |
| `boards/Ataste Flow Map.dc.html` | How the screens connect. |
| `boards/Ataste Notifications.dc.html` | Wording of all 22 push notifications (server side: `supabase/migrations/*notification_copy.sql`). |

Boards: 1 Onboarding · 2 Home and groups · 3 Group and menu · 4 Split and review · 5 Send, bill and after · 6 History, profile and states · Brand.

## Updating after a Claude Design change

1. In Claude Design: Share → Project HTML → Project archive → Export (downloads `Ataste iOS app design.zip`).
2. `docs/design/update.sh ~/Downloads/"Ataste iOS app design.zip"` replaces `boards/` and re-renders `frames/`
   (needs `uv` and Google Chrome).
3. Commit `docs/design`.
