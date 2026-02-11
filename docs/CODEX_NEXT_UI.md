# CODEX_NEXT_UI.md — Tailwind dark “hacker” theme (Emerald primary + Electric Blue secondary) + spacing cleanup

## Goal
Restyle the entire NetMon UI with Tailwind to a cohesive dark theme:
- black / near-black background
- **emerald** primary accents (brand, headings, OK states)
- **electric blue/cyan** secondary accents (links, focus, active controls)
- dense but readable tables
- consistent spacing and alignment across dashboard/anomalies/hosts/search
- keep pages fast (no heavy JS frameworks)
- charts visually match the theme

Do NOT change data logic. This is strictly UI + view structure.

Constraints:
- Use Tailwind already in the Rails app (no new CSS frameworks).
- Keep HTML semantic and accessible (contrast, focus rings, keyboard nav).
- Avoid big refactors; prefer shared layout + partials.
- No new dependencies without explicit permission.
- Don’t introduce custom CSS unless absolutely required; prefer Tailwind utilities.

Design reference:
- dark UI with soft glow, emerald highlights, cyan interaction accents (user-provided reference image).

---

## Visual Reference for Style

Use the screenshots (attached) as a reference for:
- color intensity
- mood (dark + vibrant accents)
- contrast
- spacing rhythm

Match:
- emerald/green as primary accent
- electric blue/cyan as link/focus/interactive
- amber for warning, red for alerts

## Step A — Global layout + base theme tokens
1) Update `app/views/layouts/application.html.erb`:
   - page wrapper: `class="bg-black text-zinc-200 min-h-screen font-mono"`
   - constrain width: `max-w-[1600px] mx-auto px-4 py-4`
   - default link style: `text-cyan-300 hover:text-cyan-200 underline-offset-2 hover:underline`
   - ensure focus rings visible: `focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400/60 focus-visible:ring-offset-2 focus-visible:ring-offset-black`

2) Define consistent “tokens” via utility choices (use everywhere):
   - background: `bg-black`
   - panel/card: `bg-zinc-950/70`
   - border: `border-zinc-800/80`
   - subtle glow: `shadow-[0_0_0_1px_rgba(16,185,129,0.10)]` (emerald hairline)
   - primary text: `text-zinc-200`
   - muted text: `text-zinc-500`
   - primary accent (emerald): `text-emerald-400`
   - secondary accent (cyan): `text-cyan-300`
   - “interactive cyan”: `hover:text-cyan-200`, `ring-cyan-400/50`
   - success: emerald
   - warning: amber
   - danger: red

Badge palette:
- neutral: `bg-zinc-900/60 text-zinc-200 border border-zinc-800`
- info (cyan): `bg-cyan-950/30 text-cyan-200 border border-cyan-800/40`
- ok (emerald): `bg-emerald-950/30 text-emerald-200 border border-emerald-800/40`
- warn (amber): `bg-amber-950/30 text-amber-200 border border-amber-800/40`
- alert (red): `bg-red-950/30 text-red-200 border border-red-800/40`

---

## Step B — Shared UI partials (reduce drift, fix spacing)
Create/standardize partials in `app/views/shared/`:
- `_topbar.html.erb`:
  - left: brand label “NETMON” in emerald
  - right: nav links (Dashboard, Anomalies, Incidents, Hosts, Search, Devices)
  - use compact pill links with cyan hover
- `_filter_bar.html.erb`:
  - consistent spacing, aligned controls, Apply/Clear on right
  - inputs styled uniformly
- `_card.html.erb`:
  - generic card wrapper for stat panels and boxes
- `_stat.html.erb`:
  - label/value pair pattern (small label, large value)
- `_badge.html.erb`:
  - generic badge renderer with variants
- `_table.html.erb`:
  - consistent table wrapper + header/row styling
- `_pill_button.html.erb` (optional):
  - for score quick filters (Score 0+/20+/50+) and toggles

Goal: every page shares the same visual language and spacing.

---

## Step C — Navigation + page chrome
1) Make the topbar sticky:
   - `sticky top-0 z-50 bg-black/80 backdrop-blur border-b border-zinc-800/70`
2) Keep “action cluster” (Apply/Clear/quick filters) on the right, consistent across pages.
3) Provide a subtle divider under the topbar to anchor the UI.

---

## Step D — Dashboard layout (grid + cards)
Layout structure:
- Filter bar (sticky)
- Stats row:
  - `grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3`
- Charts row:
  - `grid grid-cols-1 lg:grid-cols-4 gap-3`
- Top-N row:
  - `grid grid-cols-1 lg:grid-cols-4 gap-3`
- Table row:
  - full width card

Card styling (apply everywhere):
- `rounded-xl border border-zinc-800/80 bg-zinc-950/70 p-3 shadow-[0_0_0_1px_rgba(16,185,129,0.10)]`
Headings:
- `text-xs uppercase tracking-wider text-zinc-500`
Values:
- `text-lg text-zinc-100`

---

## Step E — Table styling (dense, readable, aligned)
Table wrapper:
- `overflow-x-auto rounded-xl border border-zinc-800/80 bg-zinc-950/50`

Table:
- `min-w-full text-sm`

Header:
- `bg-zinc-950 text-zinc-400 text-xs uppercase tracking-wider`

Rows:
- `odd:bg-black even:bg-zinc-950/30`
- hover: `hover:bg-zinc-900/50`

Cell padding:
- `px-2 py-1.5` (keep dense)

Alignment:
- numeric columns right-aligned
- proto/state/flags monospace
- long fields (reasons/rdns/org) use truncation:
  - `max-w-[260px] truncate`

Score badge:
- pill with color bands:
  - 0–19: neutral
  - 20–49: info (cyan)
  - 50–69: warn (amber)
  - 70+: alert (red)
Also show tooltip/title with reasons.

Seen badge:
- `NEW` gets cyan or emerald (your choice; default cyan)
- `SEEN` stays neutral

Ack badge:
- acked: neutral
- unacked: cyan outline

---

## Step F — Forms/inputs/buttons (consistent)
Inputs:
- `bg-black border border-zinc-800 rounded-lg px-2 py-1 text-zinc-200 placeholder:text-zinc-600`
Focus:
- `focus-visible:ring-2 focus-visible:ring-cyan-400/60 focus-visible:ring-offset-2 focus-visible:ring-offset-black`

Buttons:
- Primary (emerald): `bg-emerald-600/20 text-emerald-200 border border-emerald-700/40 hover:bg-emerald-600/30`
- Secondary (cyan): `bg-cyan-600/15 text-cyan-200 border border-cyan-700/40 hover:bg-cyan-600/25`
- Neutral: `bg-zinc-900/50 text-zinc-200 border border-zinc-800 hover:bg-zinc-900/80`

---

## Step G — “Hackery” detail without cringe
Optional (only if cheap):
- subtle panel glow via the emerald hairline shadow above
- no animated scanlines, no heavy effects
- avoid big neon gradients; keep it restrained

---

## Step H — Charts theme consistency
- backgrounds transparent
- axes/labels: zinc
- series colors:
  - bytes: emerald
  - ports: cyan
  - new dst: cyan (alt shade) or amber
  - asn: emerald/cyan
Keep the chart code minimal; don’t refactor chart libs.

---

## Step I — Apply across all pages
Update these pages to use shared partials and consistent cards:
- dashboard (/)
- anomalies (/anomalies)
- incidents (/incidents) if present
- remote host pages (per IP)
- remote hosts list (new hosts)
- search pages (hosts/connections/anomalies)
- devices edit page

---

## Step J — QA checklist
- 1080p and narrow viewport sanity
- no overflow bugs in tables
- links and buttons obvious on dark background
- focus rings visible with keyboard navigation
- no business logic changes
- run `bundle exec rspec`

Deliverables:
- cohesive emerald/cyan dark theme
- consistent spacing/alignment across UI
- shared partials reduce drift
- tables dense but readable
- charts visually match
- tests still passing
