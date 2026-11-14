# ZapDL Design Specification

Derived from the seven reference images supplied with the brief. Every token below is implemented in `lib/core/theme/`; widgets must read from the theme, never hardcode values.

## 1. Reference inventory

| # | Reference | What it contributes |
|---|-----------|---------------------|
| R1 | Persian dictionary app, mobile "Menu" (dark green) | Mobile shell: grouped rounded cards, tinted icon tiles, floating pill bottom navigation, RTL layout, hero card |
| R2 / R6 | IDM redesign (dark, desktop; R6 adds context menu + popups) | Desktop shell: collapsible category sidebar, icon+label toolbar, data table with gradient progress, disk gauge card, status bar, context menu |
| R3 | "DownloadZone" browser popup | Compact download item: file icon, percent, pause/close, chip row (size / time / speed), failed-state strikethrough + retry |
| R4 | "Dunludin" dashboard (light, blue) | Light theme and dashboard: analytics bar chart, limit gauge, queue rows, file-type tiles |
| R5 | "Paperpillar" dashboard UI kit (light, sage) | Stat cards with delta chips, icon rail, donut chart, hatched highlight bar, very soft surfaces |
| R7 | "pixidl" (dark, minimal, orange) | Desktop sidebar with count badges, tabs with counts, empty state, bottom status bar, top "paste URL" field |

### Dominant direction
Five of seven references are **dark-first, rounded, layered-surface interfaces** where one accent color carries all emphasis (R1 lime, R2 teal-to-purple, R3 green/blue, R7 orange). The two light references (R4, R5) use the same structure with soft tinted backgrounds. ZapDL therefore adopts:

- Dark is the hero theme; light is a faithful inversion with tinted (not pure white) backgrounds, as in R4/R5.
- One accent color drives selection, primary actions, progress and active navigation. Accent is user-switchable (brief section 5).
- Information density is medium-high on desktop (R2, R7), medium on mobile (R1).
- Inconsistencies resolved: R2's teal-to-purple gradient is *not* copied as a fixed brand; the progress gradient is derived from the active accent (accent to a lighter tint of the same hue). R3's magenta wordmark and R7's orange are treated as per-product branding, not as palette.

## 2. Layout and navigation

**Mobile (width < 600)** — from R1
- Large left/right-aligned screen title (RTL-aware) at top, 28-32 sp, bold.
- Content in grouped cards separated by 12-16 dp.
- **Floating pill bottom nav**: container radius 32, 1 px outline border, inset 16 dp from the screen edges, 8 dp from bottom. Active item is a filled accent pill containing icon + label; inactive items are icon + label in muted text. Tabs: Downloads, Search/Add, Categories, Stats, Settings.
- Subtle top-of-screen radial glow tinted with the accent (R1 green glow), 6-10 percent opacity.

**Desktop (width >= 900)** — from R2, R7
- Left sidebar ~240 dp: app mark + name, primary views with count badges (R7), collapsible category tree (R2: All Downloads > Music, Compressed, Videos, Programs, Documents, APKs, Images; Unfinished / Finished groups), queues section, bottom group (Settings, Updates, About).
- Selected sidebar row: accent-tinted fill (accent at ~18 percent), accent text/icon, radius 12 (R7).
- Top bar: global search + prominent "Add URL / paste" field (R2, R7) and window controls.
- Toolbar (R2): icon-over-label buttons: Resume, Stop, Stop All | Delete, Options, Queues, Scheduler, Share. Primary "Add URL" pill with accent icon button.
- Main area: sortable table (Name, Size, Status, Time left, Last modified) with leading checkbox and per-row category icon + sub-label (R2).
- Bottom status bar (R2, R7): selection control, active count, speed limit state, live down/up speed.
- Right-click context menu (R6): Open, Open With, Open Folder | Move/Rename, Redownload | Resume, Stop, Refresh address | Add to queue > | Properties.

**Tablet / medium (600-900)**: icon rail (R5) with tooltips instead of full sidebar; table collapses to card rows.

**Dashboard (all sizes, reflowed)** — from R4, R5
- Stat cards row: Active, Queued, Completed, Failed, Total speed (R5 stat card: title, large value, delta chip).
- Analytics card with weekly bar chart; today's bar highlighted with accent (R4) / hatched pattern (R5).
- Limits/usage card with arc gauge (R4) and storage gauge (R2 Disk Space).
- Queue list card with Pause All / Resume All (R4).
- File-type tiles with counts (R4): Documents, Video, Image, Archives, ...

## 3. Tokens

### Color roles (dark default)
| Role | Dark | Light |
|------|------|-------|
| background | `#0E0F12` (R7 near-black, tinted by accent 3%) | `#F3F6FB` (R4/R5 tinted) |
| surface (cards) | `#17191D` | `#FFFFFF` |
| surfaceRaised (rows, hover, inputs) | `#1E2126` | `#EEF2F8` |
| outline | `#2A2D33` | `#DDE3EC` |
| text | `#F2F4F7` | `#14181F` |
| textMuted | `#9AA1AD` | `#5B6472` |
| accent | user palette 500 | same |
| accentContainer (selected rows, icon tiles) | accent at 16-18% over surface | palette 50 |
| success | `#2EC27E` / `#12945A` | |
| warning | `#F5B93B` / `#B7791F` | |
| error | `#F0616D` / `#C0343F` | |

Semantic colors (success/warning/error) are fixed and independent of accent, as required.

### Shape
| Element | Radius |
|---------|--------|
| Grouped cards (R1) | 28 mobile / 20 desktop (R4) |
| Icon tiles (R1) | 16 |
| Buttons, chips (R3 pills) | full (stadium) |
| Inputs | 14 |
| Table row selected highlight (R2) | 14 |
| Context menu / popover | 14 |
| Window | 20 |

### Elevation
Dark: no drop shadows; separation by surface tone + 1 px outline (R1, R2, R7). Light: very soft shadow `0 8 24 rgba(20,24,31,0.06)` (R4, R5). Popovers/menus: both modes get a 1 px outline plus soft shadow.

### Spacing
4-pt scale: 4, 8, 12, 16, 20, 24, 32. Card padding 16-20. List row height 56 (mobile) / 52 (desktop table). Toolbar height 72. Sidebar item height 40.

### Typography
Sans-serif geometric-humanist (reference uses Inter-like, R7). Default: **Inter** for Latin/Cyrillic; platform fallbacks for CJK; **Vazirmatn** for Persian/Arabic (matches R1's rounded Persian weight). Scale: title 28/700, section 18/600, body 14/400-500, caption 12/400 muted, numeric speed/percent uses tabular figures.

### Iconography
Outline icons, 1.5-2 px stroke, rounded caps (all references). In R1, icons sit in 48-56 dp rounded tiles tinted by function; ZapDL tints tiles with accent or semantic color, not arbitrary hues, to stay consistent under theme switching. Directional icons (chevrons, back, play/skip) mirror in RTL.

### Progress
- Bar: 6 dp tall, fully rounded, track = outline color; fill = linear gradient accent-500 to accent-300 (R2/R3). Paused: fill uses textMuted. Failed: error. Complete: success.
- Percentage text color follows status (R3: warm/yellow for active is optional; ZapDL uses accent).
- Circular/arc gauges (R2, R4): 270-degree arc, round caps, accent gradient.

## 4. Components

**Download item (desktop table row, R2)** checkbox | category icon + name + category sub-label | size | status (text or progress bar with percent) | time left | modified date. Row hover: surfaceRaised; selected: accentContainer.

**Download item (mobile card, R3 + R4)**
```
[file icon] Name.ext                 32%   [pause] [x]
[=========progress bar=========-------]
(size chip)      (time chip)      (speed chip, accent filled)
```
States: downloading (as above), paused (muted bar, resume icon), completed (folder + x actions, no bar), failed (strikethrough name, retry icon, error text), queued (clock icon).

**Chips (R3)**: stadium, 1 px outline, 12 sp; the speed chip is accent-filled with white text.

**Empty state (R7)**: 56 dp accent-tinted rounded tile with icon, bold headline, muted one-liner, primary pill button.

**Buttons**: primary = accent fill, white text, stadium (R7 "Add a download"); secondary = surfaceRaised fill; destructive = error tint. Icon+label toolbar buttons are borderless (R2).

**Tabs with counts (R7)**: underline indicator in accent, count in muted small text.

**Dialogs / sheets**: mobile uses bottom sheets with top radius 28 and drag handle; desktop uses centered dialogs radius 20 (R6 popup card). Add-URL flow: field + detected name/size/destination + confirm.

**Gauge cards (R2 Disk Space, R4)**: card with title, "..." menu, arc gauge, big value, caption, full-width action button.

## 5. RTL (from R1)
R1 is a genuine RTL layout: titles and icon tiles anchor right, chevrons point left, trailing value ("Persian") sits on the left, bottom nav order is reversed. Implementation rule: use only `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, and mirror directional icons; no `left`/`right` literals.

## 6. States
- Loading: shimmer on surfaceRaised blocks matching row geometry.
- Error: inline error-tinted banner in the row plus Retry (R3).
- Success: brief check state then folder action.
- Offline: persistent muted banner above the list.

## 7. Responsive breakpoints
Compact < 600 (R1 shell), Medium 600-899 (icon rail, R5), Expanded >= 900 (full sidebar + table, R2/R7), Large >= 1200 (adds right-hand dashboard column, R4).

## 8. What is deliberately not copied
- IDM branding, the cartoon disk-health emoji, "Special Offer" / premium upsell cards, and the DownloadZone/Dunludin/pixidl/Paperpillar names or logos.
- R7's torrent/browser-extension entries (out of scope for the initial release).
- Fixed teal-purple gradient (replaced by accent-derived gradient).
