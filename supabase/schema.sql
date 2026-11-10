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
  phone_public boolean not null default false,       -- the maker chose to show the phone on the site (call and WhatsApp buttons). The email is never shown.
  photos      text[] not null default '{}',          -- paths inside the storage bucket "maker-photos" (the work photos, up to 10)
  portrait    text,                                  -- path of the maker's own photo in the same bucket
  status      text not null default 'pending',
  admin_note  text,                                  -- why a request was rejected (only the owner sees it)
  -- length checks: the public key is public, so these limit what a spammer can store
  constraint makers_status_ck  check (status in ('pending', 'approved', 'rejected')),
  constraint makers_craft_ck   check (craft in ('wood', 'leather', 'ceramic', 'jewelry', 'metal')),
  constraint makers_name_ck    check (char_length(btrim(name)) between 1 and 80),
  constraint makers_city_ck    check (char_length(btrim(city)) between 1 and 60),
  constraint makers_story_ck   check (char_length(story) <= 1000),
  constraint makers_email_ck   check (email is null or (char_length(email) between 5 and 120 and email like '%_@_%._%')),
  constraint makers_phone_ck   check (phone is null or char_length(phone) between 7 and 30),
  constraint makers_contact_ck check (email is not null or phone is not null),   -- at least one way to reach them
  constraint makers_photos_ck  check (coalesce(array_length(photos, 1), 0) <= 10),
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

-- For a database made with an older version of this file: add the portrait column and raise the photo limit to 10.
alter table public.makers add column if not exists portrait text;
alter table public.makers add column if not exists phone_public boolean not null default false;
alter table public.makers drop constraint if exists makers_photos_ck;
alter table public.makers add constraint makers_photos_ck check (coalesce(array_length(photos, 1), 0) <= 10);

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
grant insert (name, city, craft, story, email, phone, phone_public, portrait, photos, status) on public.makers   to anon, authenticated;
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
-- and contact_phone: the maker's phone ONLY when the maker chose to show it at signup (phone_public = true),
-- otherwise null. The email is never in this view. A shown phone can be copied by anyone who sees it.
-- security_invoker = false means: "run as the view's owner", so the view can read makers even though
-- visitors cannot. That is safe and intended here, because the view itself decides which rows and
-- columns come out. (Supabase's security linter may mention this; it is expected for this view.)
-- ---------------------------------------------------------------------
create or replace view public.public_makers
  with (security_invoker = false)
as
  select id, name, city, craft, story, photos, portrait,
         case when phone_public then phone end as contact_phone
  from public.makers
  where status = 'approved';

revoke all on public.public_makers from anon, authenticated;
grant select on public.public_makers to anon, authenticated;

-- ---------------------------------------------------------------------
-- Photos: a PUBLIC bucket "maker-photos" (photos of approved makers are shown on the site).
-- Limit 2 MB per file and image types only. The site shrinks photos to about 300-500 KB before upload.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('maker-photos', 'maker-photos', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

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
