# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Buyers in Israel** who want one specific handmade piece that does not exist yet: a wallet with their father's initials, four mugs with a wedding date, a dining table that fits their corner. They come from a phone, usually with a gift and a date in mind.
- **Makers**: individual craftspeople and small studios (wood, leather, ceramics, jewellery, metal) who work by commission and want serious requests, not haggling.
- **The owner / admin**, who approves new makers by hand and writes the rejection message personally.

## Product Purpose

בהזמנה ("made to order") turns a buyer's description into offers from real makers. The buyer writes a request in their own words, picks one or more crafts (or "other"), sets a date and never a budget. Makers reply with a price, a time and a note, and each offer is a conversation. The buyer talks with them and then chooses one. Success: a buyer holds a piece that was made for them by someone whose name they know.

## Positioning

Not a shop of finished goods. The piece starts as a conversation with a named maker, and the buyer sees it being made (workshop photos at each stage). Makers are approved by a person, not an algorithm.

## Operating Context

- Phone first, Hebrew, right-to-left. A proper desktop layout comes later.
- Order lifecycle: agreed in chat → 30% deposit held until delivery → in work (photos from the workshop) → final 70% → pickup or delivery → review.
- Today it is a clickable demo with fictional makers, requests and orders, published free on GitHub Pages. Everything must stay at ₪0.

## Capabilities and Constraints

Features that must keep working in every redesign:
- free-word search (Hebrew prefixes, plurals, synonyms), its empty state and the "לבקש" button
- request form: multi-select crafts + "אחר", no budget field
- offers as conversations, with the choose sheet
- chat that auto-scrolls; composer above the on-screen keyboard (visualViewport); tab bar hidden while typing
- maker profiles with tabs that land on their sections
- admin: approve, or reject with a message the owner writes
- hearts (saved), galleries, orders with stage tracking, buyer/maker role switch
- material filter on home without the page jumping

Technical: one static `index.html` with inline CSS/JS, images in `img/`, GSAP from cdnjs. User text always passes through `esc()`. Motion only under `prefers-reduced-motion: no-preference`. No horizontal scroll at 375px.

## Brand Commitments

Confirmed by the owner (28.10.2026, `behazmana-notes/owner-decisions.md`):
- **Logo:** a wordmark for "בהזמנה", drawn in code at ₪0. The owner picks one of three.
- **Colour:** no more cream-and-brass. A palette from the place and the materials: Jerusalem stone, Acre red clay, olive green, plus one signature colour that belongs only to בהזמנה.
- **Voice:** warm and personal, like a friend who knows the makers. Stories, names, "אנחנו".
- **Images:** no AI-generated images at all.
- Hebrew craft: gershayim (״), gender-correct labels per maker (f/m/studio).

*Inferred, to confirm with the owner:* three brand words "אישי, ידני, מקומי"; "we are not a shop of finished goods, and not a price auction".

## Evidence on Hand

- `img/`: free Unsplash photos (not of these makers). They stay until 2–3 real makers the owner knows photograph their work (guide: `behazmana-notes/photo-guide-for-makers.md`). They must never be captioned as a specific maker's own work in a live product.
- All makers, reviews, requests, prices and order counts are fictional demo data. No real testimonials, press or statistics exist; none may be invented as real.

## Product Principles

1. **A person, not a catalogue.** Every screen leads to a named maker and a conversation.
2. **Show the making.** The process (sketch, workshop, finished piece) is the proof, not stars or scores.
3. **The buyer's words first.** Requests are written in plain language; nothing asks for a budget.
4. **Local and specific.** Cities, materials and workshops are named; nothing is "from anywhere".

## Accessibility & Inclusion

Hebrew RTL throughout; text 13px minimum, body 16px; WCAG AA contrast; every control reachable by keyboard with a visible focus; reduced-motion respected.
