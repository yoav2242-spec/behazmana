# Design

*Written from the built site (impeccable `document`), 28.10.2026. Source of truth: the CSS tokens at the top of `index.html`.*

## The idea

**On this page, the workshop order slip (פתק ההזמנה) becomes the stationery the whole app is made of.**
The name בהזמנה is what is written on the slip a maker attaches to a commission: name, what, size, date, a stamp. Every screen is a piece of that slip. Direction dealt by `design-taste-frontend`: "The page is the object" (seed 1738291765). Phone first; a proper desktop layout comes later.

## Colour (place and materials, plus one colour only Be'hazmana owns)

| Token | Hex | Role |
|---|---|---|
| `--ground` | `#e4ded3` | Jerusalem stone in shade: the page |
| `--paper` | `#f2f1ee` | stone in sun: slips, fields, sheets |
| `--tone` | `#d3ccbe` | one step darker: resting buttons, chips, photo mats |
| `--ink` | `#1f2218` | olive-black: all running text (12:1 on ground) |
| `--muted` | `#55554a` | secondary notes (5.6:1 on ground, 6.8:1 on paper) |
| `--olive` | `#3b4630` | the one dark field: top bar, tab bar, the story, featured maker |
| `--clay` | `#9c4128` | Acre red clay: hearts, warnings, the closing "reply card" field |
| **`--stamp`** | **`#2443a0`** | **signature: stamp ink. Primary actions, stamps, the logo. Nowhere else.** |

All text pairs pass 4.5:1 (axe-core: 0 violations on 15 screen states).

## Type

- **Display: Karantina 700** (Google Fonts, free): names and headlines only. Its digits read poorly (7 looks like 3), so **every number, price and date is set in the text face**.
- **Text: Miriam Libre 400/700**: everything else.
- **Exactly five sizes: 13 / 16 / 20 / 28 / 44 px.** Nothing under 13px. Body 16px / 1.55.

## Components

- **Square corners everywhere** (avatars and photos included). No resting shadows, no gradients, no hairlines or outlined boxes: surfaces separate by a step in tone (ground → paper → tone).
- **Slip**: paper-coloured block with a drawn zig-zag tear edge (`.zig`, SVG strip, not clip-path). Used for the hero card and the order story.
- **Stamp**: small stamp-blue label tilted −3°, one per stage of the order story.
- **Word wall**: materials as big words (`.word`), selected = ink fill.
- **Tab bar**: a plain olive bar at the foot, current tab = paper tab. Hidden while typing.
- **Makers** show orders and response time ("58 הזמנות · עונה תוך שעות"), never star scores.
- **Logo kit** (`logo/`): wordmark (Karantina outlines + slanted saddle-stitch in stamp blue), primary with tagline "עבודת יד · לפי הזמנה", slip mark "בה" for corners and favicons, app icon.

## Home, section by section (each a different shape)

1. **Card over a dim room**: photo + one paper slip with logo, headline, sentence, one button.
2. **Search door** (opens the search screen).
3. **Word wall** of materials (filters the works below without moving the page).
4. **Works grid**: two columns, every fifth full-bleed.
5. **One maker, told properly** (Yossi from Acre) + a plain list of five more.
6. **The order story** on olive: "הארנק של אבא של רון", five slips with stamps.
7. **Reply card** on clay, then the **back of the card** (footer).

## Motion

One move: the stamp that lands on each order-story stage as it scrolls into view (GSAP + ScrollTrigger, once, under `prefers-reduced-motion: no-preference` only). Everything else is visible from the first frame. Controls change colour on press and hover; nothing else moves.

## Photography

Current photos stay until real makers photograph their work (guide: `behazmana-notes/photo-guide-for-makers.md`): window light, one background, faces, hands, workshop. No AI images.
