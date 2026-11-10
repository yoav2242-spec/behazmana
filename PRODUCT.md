# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Buyers in Israel** who want one specific handmade piece that does not exist yet: a wallet with their father's initials, four mugs with a wedding date, a dining table that fits their corner. They come from a phone, usually with a gift and a date in mind.
- **Makers**: individual craftspeople and small studios (wood, leather, ceramics, jewellery, metal) who work by commission and want serious requests, not haggling.
- **The owner / admin**, who approves new makers by hand and writes the rejection message personally.

## Product Purpose

בהזמנה ("made to order") turns a buyer's description into a conversation with a real maker. The buyer writes a request in their own words, picks one or more crafts (or "other"), sets a date and never a budget, and leaves an email or phone. The owner reads each request and passes it by hand to approved makers who fit it; buyer and maker then talk directly. Success: a buyer holds a piece that was made for them by someone whose name they know.

## Positioning

Not a shop of finished goods. The piece starts as a conversation with a named maker, and the buyer sees it being made (workshop photos at each stage). Makers are approved by a person, not an algorithm.

## Operating Context

- Phone first, Hebrew, right-to-left. A proper desktop layout comes later.
- Payments: no money goes through the site. Buyer and maker agree on price, time and payment between themselves (for example bit or a bank transfer). The site holds no deposits and takes no commission; no copy may suggest otherwise.
- Real data only, starting from zero: makers appear only after the owner approved them by hand (Supabase `public_makers`). There are no invented makers, works, reviews, orders or numbers anywhere. Published free on GitHub Pages; everything must stay at ₪0.

## Capabilities and Constraints

Features that must keep working in every redesign:
- free-word search over the makers who joined (Hebrew prefixes, plurals, craft words, one-letter typos), its empty state and the "לבקש" button
- request form: multi-select crafts + "אחר", no budget field, contact + consent; never says "sent" unless the row was saved
- "שלי": the requests sent from this device (titles and dates, localStorage only)
- join form (portrait + work photos, shrunk in the browser); arriving by `#join` is a gate until the form is sent
- direct contact: a maker's phone is shown (WhatsApp and call buttons on cards and profiles) only if the maker chose that at signup (`phone_public`, read through `public_makers.contact_phone`); emails are never shown; there is no messaging through the site
- real maker list and profiles, with empty states for zero makers
- admin at `#admin`: approve, or reject with a note the owner writes; requests with mailto routing; 200 rows per page
- the phone's back button follows the in-app trail (History API) and closes sheets first; tab bar hidden while typing

Technical: one static `index.html` with inline CSS/JS, images in `img/`, GSAP from cdnjs (with SRI), a CSP meta tag. User and database text always passes through `esc()`. Motion only under `prefers-reduced-motion: no-preference`. No horizontal scroll at 320px.

## Brand Commitments

Confirmed by the owner (28.10.2026, `behazmana-notes/owner-decisions.md`):
- **Logo:** a wordmark for "בהזמנה", drawn in code at ₪0. The owner picks one of three.
- **Colour:** no more cream-and-brass. A palette from the place and the materials: Jerusalem stone, Acre red clay, olive green, plus one signature colour that belongs only to בהזמנה.
- **Voice:** warm and personal, like a friend who knows the makers. Stories, names, "אנחנו".
- **Images:** no AI-generated images at all.
- Hebrew craft: gershayim (״), gender-correct labels per maker (f/m/studio).

*Inferred, to confirm with the owner:* three brand words "אישי, ידני, מקומי"; "we are not a shop of finished goods, and not a price auction".

## Evidence on Hand

- `img/`: free Unsplash photos used only as atmosphere (the home hero). They are never shown as a maker's own work. Makers' photos come only from their own signup.
- No testimonials, press, reviews or statistics exist yet; none may be invented.

## Product Principles

1. **A person, not a catalogue.** Every screen leads to a request or to a real, named maker.
2. **Show the making.** The maker's own workshop photos are the proof, not stars or scores.
3. **The buyer's words first.** Requests are written in plain language; nothing asks for a budget.
4. **Local and specific.** Cities, materials and workshops are named; nothing is "from anywhere".

## Accessibility & Inclusion

Hebrew RTL throughout; text 13px minimum, body 16px; WCAG AA contrast; every control reachable by keyboard with a visible focus; reduced-motion respected.
