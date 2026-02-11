
# CODEX_NEXT_UI.md — Tailwind “hackery” dark theme + spacing/layout cleanup

## Goal
Restyle the entire NetMon UI with Tailwind:
- black background, green-ish “terminal” accents
- readable density (tables still compact)
- consistent spacing/padding/typography
- keep pages fast (no heavy JS frameworks)
- make charts match the theme
- fix alignment issues in filters/top panels/tables

Constraints:
- Use Tailwind that is already in the Rails app (no new CSS frameworks).
- Do not change data logic.
- Keep HTML semantic and accessible (contrast, focus rings).
- Avoid huge refactors; apply a shared layout + partials.

---

## Step A — Establish a global layout + theme tokens
1) Create/modify `app/views/layouts/application.html.erb` to apply:
   - `class="bg-black text-zinc-100"`
   - use a monospace stack:
     - `font-mono` with fallback
   - set a centered max width and padding:
     - `max-w-[1600px] mx-auto px-4 py-4`

2) Define a simple “theme token” set via Tailwind utility choices:
   - background: `bg-black`, cards: `bg-zinc-950/60`, borders: `border-zinc-800`
   - primary: `text-emerald-400`, secondary: `text-zinc-300`
   - muted: `text-zinc-500`
   - badges:
     - normal: `bg-zinc-900 text-zinc-200`
     - warn: `bg-amber-900/40 text-amber-200 border border-amber-700/50`
     - alert: `bg-red-950/40 text-red-200 border border-red-700/50`
     - success: `bg-emerald-950/40 text-emerald-200 border border-emerald-700/50`

---

## Step B — Componentize UI fragments (partials)
Create partials in `app/views/shared/`:
- `_topbar.html.erb` (nav links + quick actions)
- `_filter_bar.html.erb` (filters + apply/clear + score quick buttons)
- `_stat_card.html.erb` (load avg/mem/interfaces etc)
- `_panel_card.html.erb` (Top-N boxes)
- `_badge.html.erb` (score badge, seen badge, ack badge)
- `_table.html.erb` (standard table wrapper)

Goal: every page uses the same structure so spacing stays consistent.

---

## Step C — Rebuild dashboard layout with Tailwind grid
Use a clear grid:
- top row: filters / controls in a sticky bar:
  - `sticky top-0 z-50 bg-black/80 backdrop-blur border-b border-zinc-800`
- stats row: `grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3`
- charts row: `grid grid-cols-1 lg:grid-cols-4 gap-3`
- Top-N row: `grid grid-cols-1 lg:grid-cols-4 gap-3`
- table: full width card beneath.

Ensure spacing:
- cards: `rounded-lg border border-zinc-800 bg-zinc-950/60 p-3`
- headings: `text-xs uppercase tracking-wider text-zinc-400`
- values: `text-lg text-zinc-100`

---

## Step D — Make tables compact but readable
Table wrapper:
- `overflow-x-auto rounded-lg border border-zinc-800`
- `table class="min-w-full text-sm"`

Row styling:
- header: `bg-zinc-950 text-zinc-300 text-xs uppercase`
- rows: `odd:bg-black even:bg-zinc-950/40`
- hover: `hover:bg-zinc-900/60`
- padding: `px-2 py-1.5` (keep it dense)

Column alignment:
- numeric columns right aligned
- codes/reasons use `text-xs` and `whitespace-nowrap` with truncation:
  - `max-w-[240px] truncate`

Score badge:
- show number inside a pill
- use color bands:
  - 0–19 normal
  - 20–49 warn
  - 50–69 high
  - 70+ alert

---

## Step E — Make “hackery” accents without being cringe
- topbar includes a small “NETMON” label in `text-emerald-400`
- subtle scanline effect optional:
  - add a pseudo-element or background gradient only if cheap (no animations)
- use `text-emerald-300` for links on hover:
  - `text-zinc-300 hover:text-emerald-300 underline-offset-2 hover:underline`

---

## Step F — Charts theme consistency
If charts are inline SVG/canvas:
- set background transparent
- set axes/labels to `zinc` colors
- line colors: keep what you already have if it’s code-heavy; otherwise:
  - bytes chart: emerald
  - ports: amber
  - new dst: cyan
Keep it subtle; don’t overdo neon.

---

## Step G — Apply styling to all pages
Pages to update:
- dashboard (/)
- anomalies (/anomalies)
- remote host page (/hosts/:ip or whatever route)
- new remote hosts page
- search pages (hosts/connections/anomalies)
- devices edit page

---

## Step H — Verify usability
- test on 1080p and small screen widths
- verify tables don’t explode spacing
- verify focus rings visible (keyboard nav)
- ensure important links/buttons still obvious

Deliverables:
- All pages use shared layout and cards
- Tailwind only, no extra libs
- Dark hackery theme applied consistently
- No change to business logic
