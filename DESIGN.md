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
- **Exactly five sizes: 13 / 16 / 20 / 28 / 44 px** (written in rem, so they follow the reader's font size). Nothing under 13px. Body 16px / 1.55.

## Components

- **Square corners everywhere** (avatars and photos included). No resting shadows, no gradients, no hairlines or outlined boxes: surfaces separate by a step in tone (ground → paper → tone).
- **Slip**: paper-coloured block with a drawn zig-zag tear edge (`.zig`, SVG strip, not clip-path). Used for the hero card, "how it works" and the thank-you screens.
- **Stamp**: small stamp-blue label tilted −3°, one per line of "how it works" and on each thank-you.
- **Tab bar**: a plain olive bar at the foot (בית / יצירות / יוצרים / בקשה / אני; the label size is capped to a fifth of the bar so all five fit at 320px and at 200% text), current tab = paper tab. Hidden while typing and on the join screens.
- **Sheets**: a close button at the top, Escape and the phone's back button close them, focus stays inside.
- **Makers** show only what they wrote themselves (name, city, craft, story, photos). No scores, counts or response times.
- Forced-colours mode adds real borders to controls; text links have a 44px tap area.
- **Logo kit** (`logo/`): wordmark (Karantina outlines + slanted saddle-stitch in stamp blue), primary with tagline "עבודת יד · לפי הזמנה", slip mark "בה" for corners and favicons, app icon.

## Home, section by section (each a different shape)

1. **Card over a workshop photo**: photo (height `clamp(180px, 34vh, 320px)`, shorter on short phones) + one paper slip with logo, one honest headline, sentence, the "לכתוב בקשה" button and a "להצטרף" link.
2. **How it works**: one slip, three lines, a stamp on each (no numbers, no story).
3. **יוצרים שהצטרפו אלינו**: the real approved makers, or an empty state inviting the first ones to join.
4. **Reply card** on clay, then the **back of the card** (footer: contact, privacy, terms).

## Motion

Restrained, one easing everywhere (`--ease`, exponential ease-out), only `transform` and `opacity`, nothing that moves layout. All of it runs only under `prefers-reduced-motion: no-preference`; with reduce, every change is instant and everything is visible at once. Content is always visible without JS.

- **Screens**: 220-280 ms fade plus a 24 px slide in the reading direction (RTL: forward arrives from the left edge, back from the right). Built on View Transitions, so the old screen stays underneath until the new one covers it (no blank frame); a plain fade-in where unsupported. The gated join screen, the thank-you screens and replaced screens fade without a slide; tab switches fade and the tab bar's paper tab slides. Back restores the scroll position of the screen you return to.
- **The stamp**: lands on each "how it works" line once, the first time it scrolls into view (GSAP + ScrollTrigger; scale 1.35 to 1 with a slight turn, 280 ms).
- **Sheets**: the panel rises from the bottom (280 ms), the backdrop fades. Closing is instant.
- **Feedback**: buttons dip 1px and darken on press (100 ms). The hero photo settles once (scale 1.04 to 1, 1.2 s).
- **Makers**: cards fade-rise 8 px once as they enter the viewport, 40 ms apart (6 at most per batch). Shown anyway if the observer is missing or silent. Search results do not animate.

## Shop and workspaces

- **Piece card**: photo (4:5, square corners), title, price as ₪1,200 or "מחיר בפנייה", maker; a sold piece is muted and carries an ink "נמכר" badge, and sinks after the available ones of each loaded page. Two columns; "עוד" pages by 24.
- **Piece detail**: a swipeable photo scroller (scroll-snap, counter), title and price in the display/text faces, the maker, WhatsApp / call / mail only when the maker opted in, and one plain line that no money goes through the site.
- **Status stamps** (`.st`): small tilted labels, always words (new, offered, not a fit, edited); never colour alone. Used on route cards, inbox cards and listing status.
- **Request card (maker inbox)**: a paper block whose head is the title, chips and dates; opening it shows the text, the buyer's contact as safe buttons, and the answers. **Route card (buyer)**: one paper row per maker with portrait, name, state stamp, offer and contact buttons.
- **Maker workspace**: three tabs (בקשות אליי / היצירות שלי / הפרופיל) in ink-on-tone, then the buyer links.

## Vision text

"מי אנחנו": a bottom sheet (from the "אני" screen and the footer of home). A title, one pull-quote in the display face on a ground-toned block, short paragraphs and a closing line. Built only from facts in PRODUCT.md and what exists now; the owner's own words can replace it later (see `עסק/מי-אנחנו.md`).

## Photography

The only stock photo is the hero (hands carving wood, no face), as atmosphere. Makers' photos come only from their own signup (guide: `behazmana-notes/photo-guide-for-makers.md`): window light, one background, faces, hands, workshop. No AI images.
