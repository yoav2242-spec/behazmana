-- =====================================================================
-- בהזמנה (Be'hazmana): database for makers who join and buyer requests.
-- Paste this WHOLE file into Supabase > SQL Editor > New query, and press Run.
-- It is safe to run again (it drops and recreates the policies).
--
-- This file matches what is live in the database (synced 10.11.2026).
-- For a NEW project: replace the owner's user id and email in is_owner() below with your own
-- (Authentication > Users shows the id; the email is the one in ADMIN_EMAIL inside index.html).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Who is the owner?
-- Every "admin" rule below asks this one function, so the owner lives in one place.
-- Both must match: the user id of the owner's account AND the email in the login token (JWT).
-- So even if someone managed to sign up with the same email, they would not be the owner.
-- ---------------------------------------------------------------------
create or replace function public.is_owner()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.uid() = 'eb1b1f1b-a6ad-42ba-81ae-582565094aa5'::uuid, false)
     and lower(coalesce(auth.jwt() ->> 'email','')) = 'behazmana1@gmail.com'
$$;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table if not exists public.makers (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  name        text not null,
  city        text not null,
  craft       text not null,
  story       text not null default '',
  email       text,
  phone       text,
  phone_public boolean not null default false,       -- the maker chose to show the phone on the site (call and WhatsApp buttons)
  email_public boolean not null default false,       -- the maker chose to show the email on the site (mail button)
  photos      text[] not null default '{}',          -- paths inside the storage bucket "maker-photos" (the work photos, up to 20)
  portrait    text,                                  -- path of the maker's own photo in the same bucket
  craft_other text,                                  -- the maker's own words when craft = 'other' (2-40 characters)
  status      text not null default 'pending',
  admin_note  text,                                  -- why a request was rejected (only the owner sees it)
  -- length checks: the public key is public, so these limit what a spammer can store
  constraint makers_status_ck  check (status in ('pending', 'approved', 'rejected')),
  constraint makers_craft_ck   check (craft in ('wood', 'leather', 'ceramic', 'jewelry', 'metal', 'other')),
  constraint makers_name_ck    check (char_length(btrim(name)) between 1 and 80),
  constraint makers_city_ck    check (char_length(btrim(city)) between 1 and 60),
  constraint makers_story_ck   check (char_length(story) <= 1000),
  constraint makers_email_ck   check (email is null or (char_length(email) between 5 and 120 and email like '%_@_%._%')),
  constraint makers_phone_ck   check (phone is null or char_length(phone) between 7 and 30),
  constraint makers_contact_ck check (email is not null or phone is not null),   -- at least one way to reach them
  constraint makers_photos_ck  check (coalesce(array_length(photos, 1), 0) <= 20),
  constraint makers_note_ck    check (admin_note is null or char_length(admin_note) <= 300)
);

create table if not exists public.requests (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  title       text not null,
  crafts      text[] not null default '{}',          -- craft keys: wood, leather, ceramic, jewelry, metal, other
  "text"      text not null default '',
  due         text not null default '',
  contact     text not null,                         -- the buyer's email or phone: private, only the owner reads it
  consent     boolean not null default false,
  status      text not null default 'new',
  constraint requests_status_ck  check (status in ('new', 'routed', 'closed')),
  constraint requests_title_ck   check (char_length(btrim(title)) between 1 and 120),
  constraint requests_text_ck    check (char_length("text") <= 2000),
  constraint requests_due_ck     check (char_length(due) <= 80),
  constraint requests_contact_ck check (char_length(btrim(contact)) between 5 and 120),
  constraint requests_crafts_ck  check (coalesce(array_length(crafts, 1), 0) <= 6)
);

-- For a database made with an older version of this file: add the portrait column and raise the photo limit to 20.
alter table public.makers add column if not exists portrait text;
alter table public.makers add column if not exists phone_public boolean not null default false;
alter table public.makers add column if not exists email_public boolean not null default false;
alter table public.makers drop constraint if exists makers_photos_ck;
alter table public.makers add constraint makers_photos_ck check (coalesce(array_length(photos, 1), 0) <= 20);

-- A craft that is not in the list: the maker picks "other" and writes it in craft_other.
alter table public.makers add column if not exists craft_other text;
alter table public.makers drop constraint if exists makers_craft_ck;
alter table public.makers add constraint makers_craft_ck
  check (craft in ('wood', 'leather', 'ceramic', 'jewelry', 'metal', 'other'));
alter table public.makers drop constraint if exists makers_craft_other_ck;
alter table public.makers add constraint makers_craft_other_ck
  check (craft_other is null or char_length(btrim(craft_other)) between 2 and 40);
alter table public.makers drop constraint if exists makers_craft_other_req_ck;
alter table public.makers add constraint makers_craft_other_req_ck
  check (craft <> 'other' or craft_other is not null);

create index if not exists makers_status_idx   on public.makers (status, created_at);
create index if not exists requests_status_idx on public.requests (status, created_at);

-- ---------------------------------------------------------------------
-- Row Level Security: ON for both tables. With RLS on and no matching policy, the answer is "no".
-- ---------------------------------------------------------------------
alter table public.makers   enable row level security;
alter table public.requests enable row level security;

-- Supabase hands new tables to everyone by default; take that away first, then give back only what is needed.
revoke all on public.makers   from anon, authenticated;
revoke all on public.requests from anon, authenticated;

-- Visitors (anon, the public key in index.html): may only ADD rows, and only these columns.
-- They cannot choose the id, the date or the admin note, and they cannot read anything back.
grant insert (name, city, craft, craft_other, story, email, phone, phone_public, email_public, portrait, photos, status) on public.makers   to anon, authenticated;
grant insert (title, crafts, "text", due, contact, consent, status)   on public.requests to anon, authenticated;

-- The owner (signed in by magic link): full access, but the policies below still check the email.
grant select, update, delete on public.makers   to authenticated;
grant select, update, delete on public.requests to authenticated;

-- ---- makers ----
drop policy if exists "anon adds a pending maker" on public.makers;
create policy "anon adds a pending maker" on public.makers
  for insert to anon, authenticated   -- authenticated too: the owner may be signed in on the phone she signs up from
  with check (status = 'pending');

drop policy if exists "owner reads makers" on public.makers;
create policy "owner reads makers" on public.makers
  for select to authenticated
  using (public.is_owner());

drop policy if exists "owner updates makers" on public.makers;
create policy "owner updates makers" on public.makers
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

drop policy if exists "owner deletes makers" on public.makers;   -- for "please delete my details" requests
create policy "owner deletes makers" on public.makers
  for delete to authenticated
  using (public.is_owner());

-- ---- requests ----
drop policy if exists "anon adds a request with consent" on public.requests;
create policy "anon adds a request with consent" on public.requests
  for insert to anon, authenticated
  with check (consent = true and status = 'new');

drop policy if exists "owner reads requests" on public.requests;
create policy "owner reads requests" on public.requests
  for select to authenticated
  using (public.is_owner());

drop policy if exists "owner updates requests" on public.requests;
create policy "owner updates requests" on public.requests
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

drop policy if exists "owner deletes requests" on public.requests;
create policy "owner deletes requests" on public.requests
  for delete to authenticated
  using (public.is_owner());

-- ---------------------------------------------------------------------
-- The public list of approved makers.
-- Visitors must NOT read the makers table (it holds emails and phones), so they read this VIEW instead.
-- It shows only approved rows and only the public columns: id, name, city, craft, story, photos, portrait,
-- craft_other (the maker's own words when craft = 'other'), contact_email (last column),
-- and contact_phone: the maker's phone ONLY when the maker chose to show it at signup (phone_public = true),
-- otherwise null. The email is in the view (contact_email) only when the maker chose to show it (email_public = true). A shown phone can be copied by anyone who sees it.
-- security_invoker = false means: "run as the view's owner", so the view can read makers even though
-- visitors cannot. That is safe and intended here, because the view itself decides which rows and
-- columns come out. (Supabase's security linter may mention this; it is expected for this view.)
-- ---------------------------------------------------------------------
create or replace view public.public_makers
  with (security_invoker = false)
as
  select id, name, city, craft, story, photos, portrait,
         case when phone_public then phone end as contact_phone,
         craft_other,
         case when email_public then email end as contact_email
  from public.makers
  where status = 'approved';

revoke all on public.public_makers from anon, authenticated;
grant select on public.public_makers to anon, authenticated;

-- ---------------------------------------------------------------------
-- Photos: a PUBLIC bucket "maker-photos" (photos of approved makers are shown on the site).
-- Limit 10 MB per file and image types only. The site uploads photos as they are (a photo over 10 MB is resized first).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('maker-photos', 'maker-photos', true, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 10485760, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- Visitors may upload (insert) images into this bucket, one folder level deep (the site uses a random folder per signup).
drop policy if exists "anon uploads maker photos" on storage.objects;
create policy "anon uploads maker photos" on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'maker-photos'
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
    and array_length(storage.foldername(name), 1) = 1
  );

-- Reading: a public bucket serves a photo to anyone who has its exact link, so no SELECT policy is needed.
-- On purpose there is none: without it, nobody can LIST the bucket and discover photos of makers who are not yet approved.

-- Only the owner may delete photos (for example when someone asks to be removed).
drop policy if exists "owner deletes maker photos" on storage.objects;
create policy "owner deletes maker photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'maker-photos' and public.is_owner());

-- ---------------------------------------------------------------------
-- Flood guard: the public key is public, so cap how many rows anyone can add in an hour, overall.
-- At most 30 new makers and 60 new requests per hour. Above that, the insert fails with
-- 'busy, try again later' (code P0001), and the site shows "יש עומס כרגע, נסו שוב בעוד כמה דקות".
-- ---------------------------------------------------------------------
create or replace function public.throttle_inserts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  if tg_table_name = 'makers' then
    select count(*) into n from public.makers where created_at > now() - interval '1 hour';
    if n >= 30 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  else
    select count(*) into n from public.requests where created_at > now() - interval '1 hour';
    if n >= 60 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  end if;
  return new;
end
$$;

drop trigger if exists makers_throttle on public.makers;
create trigger makers_throttle before insert on public.makers
  for each row execute function public.throttle_inserts();

drop trigger if exists requests_throttle on public.requests;
create trigger requests_throttle before insert on public.requests
  for each row execute function public.throttle_inserts();

-- Done. Quick check, run these two lines on their own: the first should say 2 rows (makers, requests) with rowsecurity = true.
--   select tablename, rowsecurity from pg_tables where schemaname = 'public' and tablename in ('makers', 'requests');
--   select * from public.public_makers;


-- =====================================================================
-- appended from 5-חנות-ויוצרים-בבסיס-הנתונים.sql
-- =====================================================================

-- =====================================================================
-- בהזמנה (Be'hazmana): חנות ציבורית + יוצרים מאושרים שמנהלים מוצרים משלהם.
-- Paste this WHOLE file into Supabase > SQL Editor > New query, and press Run.
-- Safe to run twice (drops and recreates policies/triggers; uses "if not exists" / "or replace").
-- Run AFTER 4-שינויים-בבסיס-הנתונים.sql (needs makers.craft_other, email_public, phone_public, portrait).
-- Supabase will warn about "destructive operation" because of the DROP POLICY / DROP TRIGGER lines:
-- they only remove old copies of the very objects recreated right below.
--
-- Prerequisites in the Supabase dashboard (NOT SQL, see the spec file):
--   Authentication > Providers > Email: "Confirm email" = ON (this is what makes the email in the login token trustworthy).
--   Authentication > URL Configuration: Site URL and Redirect URLs = only the site address.
--   Keep other sign-in providers (Google, phone, anonymous) OFF, so the only way into an account is a confirmed email.
--
-- THE RULE OF THIS FILE: anyone may create an auth account, but an account has NO power
-- unless its confirmed email equals the email of an APPROVED row in public.makers
-- (see my_maker_id()). is_owner() is NOT touched.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Which maker is signed in?   public.my_maker_id()
-- Returns the id of the ONE approved maker whose email equals the signed-in user's email, else null.
-- SECURITY DEFINER: it must read public.makers (and auth.users) which the caller cannot read.
-- It reveals nothing but the caller's OWN maker id.
-- Double check: the email in the login token (JWT) AND the current confirmed email of the auth user
-- (auth.users). The second check matters because a JWT keeps the OLD email until it expires (about an hour)
-- if the user changes the email of the account.
-- (Supabase "secure email change" also requires confirming the new address; keep that setting ON.)
-- ---------------------------------------------------------------------

-- Uniqueness: at most ONE approved maker per email, so my_maker_id() can never be ambiguous.
-- If this statement fails with "could not create unique index", two approved rows share an email. Find them with:
--   select lower(btrim(email)), count(*) from public.makers where status = 'approved' group by 1 having count(*) > 1;
-- (the table is empty today, so this should succeed.)
-- Side effect for the admin screen: approving a maker whose email already belongs to an approved maker fails with code 23505.
create unique index if not exists makers_approved_email_uq
  on public.makers (lower(btrim(email)))
  where status = 'approved' and email is not null;

create or replace function public.my_maker_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.makers m
  where m.status = 'approved'
    and m.email is not null
    and lower(btrim(m.email)) = lower(btrim(coalesce(auth.jwt() ->> 'email', '')))
    and exists (
      select 1 from auth.users u
      where u.id = auth.uid()
        and u.email_confirmed_at is not null
        and lower(btrim(coalesce(u.email, ''))) = lower(btrim(m.email))
    )
  limit 1
$$;

revoke all on function public.my_maker_id() from public, anon;
grant execute on function public.my_maker_id() to authenticated;

-- ---------------------------------------------------------------------
-- 2. The signed-in user's own maker row(s): view public.my_maker
-- Filtered by the email in the login token, any status (so a pending/rejected maker sees the status).
-- NO email, NO phone, NO admin_note. A visitor (anon) gets nothing: no grant.
-- security_invoker = false: runs as the view owner so it can read makers; the WHERE decides who sees what.
-- With no signed-in user, auth.jwt() is empty, the comparison is null, and zero rows come out.
-- ---------------------------------------------------------------------
create or replace view public.my_maker
  with (security_invoker = false)
as
  select id, name, city, craft, craft_other, story, photos, portrait,
         phone_public, email_public, status, created_at
  from public.makers
  where email is not null
    and lower(btrim(email)) = lower(btrim(coalesce(auth.jwt() ->> 'email', '')));

revoke all on public.my_maker from anon, authenticated;
grant select on public.my_maker to authenticated;

-- ---------------------------------------------------------------------
-- 3. Table public.listings
-- ---------------------------------------------------------------------

-- Photo paths: a listing's photos must live in ITS OWN MAKER's folder and have the exact shape
--   <maker_id>/<uuid>-<n>.<jpg|jpeg|png|webp>        (n = one digit, 0..9; lower case only)
-- This stops a maker from pointing a listing at someone else's files, or at any other URL.
-- The function is immutable (depends only on its arguments) so it can be used inside a CHECK.
create or replace function public.valid_listing_photos(p text[], mid uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_ndims(p) = 1 and cardinality(p) between 1 and 10, false)   -- 1..10 items, flat array (an empty array is NOT allowed)
     and not exists (
       select 1 from unnest(p) as x
       where x is null
          or char_length(x) > 200
          or x !~ ('^' || mid::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-9]\.(jpg|jpeg|png|webp)$')
     )
$$;

revoke all on function public.valid_listing_photos(text[], uuid) from public, anon;
grant execute on function public.valid_listing_photos(text[], uuid) to authenticated;

create table if not exists public.listings (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  maker_id     uuid not null references public.makers(id) on delete cascade,   -- deleting a maker deletes the listings (the PHOTO FILES stay: see storage notes below)
  title        text not null,
  description  text not null default '',
  price_ils    integer,                                   -- shekels. null = "מחיר בפנייה" (price on request)
  photos       text[] not null,                           -- paths inside the bucket "listing-photos"
  availability text not null default 'available',
  status       text not null default 'pending',           -- pending -> the owner approves/rejects; hidden = the owner took it down
  admin_note   text,                                      -- the owner's reason for a rejection. NOTE: the maker can read this on their OWN listing (it is the reason shown to them)
  constraint listings_title_ck  check (char_length(btrim(title)) between 2 and 80),
  constraint listings_desc_ck   check (char_length(description) <= 1500),
  constraint listings_price_ck  check (price_ils is null or price_ils between 0 and 1000000),
  constraint listings_photos_ck check (public.valid_listing_photos(photos, maker_id)),
  constraint listings_avail_ck  check (availability in ('available', 'sold')),
  constraint listings_status_ck check (status in ('pending', 'approved', 'rejected', 'hidden')),
  constraint listings_note_ck   check (admin_note is null or char_length(admin_note) <= 300)
);

create index if not exists listings_status_idx  on public.listings (status, created_at desc);
create index if not exists listings_maker_idx   on public.listings (maker_id);

alter table public.listings enable row level security;

-- Supabase hands new tables to everyone by default; take it away first, then give back only what is needed.
revoke all on public.listings from anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Grants + policies on listings
-- anon (visitors): NOTHING on the table. They read the shop through the view public_listings.
-- authenticated: the owner AND approved makers AND useless accounts all share this role, so
--   the policies decide (is_owner() / my_maker_id()), and the triggers below protect status/admin_note/maker_id.
-- ---------------------------------------------------------------------
grant select, delete on public.listings to authenticated;
-- A maker may INSERT only these columns. NOT id, created_at, updated_at, status, admin_note.
-- (status and admin_note therefore always get their defaults: 'pending' and null.)
grant insert (maker_id, title, description, price_ils, photos, availability) on public.listings to authenticated;
-- UPDATE columns: status and admin_note are for the owner. They are in the grant only because the owner
-- is also "authenticated" (grants are per role, not per person); the trigger listings_guard blocks everyone else.
grant update (title, description, price_ils, photos, availability, status, admin_note) on public.listings to authenticated;

-- ---- owner: everything (read all, update, delete) ----
drop policy if exists "owner reads listings" on public.listings;
create policy "owner reads listings" on public.listings
  for select to authenticated
  using (public.is_owner());

drop policy if exists "owner updates listings" on public.listings;
create policy "owner updates listings" on public.listings
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

drop policy if exists "owner deletes listings" on public.listings;
create policy "owner deletes listings" on public.listings
  for delete to authenticated
  using (public.is_owner());

-- ---- approved maker: own listings only. my_maker_id() is null for everyone else, so "= null" is never true ----
drop policy if exists "maker reads own listings" on public.listings;
create policy "maker reads own listings" on public.listings
  for select to authenticated
  using (maker_id = public.my_maker_id());

drop policy if exists "maker adds own pending listing" on public.listings;
create policy "maker adds own pending listing" on public.listings
  for insert to authenticated
  with check (
    maker_id = public.my_maker_id()
    and status = 'pending'
    and availability = 'available'
    and admin_note is null
  );

drop policy if exists "maker updates own listings" on public.listings;
create policy "maker updates own listings" on public.listings
  for update to authenticated
  using (maker_id = public.my_maker_id())
  with check (maker_id = public.my_maker_id());

drop policy if exists "maker deletes own listings" on public.listings;
create policy "maker deletes own listings" on public.listings
  for delete to authenticated
  using (maker_id = public.my_maker_id());

-- ---------------------------------------------------------------------
-- Guard triggers (run as the caller, not SECURITY DEFINER; search_path is empty).
-- "Trusted" callers are the database admin roles (SQL editor = postgres, service_role): the guard does not
-- apply to them, so the owner can still fix data by hand in the SQL editor. API users are always
-- "authenticated" or "anon": a person cannot change their database role through the API.
-- For API callers who are not the owner:
--   INSERT: must be for their own maker_id, status 'pending', availability 'available', no admin_note.
--   UPDATE: status, admin_note, maker_id (and id, created_at) can never change;
--           changing title/description/price_ils/photos puts the listing back to 'pending'
--           (an approved listing cannot be changed silently); changing only availability keeps the status.
-- Error: errcode 42501 ("not allowed"), which the API returns as HTTP 403.
-- ---------------------------------------------------------------------
create or replace function public.listings_guard_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if current_user not in ('postgres', 'supabase_admin', 'service_role') and not public.is_owner() then
    if new.status is distinct from 'pending'
       or new.availability is distinct from 'available'
       or new.admin_note is not null
       or new.maker_id is distinct from public.my_maker_id() then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

create or replace function public.listings_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if current_user not in ('postgres', 'supabase_admin', 'service_role') and not public.is_owner() then
    if new.id is distinct from old.id
       or new.created_at is distinct from old.created_at
       or new.maker_id is distinct from old.maker_id
       or new.status is distinct from old.status
       or new.admin_note is distinct from old.admin_note then
      raise exception 'not allowed' using errcode = '42501';
    end if;
    if new.title is distinct from old.title
       or new.description is distinct from old.description
       or new.price_ils is distinct from old.price_ils
       or new.photos is distinct from old.photos then
      new.status := 'pending';   -- content changed: the owner must approve again (also lifts a "hidden"/"rejected" listing back to review, never to public)
    end if;
  end if;
  return new;
end
$$;

revoke all on function public.listings_guard_insert() from public, anon;
revoke all on function public.listings_guard()        from public, anon;

drop trigger if exists listings_guard_insert on public.listings;
create trigger listings_guard_insert before insert on public.listings
  for each row execute function public.listings_guard_insert();   -- fires BEFORE listings_throttle (alphabetical order)

drop trigger if exists listings_guard on public.listings;
create trigger listings_guard before update on public.listings
  for each row execute function public.listings_guard();

-- ---------------------------------------------------------------------
-- 5. The public shop: view public.public_listings
-- Approved listings of APPROVED makers only. Contact details only if the maker opted in
-- (phone_public / email_public). No admin_note, no status, no updated_at, no maker email/phone otherwise.
-- security_invoker = false: runs as the view owner (visitors cannot read the tables); the WHERE and the
-- column list below are the whole public surface. Ordering is done by the client (created_at desc).
-- ---------------------------------------------------------------------
create or replace view public.public_listings
  with (security_invoker = false)
as
  select l.id, l.title, l.description, l.price_ils, l.photos, l.availability, l.created_at,
         l.maker_id,
         m.name        as maker_name,
         m.city        as maker_city,
         m.craft       as maker_craft,
         m.craft_other as maker_craft_other,
         m.portrait    as maker_portrait,
         case when m.phone_public then m.phone end as contact_phone,
         case when m.email_public then m.email end as contact_email
  from public.listings l
  join public.makers   m on m.id = l.maker_id
  where l.status = 'approved'
    and m.status = 'approved';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Storage: PUBLIC bucket "listing-photos"
-- Path shape (enforced by the policy AND, for listing rows, by listings_photos_ck):
--   <maker_id>/<uuid>-<n>.<ext>      ext = jpg | jpeg | png | webp (lower case), n = one digit 0..9
--   <uuid> is generated by the browser (crypto.randomUUID()) once per listing being created, so the
--   files of one listing share it. It is NOT the listing id (the listing id is created by the database
--   afterwards; makers cannot choose ids).
-- A public bucket serves a file to anyone who has the exact link. So files are visible by link even while
-- the listing is still pending; links contain two random-looking parts and cannot be listed by visitors.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 10485760, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- UPLOAD: an approved maker, into their own folder only, exact file-name shape. No anon.
-- If my_maker_id() is null the whole expression is null = denied.
drop policy if exists "maker uploads listing photos" on storage.objects;
create policy "maker uploads listing photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and public.my_maker_id() is not null
    and name ~ ('^' || public.my_maker_id()::text
                || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-9]\.(jpg|jpeg|png|webp)$')
  );

-- DELETE: a maker in their own folder, or the owner anywhere.
drop policy if exists "maker or owner deletes listing photos" on storage.objects;
create policy "maker or owner deletes listing photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and ( (storage.foldername(name))[1] = public.my_maker_id()::text
          or public.is_owner() )
  );

-- READ for authenticated, restricted to the own folder (owner: all).
-- Why this exists although the brief said "no select policy": the Storage API deletes with
-- "DELETE ... RETURNING", and Postgres then also requires a matching SELECT policy, otherwise a delete
-- silently removes nothing. This policy is NOT a hole: anon has no select policy at all (visitors cannot list),
-- and a maker can only list their OWN folder. Public links (download of an exact path) work without any policy.
drop policy if exists "maker or owner reads own listing photos" on storage.objects;
create policy "maker or owner reads own listing photos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'listing-photos'
    and ( (storage.foldername(name))[1] = public.my_maker_id()::text
          or public.is_owner() )
  );

-- NO update policy: nobody can overwrite or move a file (upload with upsert:false only).
-- ORPHANED PHOTOS (files with no listing): the client removes a listing's files when the maker deletes the listing
-- (delete the row first, then storage.remove(paths)); the owner can delete files from the dashboard or with
-- the same API call. A maker who uploads and then abandons the form leaves files behind.
-- A nightly cleanup (list the bucket, compare to listings.photos, delete the difference) needs the service key
-- from a server job: OUT OF SCOPE here. Deleting a maker/listing in SQL does NOT delete the files, and deleting
-- rows of storage.objects by SQL removes only the record, not the file: always delete files through the Storage API/dashboard.

-- ---------------------------------------------------------------------
-- 7. Flood guard for listings (the existing makers/requests throttles are untouched)
-- At most 20 new listings per maker per hour, and 100 per hour overall. Above that:
-- exception 'busy, try again later' with code P0001 (same as the existing throttle).
-- It counts a small LOG table, not the listings table, so deleting your listings does not reset your counter.
-- The log has RLS on and NO policies and no grants: only this SECURITY DEFINER function touches it.
-- ---------------------------------------------------------------------
create table if not exists public.listing_throttle_log (
  maker_id   uuid        not null,
  created_at timestamptz not null default now()
);
create index if not exists listing_throttle_log_at_idx    on public.listing_throttle_log (created_at);
create index if not exists listing_throttle_log_maker_idx on public.listing_throttle_log (maker_id, created_at);
alter table public.listing_throttle_log enable row level security;
revoke all on public.listing_throttle_log from anon, authenticated;

create or replace function public.throttle_listings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  perform pg_advisory_xact_lock(hashtext('behazmana.listings_throttle'));   -- one at a time: no race that lets a burst through
  delete from public.listing_throttle_log where created_at < now() - interval '1 day';
  select count(*) into n from public.listing_throttle_log
   where maker_id = new.maker_id and created_at > now() - interval '1 hour';
  if n >= 20 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  select count(*) into n from public.listing_throttle_log
   where created_at > now() - interval '1 hour';
  if n >= 100 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  insert into public.listing_throttle_log (maker_id) values (new.maker_id);
  return new;
end
$$;

revoke all on function public.throttle_listings() from public, anon, authenticated;

drop trigger if exists listings_throttle on public.listings;
create trigger listings_throttle before insert on public.listings
  for each row execute function public.throttle_listings();

-- =====================================================================
-- 8. VERIFICATION: read-only SELECTs. Run them one by one (or all; the editor shows the last result).
-- =====================================================================

-- 8.1 tables: both should have rowsecurity = true
select tablename, rowsecurity from pg_tables
 where schemaname = 'public' and tablename in ('listings', 'listing_throttle_log');

-- 8.2 views and functions exist
select table_name as view_name from information_schema.views
 where table_schema = 'public' and table_name in ('my_maker', 'public_listings');
select proname, prosecdef as security_definer, provolatile, proconfig
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('my_maker_id', 'valid_listing_photos', 'listings_guard', 'listings_guard_insert', 'throttle_listings', 'is_owner');

-- 8.3 view columns (public_listings: 15 columns, last is contact_email; my_maker: 12 columns, no email/phone/admin_note)
select table_name, ordinal_position, column_name from information_schema.columns
 where table_schema = 'public' and table_name in ('my_maker', 'public_listings')
 order by table_name, ordinal_position;

-- 8.4 indexes (look for makers_approved_email_uq and the listings indexes)
select tablename, indexname, indexdef from pg_indexes
 where schemaname = 'public' and indexname in ('makers_approved_email_uq', 'listings_status_idx', 'listings_maker_idx',
       'listing_throttle_log_at_idx', 'listing_throttle_log_maker_idx');

-- 8.5 policies on listings (expect 7: 3 owner + 4 maker)
select policyname, cmd, roles, qual, with_check from pg_policies
 where schemaname = 'public' and tablename = 'listings' order by cmd, policyname;

-- 8.6 triggers on listings (expect listings_guard (UPDATE), listings_guard_insert (INSERT), listings_throttle (INSERT))
select trigger_name, event_manipulation, action_timing, action_statement from information_schema.triggers
 where event_object_schema = 'public' and event_object_table = 'listings' order by trigger_name;

-- 8.7 table-level grants for anon/authenticated on listings and the views.
--     Expect: listings -> authenticated: SELECT, DELETE only (anon: nothing); my_maker -> authenticated SELECT only;
--     public_listings -> anon + authenticated SELECT only; listing_throttle_log -> nothing.
select grantee, table_name, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('listings', 'my_maker', 'public_listings', 'listing_throttle_log')
   and grantee in ('anon', 'authenticated')
 order by table_name, grantee, privilege_type;

-- 8.8 column-level grants on listings (expect INSERT: maker_id, title, description, price_ils, photos, availability;
--     UPDATE: title, description, price_ils, photos, availability, status, admin_note)
select grantee, privilege_type, column_name from information_schema.role_column_grants
 where table_schema = 'public' and table_name = 'listings' and grantee in ('anon', 'authenticated')
   and privilege_type in ('INSERT', 'UPDATE')
 order by privilege_type, grantee, column_name;

-- 8.9 who may run the functions (my_maker_id: authenticated = true, anon = false)
select has_function_privilege('anon',          'public.my_maker_id()', 'execute') as anon_can_run_my_maker_id,
       has_function_privilege('authenticated', 'public.my_maker_id()', 'execute') as authenticated_can_run_my_maker_id;

-- 8.10 the bucket
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'listing-photos';

-- 8.11 storage policies: expect exactly 3 for listing-photos (insert, delete, select), no anon, no update.
--      Also scan the whole list for any OTHER broad policy (for example "to public" without a bucket_id check) that would reach this bucket.
select policyname, cmd, roles, qual, with_check from pg_policies
 where schemaname = 'storage' and tablename = 'objects' order by policyname;

-- 8.12 no duplicate approved emails (must return 0 rows)
select lower(btrim(email)) as email, count(*) from public.makers
 where status = 'approved' and email is not null group by 1 having count(*) > 1;


-- =====================================================================
-- appended from 6-מעקב-בקשות-בבסיס-הנתונים.sql
-- =====================================================================

-- =====================================================================
-- בהזמנה (Be'hazmana): מעקב בקשות. הקונה חוזר ורואה מה קרה לבקשה, היוצרים מקבלים תיבת בקשות,
-- הבעלים מנתב בקשות ליוצרים מתאימים.
-- Paste this WHOLE file into Supabase > SQL Editor > New query, and press Run.
-- Safe to run twice (drops and recreates policies/triggers; "if not exists" / "or replace").
-- Run AFTER 5-חנות-ויוצרים-בבסיס-הנתונים.sql (needs is_owner(), my_maker_id(), makers, requests).
-- Supabase will warn about "destructive operation" because of the DROP POLICY / DROP TRIGGER / DROP CONSTRAINT lines:
-- they only remove old copies of the very objects recreated right below.
--
-- THE MODEL
--   * The buyer has NO account. The browser makes a random uuid (crypto.randomUUID()) = the buyer's TOKEN, sends it
--     with the request, and remembers it in localStorage. The token is a key: whoever holds it can see that ONE request's
--     status (rpc request_status) and close it (rpc close_request). Nobody can read tokens back (anon has no select).
--   * The owner creates "routes" (request_routes rows: this request -> this approved maker).
--   * An approved maker sees only the routes made to him/her (view my_inbox, incl. the buyer's contact) and answers each one
--     (seen / thinking / offered with note+price / declined).
--   * The buyer's contact (requests.contact) is NEVER returned by request_status. Only the owner and the routed makers see it.
--   * No chat, no payments, no email from the database.
-- is_owner() and my_maker_id() are NOT touched.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. requests: the buyer's token + "closed by the buyer" time
-- ---------------------------------------------------------------------
-- A volatile default makes Postgres give EVERY existing row its own random value, so old requests get a token too.
alter table public.requests add column if not exists token uuid not null default gen_random_uuid();
alter table public.requests add column if not exists closed_by_buyer_at timestamptz;

create unique index if not exists requests_token_uq on public.requests (token);

-- The token must look like crypto.randomUUID() (version 4, lower case). Stops "0000..." / hand-made weak tokens.
alter table public.requests drop constraint if exists requests_token_ck;
alter table public.requests add constraint requests_token_ck
  check (token::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

-- The client may now send its own token on insert. NOT closed_by_buyer_at, NOT id, NOT created_at.
-- (The existing insert grants and the policy "anon adds a request with consent": consent = true and status = 'new' stay as they are.)
grant insert (token) on public.requests to anon, authenticated;

-- Because anon cannot SELECT, the client must insert WITHOUT .select() (return=minimal), see the spec.
-- UPDATE on requests is still owner-only (policy "owner updates requests", unchanged): the token never lets anybody edit the row;
-- the two RPCs below are the only things a token holder can do.

-- ---------------------------------------------------------------------
-- 2. Table public.request_routes
-- ---------------------------------------------------------------------
create table if not exists public.request_routes (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  request_id      uuid not null references public.requests(id) on delete cascade,   -- deleting a request deletes its routes
  maker_id        uuid not null references public.makers(id)   on delete cascade,   -- deleting a maker deletes his/her routes
  status          text not null default 'sent',
  seen_at         timestamptz,                -- set by the trigger the first time status leaves 'sent'
  offer_note      text,
  offer_price_ils integer
);

alter table public.request_routes drop constraint if exists request_routes_status_ck;
alter table public.request_routes add constraint request_routes_status_ck
  check (status in ('sent', 'seen', 'thinking', 'offered', 'declined'));
alter table public.request_routes drop constraint if exists request_routes_note_ck;
alter table public.request_routes add constraint request_routes_note_ck
  check (offer_note is null or char_length(offer_note) <= 500);
alter table public.request_routes drop constraint if exists request_routes_price_ck;
alter table public.request_routes add constraint request_routes_price_ck
  check (offer_price_ils is null or offer_price_ils between 0 and 1000000);
-- note and price exist only on an offer
alter table public.request_routes drop constraint if exists request_routes_offer_ck;
alter table public.request_routes add constraint request_routes_offer_ck
  check (status = 'offered' or (offer_note is null and offer_price_ils is null));

-- One route per (request, maker). A duplicate insert fails with 23505 (index name request_routes_uq): "already routed".
create unique index if not exists request_routes_uq          on public.request_routes (request_id, maker_id);
create index        if not exists request_routes_maker_idx   on public.request_routes (maker_id, created_at desc);
create index        if not exists request_routes_request_idx on public.request_routes (request_id);

alter table public.request_routes enable row level security;

-- Supabase hands new tables to everyone by default; take it away first, then give back only what is needed.
revoke all on public.request_routes from anon, authenticated;

-- anon (visitors/buyers): NOTHING on the table (buyers use rpc request_status).
-- authenticated = the owner AND approved makers AND useless accounts; the policies decide.
grant select, delete on public.request_routes to authenticated;
-- INSERT: only the pair. status/seen_at/offer_* always take their defaults. (Only the owner passes the policy + guard.)
grant insert (request_id, maker_id) on public.request_routes to authenticated;
-- UPDATE: these columns only. request_id, maker_id, created_at, id can never be changed through the API.
-- seen_at is in the grant as asked, but the trigger IGNORES the value sent and computes it itself.
grant update (status, seen_at, offer_note, offer_price_ils) on public.request_routes to authenticated;

-- ---- owner: everything ----
drop policy if exists "owner reads routes" on public.request_routes;
create policy "owner reads routes" on public.request_routes
  for select to authenticated
  using (public.is_owner());

drop policy if exists "owner adds routes" on public.request_routes;
create policy "owner adds routes" on public.request_routes
  for insert to authenticated
  with check (public.is_owner());

drop policy if exists "owner updates routes" on public.request_routes;
create policy "owner updates routes" on public.request_routes
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

drop policy if exists "owner deletes routes" on public.request_routes;
create policy "owner deletes routes" on public.request_routes
  for delete to authenticated
  using (public.is_owner());

-- ---- approved maker: select and update only OWN routes; no insert, no delete ----
-- my_maker_id() is null for everyone who is not an approved maker, and "= null" is never true.
-- (select ...) makes Postgres evaluate it once per query instead of once per row.
drop policy if exists "maker reads own routes" on public.request_routes;
create policy "maker reads own routes" on public.request_routes
  for select to authenticated
  using (maker_id = (select public.my_maker_id()));

drop policy if exists "maker updates own routes" on public.request_routes;
create policy "maker updates own routes" on public.request_routes
  for update to authenticated
  using (maker_id = (select public.my_maker_id()))
  with check (maker_id = (select public.my_maker_id()));

-- ---------------------------------------------------------------------
-- 2b. Helper: is the request of one of MY routes closed?
-- A maker cannot read public.requests, but the update guard needs to know whether the buyer closed the request.
-- SECURITY DEFINER; answers only for a request that has a route to the CALLING maker (anyone else gets null).
-- ---------------------------------------------------------------------
create or replace function public.request_route_closed(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select r.status = 'closed'
  from public.requests r
  join public.request_routes rr on rr.request_id = r.id
  where r.id = p_request
    and rr.maker_id = public.my_maker_id()
  limit 1
$$;

revoke all on function public.request_route_closed(uuid) from public, anon, authenticated;
grant execute on function public.request_route_closed(uuid) to authenticated;   -- the guard trigger runs as the caller and calls it

-- ---------------------------------------------------------------------
-- 2c. Guard triggers (run as the caller, not SECURITY DEFINER; search_path is empty).
-- "Trusted" callers are the database admin roles (SQL editor = postgres, service_role): the guards do not apply to them.
-- API users are always "authenticated" or "anon" and cannot change their database role.
--
-- INSERT guard (request_routes_guard_insert): only the owner; the maker must be 'approved'; the request must exist and not be 'closed';
--   status must be 'sent' with no seen_at/offer. Errors: 42501 'not allowed', 22023 'maker not approved', 22023 'request not open'.
--
-- UPDATE guard (request_routes_guard), for API callers:
--   everyone (owner too): id, request_id, maker_id, created_at never change (42501 'not allowed');
--     updated_at is always set; seen_at is computed (null while 'sent'; otherwise the old value, or now() the first time it leaves 'sent'):
--     the value the client sends is ignored; an offer needs a note (22023 'offer note required'), and note/price are cleared
--     (set to null) whenever status is not 'offered'.
--   NOT the owner (a maker):
--     * if the buyer closed the request: 22023 'request closed' (nothing can change any more);
--     * status can only change along these allowed transitions (22023 'bad status change' otherwise), never back to 'sent':
--         sent     -> seen | thinking | offered | declined
--         seen     -> thinking | offered | declined
--         thinking -> offered | declined
--         offered  -> thinking | declined        (offered -> offered = editing the offer; going back to thinking/declined erases the offer)
--         declined -> thinking | offered         (the maker changed his/her mind)
--       never -> 'seen' except from 'sent' (so a stale screen cannot downgrade a 'thinking' route to 'seen');
--       the same status again is allowed (no change).
--   The owner may set any status (to fix a mistake). The buyer would see it, so use sparingly.
-- ---------------------------------------------------------------------
create or replace function public.request_routes_guard_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;
  if not public.is_owner() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if new.status is distinct from 'sent'
     or new.seen_at is not null
     or new.offer_note is not null
     or new.offer_price_ils is not null then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  -- the owner can read makers and requests through his policies, so these two checks work as the caller
  if not exists (select 1 from public.makers m where m.id = new.maker_id and m.status = 'approved') then
    raise exception 'maker not approved' using errcode = '22023';
  end if;
  if not exists (select 1 from public.requests r where r.id = new.request_id and r.status <> 'closed') then
    raise exception 'request not open' using errcode = '22023';
  end if;
  return new;
end
$$;

create or replace function public.request_routes_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare v_owner boolean;
begin
  new.updated_at := now();
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.request_id is distinct from old.request_id
     or new.maker_id is distinct from old.maker_id
     or new.created_at is distinct from old.created_at then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  v_owner := public.is_owner();

  if not v_owner then
    if coalesce(public.request_route_closed(old.request_id), false) then
      raise exception 'request closed' using errcode = '22023';
    end if;
    if new.status is distinct from old.status then
      if not (   (old.status = 'sent'     and new.status in ('seen', 'thinking', 'offered', 'declined'))
              or (old.status = 'seen'     and new.status in ('thinking', 'offered', 'declined'))
              or (old.status = 'thinking' and new.status in ('offered', 'declined'))
              or (old.status = 'offered'  and new.status in ('thinking', 'declined'))
              or (old.status = 'declined' and new.status in ('thinking', 'offered'))) then
        raise exception 'bad status change' using errcode = '22023';
      end if;
    end if;
  end if;

  -- offer fields only on an offer
  if new.status = 'offered' then
    new.offer_note := btrim(coalesce(new.offer_note, ''));
    if new.offer_note = '' then
      raise exception 'offer note required' using errcode = '22023';
    end if;
  else
    new.offer_note := null;
    new.offer_price_ils := null;
  end if;

  -- seen_at is computed, never taken from the client
  if new.status = 'sent' then
    new.seen_at := null;
  else
    new.seen_at := coalesce(old.seen_at, now());
  end if;
  return new;
end
$$;

-- AFTER INSERT: the first route moves the request from 'new' to 'routed'. SECURITY DEFINER because the caller
-- (the owner) may update requests, but this must also work whoever inserts (SQL editor, service role).
create or replace function public.request_routes_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.requests set status = 'routed' where id = new.request_id and status = 'new';
  return null;
end
$$;

revoke all on function public.request_routes_guard_insert() from public, anon, authenticated;
revoke all on function public.request_routes_guard()        from public, anon, authenticated;
revoke all on function public.request_routes_after_insert() from public, anon, authenticated;

drop trigger if exists request_routes_guard_insert on public.request_routes;
create trigger request_routes_guard_insert before insert on public.request_routes
  for each row execute function public.request_routes_guard_insert();

drop trigger if exists request_routes_guard on public.request_routes;
create trigger request_routes_guard before update on public.request_routes
  for each row execute function public.request_routes_guard();

drop trigger if exists request_routes_after_insert on public.request_routes;
create trigger request_routes_after_insert after insert on public.request_routes
  for each row execute function public.request_routes_after_insert();

-- ---------------------------------------------------------------------
-- 3. The maker's inbox: view public.my_inbox
-- Only the signed-in APPROVED maker's own routes (route.maker_id = my_maker_id()). For anon, for a signed-in non-maker,
-- for a rejected/pending maker: my_maker_id() is null, the comparison is null, zero rows. anon has no grant at all.
-- Shows the request details INCLUDING the buyer's contact (the buyer was told at submit that the request is passed on),
-- but NEVER the token, and NOT the other makers the request went to.
-- When the buyer closed the request, request_status = 'closed' and contact is null (the deal is over; less personal data out there).
-- security_invoker = false: runs as the view owner (makers cannot read requests); the WHERE is the whole access rule.
-- ---------------------------------------------------------------------
drop view if exists public.my_inbox;
create view public.my_inbox
  with (security_invoker = false)
as
  select rr.id              as route_id,
         rr.request_id      as request_id,
         rr.status          as route_status,
         rr.seen_at         as seen_at,
         rr.offer_note      as offer_note,
         rr.offer_price_ils as offer_price_ils,
         rr.created_at      as routed_at,
         r.title            as title,
         r.crafts           as crafts,
         r."text"           as "text",
         r.due              as due,
         case when r.status = 'closed' then null else r.contact end as contact,
         r.created_at       as created_at,
         r.status           as request_status
  from public.request_routes rr
  join public.requests r on r.id = rr.request_id
  where rr.maker_id = (select public.my_maker_id());

revoke all on public.my_inbox from public, anon, authenticated;
grant select on public.my_inbox to authenticated;

-- ---------------------------------------------------------------------
-- 4. Token rate limiter + RPC public.request_status(p_token)
--
-- WHAT POSTGRES CAN KNOW ABOUT THE CALLER: PostgREST puts the HTTP headers of the request in the setting
-- request.headers (json). Supabase sits behind Cloudflare, which sets cf-connecting-ip (overwritten by Cloudflare, so the
-- client cannot forge it there) and appends the client address to the END of x-forwarded-for (the first entries can be forged
-- by the client). So the "client key" is: cf-connecting-ip, else the LAST x-forwarded-for entry, else 'unknown'.
-- This is a best effort: if the project is ever served without that proxy the key could be forged, so a GLOBAL cap is added
-- that cannot be dodged. There is no other client identity for an anonymous caller.
--
-- WHAT IS LIMITED: only MISSES (unknown token). A real buyer's token always exists, so real use is never limited and
-- an attacker cannot lock buyers out by flooding (the limiter is consulted only after a lookup fails). Brute force is
-- hopeless anyway (random v4 uuid = 122 bits); the limiter only caps noise and cost.
--   per client key: 20 misses per minute; all clients together: 200 misses per minute.
--   Above that: exception 'busy, try again later' (code P0001, the same as the other throttles).
-- The log table has RLS on, NO policies, no grants: only the SECURITY DEFINER functions touch it.
--
-- NOTE ON "STABLE": the brief asked for STABLE, but a STABLE function cannot write, and the limiter must record misses.
-- So request_status is VOLATILE (PostgREST then allows it only as POST rpc, which is what supabase-js .rpc() uses anyway).
-- ---------------------------------------------------------------------
create table if not exists public.request_status_log (
  id         bigint generated always as identity primary key,
  client_key text        not null,
  created_at timestamptz not null default now()
);
create index if not exists request_status_log_at_idx  on public.request_status_log (created_at);
create index if not exists request_status_log_key_idx on public.request_status_log (client_key, created_at);
alter table public.request_status_log enable row level security;
revoke all on public.request_status_log from anon, authenticated;

create or replace function public.request_token_miss()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  hdr json;
  k   text;
  n   int;
begin
  begin
    hdr := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    hdr := null;
  end;
  k := left(coalesce(
         nullif(btrim(hdr ->> 'cf-connecting-ip'), ''),
         nullif(substring(coalesce(hdr ->> 'x-forwarded-for', '') from '([^,[:space:]]+)[[:space:]]*$'), ''),
         'unknown'), 64);

  perform pg_advisory_xact_lock(hashtext('behazmana.request_status_miss'));   -- one at a time: no race that lets a burst through
  delete from public.request_status_log where created_at < now() - interval '1 hour';
  select count(*) into n from public.request_status_log
   where client_key = k and created_at > now() - interval '1 minute';
  if n >= 20 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  select count(*) into n from public.request_status_log
   where created_at > now() - interval '1 minute';
  if n >= 200 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  insert into public.request_status_log (client_key) values (k);
end
$$;

revoke all on function public.request_token_miss() from public, anon, authenticated;   -- internal: only the two RPCs below call it

-- The buyer's view of ONE request (the one whose token = p_token). Returns null for an unknown token or a null token.
-- Never returns: contact, token, id, consent, other requests, makers' private data (email/phone unless the maker chose to show them),
-- admin_note. A 'declined' route returns only the maker's public identity (name, city, craft, portrait) and route_status = 'declined':
-- seen_at, offer_note, offer_price_ils, contact_*, updated_at are null. Makers that are not 'approved' any more are left out.
-- The jsonb is built key by key (no row_to_json / to_jsonb of a whole row), so adding a column to a table later cannot leak it.
create or replace function public.request_status(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.requests%rowtype;
  result jsonb;
begin
  if p_token is null then
    return null;
  end if;

  select * into v from public.requests r where r.token = p_token;
  if not found then
    perform public.request_token_miss();   -- may raise 'busy, try again later'
    return null;
  end if;

  select jsonb_build_object(
           'title',      v.title,
           'crafts',     to_jsonb(v.crafts),
           'text',       v."text",
           'due',        v.due,
           'status',     v.status,
           'created_at', v.created_at,
           'closed',     v.status = 'closed',
           'routes', coalesce((
             select jsonb_agg(
                      jsonb_build_object(
                        'maker_id',          m.id,
                        'maker_name',        m.name,
                        'maker_city',        m.city,
                        'maker_craft',       m.craft,
                        'maker_craft_other', m.craft_other,
                        'maker_portrait',    m.portrait,
                        'route_status',      rr.status,
                        'seen_at',           case when rr.status = 'declined' then null else rr.seen_at end,
                        'offer_note',        case when rr.status = 'offered'  then rr.offer_note else null end,
                        'offer_price_ils',   case when rr.status = 'offered'  then rr.offer_price_ils else null end,
                        'updated_at',        case when rr.status = 'declined' then null else rr.updated_at end,
                        'contact_phone',     case when rr.status <> 'declined' and m.phone_public then m.phone else null end,
                        'contact_email',     case when rr.status <> 'declined' and m.email_public then m.email else null end
                      )
                      order by rr.created_at, rr.id)
             from public.request_routes rr
             join public.makers m on m.id = rr.maker_id and m.status = 'approved'
             where rr.request_id = v.id
           ), '[]'::jsonb)
         )
    into result;

  return result;
end
$$;

revoke all on function public.request_status(uuid) from public, anon, authenticated;
grant execute on function public.request_status(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. RPC public.close_request(p_token): the buyer closes his/her own request.
-- Sets status = 'closed' and closed_by_buyer_at = now(). Returns true if the request exists (closing twice is fine: still true),
-- false for a null or unknown token (unknown tokens count in the same miss limiter, which may raise 'busy, try again later').
-- A closed request: makers can no longer change their routes, my_inbox hides the contact, the owner sees status 'closed'.
-- The buyer cannot reopen it (only the owner can, with a normal update).
-- ---------------------------------------------------------------------
create or replace function public.close_request(p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  if p_token is null then
    return false;
  end if;

  update public.requests
     set status = 'closed',
         closed_by_buyer_at = coalesce(closed_by_buyer_at, now())
   where token = p_token and status <> 'closed';
  get diagnostics n = row_count;
  if n > 0 then
    return true;
  end if;

  if exists (select 1 from public.requests where token = p_token) then
    return true;   -- already closed
  end if;

  perform public.request_token_miss();
  return false;
end
$$;

revoke all on function public.close_request(uuid) from public, anon, authenticated;
grant execute on function public.close_request(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Owner helper: view public.admin_requests
-- All requests with the number of routes and a count per route status. The view returns NOTHING unless is_owner()
-- (the where clause), and has no grant for anon. No token column (the owner does not need the buyer's key).
-- The owner can read request_routes directly (policies above), e.g. with an embedded maker:
--   from('request_routes').select('*, makers(name,city,craft,craft_other)').eq('request_id', id)
-- and lists the makers to choose from with from('makers').select('id,name,city,craft,craft_other').eq('status','approved')
-- (owner policy on makers, nothing new needed); the screen suggests those whose craft is in the request's crafts.
-- ---------------------------------------------------------------------
create or replace view public.admin_requests
  with (security_invoker = false)
as
  select r.id,
         r.created_at,
         r.title,
         r.crafts,
         r."text" as "text",
         r.due,
         r.contact,
         r.consent,
         r.status,
         r.closed_by_buyer_at,
         coalesce(c.total, 0)::int    as route_count,
         coalesce(c.sent, 0)::int     as routes_sent,
         coalesce(c.seen, 0)::int     as routes_seen,
         coalesce(c.thinking, 0)::int as routes_thinking,
         coalesce(c.offered, 0)::int  as routes_offered,
         coalesce(c.declined, 0)::int as routes_declined
  from public.requests r
  left join lateral (
    select count(*)                                    as total,
           count(*) filter (where rr.status = 'sent')     as sent,
           count(*) filter (where rr.status = 'seen')     as seen,
           count(*) filter (where rr.status = 'thinking') as thinking,
           count(*) filter (where rr.status = 'offered')  as offered,
           count(*) filter (where rr.status = 'declined') as declined
    from public.request_routes rr
    where rr.request_id = r.id
  ) c on true
  where public.is_owner();

revoke all on public.admin_requests from public, anon, authenticated;
grant select on public.admin_requests to authenticated;

-- =====================================================================
-- 7. VERIFICATION: read-only SELECTs. Run them one by one (or all; the editor shows the last result).
-- =====================================================================

-- 7.1 tables: request_routes and request_status_log must have rowsecurity = true; requests too
select tablename, rowsecurity from pg_tables
 where schemaname = 'public' and tablename in ('requests', 'request_routes', 'request_status_log');

-- 7.2 new columns on requests, and the constraints/indexes
select column_name, data_type, is_nullable, column_default from information_schema.columns
 where table_schema = 'public' and table_name = 'requests' and column_name in ('token', 'closed_by_buyer_at');
select conname, pg_get_constraintdef(oid) from pg_constraint
 where conrelid in ('public.request_routes'::regclass, 'public.requests'::regclass) and contype in ('c', 'f') order by conname;
select tablename, indexname from pg_indexes
 where schemaname = 'public' and indexname in ('requests_token_uq', 'request_routes_uq', 'request_routes_maker_idx',
       'request_routes_request_idx', 'request_status_log_at_idx', 'request_status_log_key_idx');

-- 7.3 policies: request_routes expect 6 (4 owner + 2 maker); requests expect exactly the 5 old ones (owner-only update!)
select tablename, policyname, cmd, roles, qual, with_check from pg_policies
 where schemaname = 'public' and tablename in ('request_routes', 'requests') order by tablename, cmd, policyname;

-- 7.4 triggers on request_routes (expect request_routes_after_insert, request_routes_guard (UPDATE), request_routes_guard_insert (INSERT))
-- and on requests (expect the old requests_throttle only)
select event_object_table, trigger_name, event_manipulation, action_timing from information_schema.triggers
 where event_object_schema = 'public' and event_object_table in ('request_routes', 'requests') order by 1, 2;

-- 7.5 table-level grants. Expect: request_routes -> authenticated SELECT, DELETE (anon nothing);
--     requests -> unchanged (authenticated SELECT, UPDATE, DELETE; anon nothing at table level);
--     my_inbox, admin_requests -> authenticated SELECT only (anon nothing); request_status_log -> nothing.
select grantee, table_name, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('request_routes', 'requests', 'my_inbox', 'admin_requests', 'request_status_log')
   and grantee in ('anon', 'authenticated', 'public')
 order by table_name, grantee, privilege_type;

-- 7.6 column-level grants. Expect request_routes INSERT: request_id, maker_id (authenticated);
--     UPDATE: status, seen_at, offer_note, offer_price_ils (authenticated);
--     requests INSERT: title, crafts, text, due, contact, consent, status, token (anon + authenticated); no UPDATE for anon.
select grantee, table_name, privilege_type, column_name from information_schema.role_column_grants
 where table_schema = 'public' and table_name in ('request_routes', 'requests') and grantee in ('anon', 'authenticated')
   and privilege_type in ('INSERT', 'UPDATE')
 order by table_name, privilege_type, grantee, column_name;

-- 7.7 functions: security type, volatility (v = volatile, s = stable) and search_path (must show search_path="")
select proname, prosecdef as security_definer, provolatile, proconfig
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('request_status', 'close_request', 'request_token_miss', 'request_route_closed',
                   'request_routes_guard', 'request_routes_guard_insert', 'request_routes_after_insert',
                   'is_owner', 'my_maker_id')
 order by proname;

-- 7.8 who may run the functions. Expect: request_status/close_request: anon true, authenticated true;
--     request_route_closed: anon false, authenticated true; request_token_miss + the three trigger functions: all false.
select f,
       has_function_privilege('anon',          f, 'execute') as anon_can_run,
       has_function_privilege('authenticated', f, 'execute') as authenticated_can_run
  from unnest(array['public.request_status(uuid)', 'public.close_request(uuid)', 'public.request_token_miss()',
                    'public.request_route_closed(uuid)', 'public.request_routes_guard()',
                    'public.request_routes_guard_insert()', 'public.request_routes_after_insert()']) as f;

-- 7.9 view columns: my_inbox 14 columns (no token), admin_requests 16 columns (no token)
select table_name, ordinal_position, column_name from information_schema.columns
 where table_schema = 'public' and table_name in ('my_inbox', 'admin_requests') order by table_name, ordinal_position;

-- 7.10 every request has a distinct token (must return 0 rows)
select token, count(*) from public.requests group by token having count(*) > 1;

-- ---------------------------------------------------------------------
-- 7.11 Checks the owner can run from a terminal, AS ANON (replace <PROJECT> and <PUBLISHABLE_KEY>; headers: apikey and Authorization: Bearer <PUBLISHABLE_KEY>)
--   curl "https://<PROJECT>.supabase.co/rest/v1/request_routes?select=*"   -> expect 401 / 42501 "permission denied" (never rows)
--   curl "https://<PROJECT>.supabase.co/rest/v1/my_inbox?select=*"         -> expect 401 / 42501
--   curl "https://<PROJECT>.supabase.co/rest/v1/admin_requests?select=*"   -> expect 401 / 42501
--   curl "https://<PROJECT>.supabase.co/rest/v1/requests?select=token"     -> expect 401 / 42501 (the token cannot be read back)
--   curl -X POST "https://<PROJECT>.supabase.co/rest/v1/rpc/request_status" -H "Content-Type: application/json" -d '{"p_token":"00000000-0000-4000-8000-000000000000"}'
--        -> expect 200 with body: null
--   same call with '{"p_token":null}' -> 200, null ;  with '{}' -> 404 PGRST202 (no such function signature)
--   call it ~25 times in a minute with random uuids -> after about 20 misses expect 400 P0001 "busy, try again later"
--   curl -X POST ".../rest/v1/rpc/close_request" -d '{"p_token":"00000000-0000-4000-8000-000000000000"}' -> 200, false
--   curl -X POST ".../rest/v1/rpc/request_token_miss" -d '{}'      -> expect 401/403 permission denied (internal function)
--   curl -X POST ".../rest/v1/rpc/request_route_closed" -d '{"p_request":"00000000-0000-4000-8000-000000000000"}' -> expect 401/403
--   curl -X PATCH ".../rest/v1/requests?id=eq.<ID>" -d '{"status":"closed"}'                  -> expect 401/403 (no update grant for anon)
--   The real positive test: submit a request from the site, then
--   curl -X POST ".../rest/v1/rpc/request_status" -d '{"p_token":"<the token in the browser localStorage>"}' -> JSON with title...routes:[], and NO "contact".
-- ---------------------------------------------------------------------


-- =====================================================================
-- appended from 7-עריכת-בקשה-והרשמה-אחת.sql
-- =====================================================================

-- בהזמנה: סקריפט 7. מריצים אחרי 4, 5, 6. בטוח להריץ פעמיים.
-- (א) הרשמה אחת בלבד לכל מייל ולכל מספר טלפון (יוצר שנדחה יכול להירשם שוב)
-- (ב) קונה יכול לערוך את הבקשה שלו (עם הקישור הסודי של המכשיר שלו)
-- Supabase יציג אזהרה על "פעולה הרסנית" בגלל שורות DROP/REPLACE: זה צפוי.

-- ---------------------------------------------------------------------
-- (א) מספר טלפון מנורמל: רק ספרות, +972 / 972 / 00972 הופכים ל-0 בהתחלה
--   "+972 (0)50-123-4567", "972501234567", "050 123 4567" -> כולם 0501234567
-- ---------------------------------------------------------------------
create or replace function public.norm_phone(p text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p is null then null
    else (
      select case when d = '' then null when d ~ '^0' then d else '0' || d end
      from (
        select case
                 when v ~ '^00972' then substr(v, 6)
                 when v ~ '^972'   then substr(v, 4)
                 else v
               end as d
        from (select regexp_replace(p, '\D', '', 'g') as v) x
      ) y
    )
  end
$$;

alter table public.makers
  add column if not exists phone_norm text generated always as (public.norm_phone(phone)) stored;

-- מייל אחד לכל נרשם פעיל (ממתין או מאושר). מי שנדחה לא תופס את המייל.
create unique index if not exists makers_email_unique
  on public.makers (lower(btrim(email)))
  where email is not null and status in ('pending', 'approved');

-- טלפון אחד לכל נרשם פעיל (לפחות 7 ספרות, אחרת מתעלמים)
create unique index if not exists makers_phone_unique
  on public.makers (phone_norm)
  where phone_norm is not null and char_length(phone_norm) >= 8 and status in ('pending', 'approved');

-- ---------------------------------------------------------------------
-- (ב) עריכת בקשה על ידי הקונה
-- ---------------------------------------------------------------------
alter table public.requests add column if not exists edited_at timestamptz;

-- מחזיר את פרטי הבקשה לעריכה (כולל פרטי הקשר שהקונה עצמו כתב). רק לבקשה פתוחה. אסימון לא מוכר: null.
create or replace function public.request_for_edit(p_token uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v public.requests%rowtype;
begin
  if p_token is null then
    return null;
  end if;
  select * into v from public.requests r where r.token = p_token;
  if not found then
    perform public.request_token_miss();   -- may raise 'busy, try again later'
    return null;
  end if;
  if v.status = 'closed' then
    return jsonb_build_object('closed', true);
  end if;
  return jsonb_build_object(
    'closed',  false,
    'title',   v.title,
    'crafts',  to_jsonb(v.crafts),
    'text',    v."text",
    'due',     v.due,
    'contact', v.contact
  );
end
$$;
revoke all on function public.request_for_edit(uuid) from public, anon, authenticated;
grant execute on function public.request_for_edit(uuid) to anon, authenticated;

-- מעדכן בקשה פתוחה. בודק את אותם כללים כמו בהכנסה. מחזיר true; false לאסימון לא מוכר; שגיאה 22023 אם הבקשה סגורה או נתון לא תקין.
create or replace function public.update_request(
  p_token   uuid,
  p_title   text,
  p_crafts  text[],
  p_text    text,
  p_due     text,
  p_contact text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v public.requests%rowtype;
  c text;
  n_crafts int;
begin
  if p_token is null then
    return false;
  end if;
  select * into v from public.requests r where r.token = p_token;
  if not found then
    perform public.request_token_miss();
    return false;
  end if;
  if v.status = 'closed' then
    raise exception 'request closed' using errcode = '22023';
  end if;

  n_crafts := coalesce(array_length(p_crafts, 1), 0);
  if n_crafts > 6 then
    raise exception 'too many crafts' using errcode = '22023';
  end if;
  foreach c in array coalesce(p_crafts, '{}'::text[]) loop
    if c is null or c not in ('wood', 'leather', 'ceramic', 'jewelry', 'metal', 'other') then
      raise exception 'bad craft' using errcode = '22023';
    end if;
  end loop;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 120 then
    raise exception 'bad title' using errcode = '22023';
  end if;
  if char_length(coalesce(p_text, '')) > 2000 then
    raise exception 'text too long' using errcode = '22023';
  end if;
  if char_length(coalesce(p_due, '')) > 80 then
    raise exception 'due too long' using errcode = '22023';
  end if;
  if p_contact is null or char_length(btrim(p_contact)) not between 5 and 120 then
    raise exception 'bad contact' using errcode = '22023';
  end if;

  update public.requests
     set title     = btrim(p_title),
         crafts    = coalesce(p_crafts, '{}'::text[]),
         "text"    = coalesce(p_text, ''),
         due       = coalesce(p_due, ''),
         contact   = btrim(p_contact),
         edited_at = now()
   where id = v.id;
  return true;
end
$$;
revoke all on function public.update_request(uuid, text, text[], text, text, text) from public, anon, authenticated;
grant execute on function public.update_request(uuid, text, text[], text, text, text) to anon, authenticated;

-- יוצרים רואים שהבקשה נערכה: העמודה edited_at מתווספת בסוף תיבת הבקשות
create or replace view public.my_inbox
  with (security_invoker = false)
as
  select rr.id              as route_id,
         rr.request_id      as request_id,
         rr.status          as route_status,
         rr.seen_at         as seen_at,
         rr.offer_note      as offer_note,
         rr.offer_price_ils as offer_price_ils,
         rr.created_at      as routed_at,
         r.title            as title,
         r.crafts           as crafts,
         r."text"           as "text",
         r.due              as due,
         case when r.status = 'closed' then null else r.contact end as contact,
         r.created_at       as created_at,
         r.status           as request_status,
         r.edited_at        as edited_at
  from public.request_routes rr
  join public.requests r on r.id = rr.request_id
  where rr.maker_id = (select public.my_maker_id());

revoke all on public.my_inbox from public, anon, authenticated;
grant select on public.my_inbox to authenticated;

-- ---------------------------------------------------------------------
-- בדיקה
-- ---------------------------------------------------------------------
select public.norm_phone('+972 (0)50-123-4567') as a, public.norm_phone('972501234567') as b,
       public.norm_phone('050 123 4567') as c, public.norm_phone('00972-50-1234567') as d;   -- כולם 0501234567

-- The owner can also read (and so really delete) photos in maker-photos; without a read rule, deleting removes nothing.
drop policy if exists "owner reads maker photos" on storage.objects;
create policy "owner reads maker photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'maker-photos' and public.is_owner());

select indexname from pg_indexes where schemaname = 'public' and indexname in ('makers_email_unique', 'makers_phone_unique');
select proname, prosecdef from pg_proc where proname in ('request_for_edit', 'update_request', 'norm_phone');
