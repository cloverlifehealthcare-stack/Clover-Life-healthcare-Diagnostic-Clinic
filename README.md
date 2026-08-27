# Clover Life Healthcare Diagnostic Clinic — Management System (Supabase edition)

A separate, independent clinic management app for Clover Life Healthcare
Diagnostic Clinic: patients, appointments, diagnostics/lab orders, billing,
and staff — with individual staff logins, real-time-capable data, and a
managed Postgres database (via [Supabase](https://supabase.com)).

**This project is fully independent.** It has its own codebase, its own
database, and — once you set it up — its own Supabase project and hosting
project. It shares nothing with, and has no connection to, any other clinic
system.

## How this is different from a typical backend app

There's no server to run yourself. The browser talks directly to Supabase
(a hosted Postgres database with built-in authentication), protected by
Row Level Security policies defined in `supabase/schema.sql` — those
policies, not a server you maintain, are what enforce who can see and
change what. That means:

- Hosting is just serving static files (`index.html` + `config.js`) — any
  static host works. Vercel is the one this README walks through.
- No server to keep running, no disk to manage, no Docker.
- Password resets, secure password storage, and login sessions are handled
  by Supabase, not by custom code.

## Setup — do these in order

### 1. Create a new Supabase project

Go to [supabase.com](https://supabase.com), sign up or log in, and click
**New project**. Give it a name that's clearly this clinic's own (e.g.
`clover-life-diagnostic`) — don't reuse a project from any other clinic
system. Pick a strong database password and save it somewhere safe (a
password manager) — you likely won't need it day-to-day, but you'll want it
if you ever need direct database access.

### 2. Run the schema

In your new project: **SQL Editor → New query**. Open `supabase/schema.sql`
from this folder, paste its entire contents in, and click **Run**. This
creates all the tables, security policies, and loads the sample data.

### 3. Create your own (admin) login

**Authentication → Users → Add user.** Use your real email and a strong
password. (You can either send an invite email or set the password directly
— your choice.) This automatically creates your staff profile behind the
scenes.

Then back in **SQL Editor**, run this one line (with your real email):

```sql
update public.profiles set access_role = 'admin'
where id = (select id from auth.users where email = 'YOUR-EMAIL-HERE');
```

That makes you an administrator — able to manage other staff and the
clinic profile.

### 4. Get your API keys

**Project Settings → API.** You'll need the **Project URL** and the
**anon / public** key (NOT the `service_role` key — never put that one in
this app).

### 5. Fill in `config.js`

Open `config.js` in this folder and replace the two placeholder values with
what you copied in step 4.

### 6. Try it locally (optional but recommended)

Since this is just static files, any local web server works, e.g.:

```bash
cd clover-life-diagnostics
python3 -m http.server 8080
```

Open **http://localhost:8080**, sign in with the login you created in step
3, and confirm everything loads.

### 7. Deploy to Vercel (so your team can reach it from anywhere)

1. Push this folder to a **new** GitHub repository (separate from any other
   clinic project) — e.g. via GitHub's web **uploading an existing file**
   option, no command line needed.
2. Sign up / log in at [vercel.com](https://vercel.com) (using your GitHub
   account makes this one click), click **Add New → Project**, and import
   that repository.
3. Vercel auto-detects this as a static site — no build settings needed.
   Click **Deploy**.
4. Vercel gives you a working `https://….vercel.app` URL immediately after
   the first deploy finishes (usually under a minute) — that's what you
   share with your team.

## Adding more staff later

1. **Supabase dashboard → Authentication → Users → Add user** — create
   their login with their email.
2. That's it for the account — a "staff" profile is created automatically.
3. In the app's **Staff** page (as an admin), click the edit icon next to
   their name to fill in their name, role/title, department, and — if
   they should be an administrator — set their access level.

Staff can change their own password any time from **Settings → Your
account**, or use **Forgot your password?** on the login screen (Supabase
emails them a reset link — this uses Supabase's built-in email sending,
which is rate-limited; for a real clinic doing this often, connect a custom
SMTP provider under Project Settings → Auth in Supabase).

## What "Administrator" vs "Staff" can do

- Everyone (any signed-in account) can manage patients, appointments,
  diagnostics/lab orders, and billing.
- Only an **Administrator** can edit other staff members' details/access
  level, remove a staff profile, and edit the clinic profile in Settings.
- This is enforced at the database level (Row Level Security), not just
  hidden in the app — even a modified copy of the app couldn't bypass it.

## Your data

Everything lives in your Supabase project's Postgres database — Supabase
handles backups on paid plans; on the free plan, consider exporting a
backup periodically (**Database → Backups**, or `pg_dump` against the
connection string in Project Settings → Database).

## A note on security, since this handles patient health information

This app has real authentication and database-enforced permissions, but
it's a lightweight self-hosted tool, not a certified healthcare system —
no audit logging of who viewed what, no compliance certification. That's
workable for a small clinic's internal use with strong unique passwords per
staff member, but worth knowing before scaling up or handling especially
sensitive records.

## Project layout

```
index.html              the entire frontend (single page app)
config.js                your Supabase project URL + anon key (edit this)
supabase/schema.sql      database tables, security policies, sample data
```
