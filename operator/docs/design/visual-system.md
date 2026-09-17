# Visual System — Atlas Operator

No existing Atlas brand assets exist, so this is a fresh minimal system.

## Color (one role each — build rule 29)
- Primary: deep slate blue — chrome, active nav, primary actions
- Accent: amber — used ONLY for attention states (degraded, stale)
- Neutrals: 5-step gray scale — backgrounds, borders, secondary text
- Semantic: green (healthy), amber (degraded/stale), red (failed),
  gray (unknown/offline)

## Typography
One typeface family, two roles:
- UI text: Inter (or system default) — labels, nav, body
- Data/metrics: a monospace (e.g. IBM Plex Mono) — job IDs, SHAs,
  numeric metrics, so digits align and don't jitter on update

## Spacing scale
4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 — tighter (4/8/12) for data-dense
lists, larger (24/32/48) for section breaks and primary actions.

## Border radius
- Data surfaces (lists, tables, log lines): 4px — sharp, dense
- Primary interactive surfaces (buttons, cards you tap into): 12px

## Icons
Lucide (`lucide_icons` Flutter package). One system only. No emoji
as functional icons.

## Explicitly avoided
Purple/pink gradients, glassmorphism, decorative shadows on every
card, three-column feature-grid SaaS layouts.
