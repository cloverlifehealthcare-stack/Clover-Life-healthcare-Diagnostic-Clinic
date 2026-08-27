-- Clover Life Healthcare Diagnostic Clinic — database schema
-- Run this once in your Supabase project's SQL Editor (Dashboard -> SQL
-- Editor -> New query -> paste this whole file -> Run). This project's
-- Supabase project should be a brand-new one, separate from any other
-- clinic system you run — nothing here references or shares data with
-- another project.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default '',        -- job title, e.g. "Radiologist"
  dept text not null default '',
  phone text not null default '',
  access_role text not null default 'staff' check (access_role in ('admin','staff')),
  created_at timestamptz not null default now()
);

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  age int,
  sex text,
  phone text,
  last_visit date,
  condition text,
  created_at timestamptz not null default now()
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient text not null,
  doctor text,
  appt_date date not null,
  appt_time text not null,
  type text,
  status text not null default 'Scheduled' check (status in ('Scheduled','Checked-in','Completed','Cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists public.lab_orders (
  id uuid primary key default gen_random_uuid(),
  patient text not null,
  test text not null,
  ordered_date date not null default current_date,
  status text not null default 'Pending' check (status in ('Pending','In Progress','Completed')),
  result text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  patient text not null,
  description text not null,
  amount numeric(12,2) not null default 0,
  invoice_date date not null default current_date,
  status text not null default 'Unpaid' check (status in ('Unpaid','Paid')),
  created_at timestamptz not null default now()
);

create table if not exists public.clinic_settings (
  id int primary key default 1 check (id = 1),
  name text not null default 'Clover Life Healthcare Diagnostic Clinic',
  tagline text not null default 'Diagnostic & Wellness Center',
  address text not null default '',
  phone text not null default '',
  hours text not null default ''
);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  text text not null,
  at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- New staff member -> automatic profile row
-- When you create a user in Authentication -> Users (or they're invited),
-- this fires and gives them a "staff" profile automatically. Promote the
-- first one to admin with the UPDATE at the bottom of this file.
-- ---------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, access_role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    'staff'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Helper: is the current logged-in user an administrator?
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and access_role = 'admin'
  );
$$;

-- Only an admin may change someone's access level, even on their own row.
-- (auth.uid() is null for direct SQL Editor / migration changes — those are
-- trusted by definition, since only a project admin has SQL Editor access.
-- This guard only applies to changes coming through the app, where a real
-- signed-in user's id is attached to the request.)
create or replace function public.guard_profile_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.access_role is distinct from old.access_role
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'Only an administrator can change access level.';
  end if;
  return new;
end;
$$;

drop trigger if exists before_profile_update on public.profiles;
create trigger before_profile_update
  before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ---------------------------------------------------------------------
-- Row Level Security
-- Every table is readable/writable only by a signed-in clinic account.
-- Staff accounts can do everything with clinical/billing data; only
-- admins can manage other staff accounts or edit the clinic profile.
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.patients enable row level security;
alter table public.appointments enable row level security;
alter table public.lab_orders enable row level security;
alter table public.invoices enable row level security;
alter table public.clinic_settings enable row level security;
alter table public.activity_log enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete using (public.is_admin());
-- (no insert policy — new rows are only ever created by the trigger above,
-- which runs as security definer and bypasses RLS)

drop policy if exists patients_all on public.patients;
create policy patients_all on public.patients
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists appointments_all on public.appointments;
create policy appointments_all on public.appointments
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists lab_orders_all on public.lab_orders;
create policy lab_orders_all on public.lab_orders
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists invoices_all on public.invoices;
create policy invoices_all on public.invoices
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists activity_log_select on public.activity_log;
create policy activity_log_select on public.activity_log
  for select using (auth.role() = 'authenticated');

drop policy if exists activity_log_insert on public.activity_log;
create policy activity_log_insert on public.activity_log
  for insert with check (auth.role() = 'authenticated');

drop policy if exists clinic_settings_select on public.clinic_settings;
create policy clinic_settings_select on public.clinic_settings
  for select using (auth.role() = 'authenticated');

drop policy if exists clinic_settings_update on public.clinic_settings;
create policy clinic_settings_update on public.clinic_settings
  for update using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- Sample data — safe to delete later from the app's Settings page (once
-- you're an admin) or with: truncate patients, appointments, lab_orders,
-- invoices restart identity;
-- ---------------------------------------------------------------------

insert into public.clinic_settings (id, name, tagline, address, phone, hours)
values (1, 'Clover Life Healthcare Diagnostic Clinic', 'Diagnostic & Wellness Center',
        '2F Clover Life Building, 88 Salcedo St., Makati City', '(02) 8888 4321',
        'Mon–Sat, 7:00 AM – 7:00 PM')
on conflict (id) do nothing;

insert into public.patients (name, age, sex, phone, last_visit, condition) values
  ('Amara Sy Villanueva', 34, 'F', '0917 220 4481', current_date - 3, 'Hypertension follow-up'),
  ('Ben Custodio', 58, 'M', '0918 774 0092', current_date - 10, 'Type 2 diabetes monitoring'),
  ('Carmela Ibarra', 27, 'F', '0920 553 1187', current_date - 1, 'Pre-employment screening'),
  ('Diego Manalo', 45, 'M', '0915 340 9922', current_date - 21, 'Annual physical'),
  ('Elena Bautista', 63, 'F', '0922 118 4470', current_date - 2, 'Cardiac workup'),
  ('Franco Reyes', 19, 'M', '0917 665 2201', current_date - 40, 'Sports clearance')
on conflict do nothing;

insert into public.appointments (patient, doctor, appt_date, appt_time, type, status) values
  ('Amara Sy Villanueva', 'Dr. Marcus Aquino', current_date, '09:00', 'Follow-up', 'Checked-in'),
  ('Carmela Ibarra', 'Dr. Isabel Trinidad', current_date, '10:30', 'Chest X-ray', 'Scheduled'),
  ('Elena Bautista', 'Dr. Marcus Aquino', current_date, '11:15', 'Cardiac consult', 'Scheduled'),
  ('Ben Custodio', 'Dr. Marcus Aquino', current_date - 1, '14:00', 'Diabetes review', 'Completed'),
  ('Franco Reyes', 'Dr. Isabel Trinidad', current_date + 1, '08:30', 'Sports physical', 'Scheduled'),
  ('Diego Manalo', 'Dr. Marcus Aquino', current_date - 2, '15:30', 'Annual physical', 'Cancelled')
on conflict do nothing;

insert into public.lab_orders (patient, test, ordered_date, status, result) values
  ('Amara Sy Villanueva', 'Lipid Panel', current_date - 1, 'Completed', 'LDL 138 mg/dL, HDL 46 mg/dL — mildly elevated LDL.'),
  ('Ben Custodio', 'HbA1c', current_date - 2, 'Completed', '7.1% — improved from prior 7.8%.'),
  ('Carmela Ibarra', 'Chest X-ray', current_date, 'In Progress', ''),
  ('Elena Bautista', 'ECG + Troponin', current_date, 'Pending', ''),
  ('Diego Manalo', 'CBC', current_date - 5, 'Completed', 'All values within normal range.'),
  ('Franco Reyes', 'Urinalysis', current_date - 1, 'Pending', '')
on conflict do nothing;

insert into public.invoices (patient, description, amount, invoice_date, status) values
  ('Amara Sy Villanueva', 'Follow-up consult + Lipid Panel', 1850, current_date - 1, 'Paid'),
  ('Ben Custodio', 'HbA1c + consult', 2100, current_date - 2, 'Paid'),
  ('Carmela Ibarra', 'Pre-employment package', 3200, current_date, 'Unpaid'),
  ('Elena Bautista', 'Cardiac workup deposit', 4500, current_date, 'Unpaid'),
  ('Diego Manalo', 'Annual physical package', 2800, current_date - 5, 'Paid')
on conflict do nothing;

insert into public.activity_log (text) values
  ('Sample data loaded for Clover Life Healthcare Diagnostic Clinic')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- LAST STEP (do this manually, after creating your own login):
-- 1. Dashboard -> Authentication -> Users -> Add user. Use your own email
--    and a password. This automatically creates your "staff" profile row
--    via the trigger above.
-- 2. Come back to the SQL Editor and run the line below with your email,
--    to make yourself an administrator:
--
--    update public.profiles set access_role = 'admin'
--    where id = (select id from auth.users where email = 'YOUR-EMAIL-HERE');
-- ---------------------------------------------------------------------
