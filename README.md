# StormReel

Track every film and series you watch. Rate titles in bolts, keep a diary, build collections and compare notes with friends, all under a live storm sky. You can change the weather, too.

The whole site is one file, `index.html`. `supabase-schema.sql` sets up the database.

---

## 1. Put it on GitHub Pages

1. Create a new **public** repository and upload `index.html`, `README.md` and `supabase-schema.sql`.
2. Go to **Settings → Pages**. Under Source, choose **Deploy from a branch**, then pick `main` and `/ (root)`.
3. After a minute or two the site is live at `https://YOUR-NAME.github.io/REPO-NAME/`.

It works straight away. Until you finish step 2, accounts are saved only in each visitor's browser.

## 2. Turn on cloud accounts (Supabase, free)

1. Sign up at **supabase.com** and create a **New project**. Pick any name and a region near you, and save the database password somewhere safe.
2. In the project, open **SQL Editor → New query**, paste in all of `supabase-schema.sql`, then click **Run**. It should finish with "Success. No rows returned."
3. Go to **Project Settings → API Keys** and copy two things:
   - the **Project URL** (`https://xxxx.supabase.co`)
   - the **Publishable key** (starts with `sb_publishable_`). On older projects this is called the "anon public" key, and either one works.
4. Open `index.html`, find `const CONFIG` near the top of the script, and paste them in:
   ```js
   supabaseUrl: "https://xxxx.supabase.co",
   supabaseKey: "sb_publishable_...",
   ```
   Commit the change. These two values are meant to be public. Never paste the **secret** key (`sb_secret_...`) or the `service_role` key into this file.
5. **Required:** go to **Authentication → Sign In / Providers → Email** and turn **off** "Confirm email". Do this before anyone signs up.

### Usernames, not emails

People sign up and sign in with just a username and password. Supabase needs an email address for every account, so the app quietly uses `username@users.stormreel.app`. Nobody sees it, and with confirmation off, no email is ever sent. The domain is `loginDomain` in `CONFIG`. Don't change it after people have joined, or they won't be able to sign in.

The trade-off is that there's no "forgot password" email. If someone forgets theirs, reset it yourself in Supabase → **SQL Editor**:

```sql
update auth.users
set encrypted_password = extensions.crypt('TheirNewPassword', extensions.gen_salt('bf'))
where email = 'bob@users.stormreel.app';   -- their username + @users.stormreel.app
```

If someone signed up while "Confirm email" was still on, they can't sign in yet. Unlock everyone with:

```sql
update auth.users set email_confirmed_at = now() where email_confirmed_at is null;
```

## 3. Optional: films for everyone (TMDB)

Without a TMDB key the site shows series only, using TVmaze. To add films, trailers and recommendations:

1. Get a free key at themoviedb.org → Settings → API.
2. Either paste it into `tmdbKey` in `CONFIG`, so every visitor gets films, or let each person add their own in the site's Settings page.

TMDB's terms allow free, non-commercial use with attribution, and the footer already credits them. If StormReel ever makes money, you need a commercial agreement with TMDB.

---

## How it works

```
 Visitor's browser (index.html on GitHub Pages)
   │
   ├── Film/series info ──► TMDB or TVmaze   (public catalogue data, read-only)
   │
   └── Accounts + data ──► Supabase           (YOUR database)
          • Auth:  username + password sign-in, sessions
          • Postgres tables: profiles, ratings, reviews, history,
            watchlist, collections, collection_items, friends
          • Row Level Security decides who can read each row
```

- **GitHub Pages** only serves the file. It has no server and stores nothing.
- **Supabase** is a hosted Postgres database with sign-in built in. The browser talks to it directly using the publishable key.
- **Why the public key is safe:** every table has row-level security switched on, and the database checks each request against rules in `supabase-schema.sql`:
  - **ratings, reviews, diary:** you can read your own rows, plus the rows of anyone who has added you as a friend
  - **watchlist, collections:** you only
  - **usernames:** public, so people can find each other
  - **writing:** nobody can change another person's data

  These rules were tested against a real Postgres engine.
- **Friends work both ways.** Add someone by username. Once they add you back, you can each see the other's ratings, reviews and diary.
- **Passwords** are handled by Supabase Auth and stored hashed. StormReel never sees them.
- **Swapping pieces later:** film data goes through a provider layer (`TMDBProvider`, `TVmazeProvider`), and your data goes through a store layer (`CloudStore`, `LocalStore`). Either can be replaced without touching the rest of the app.
- **Free tier limits:** about 50,000 monthly users and a 500 MB database. Projects with no activity for a week get paused, and you can wake them from the dashboard.

## Playing films

Titles marked **▶ Free** get a **Play now** button that streams the whole film inside StormReel. The app takes the title's TMDB number and asks each stream source whether it can play it (`Streams` and `OpenFilms` in the script). If one can, the film opens in a full-screen player.

The built-in source covers 19 films that anyone may stream:

- **11 Blender Studio open movies,** released under Creative Commons and played from Blender's official YouTube uploads.
- **8 public-domain classics** from the Internet Archive.

The **Free** page lists them all. Every other title gets a **Where to watch** panel showing the services that carry it in the visitor's country (TMDB data, supplied by JustWatch). Each logo links out to the service.

## The storm

The sky is drawn live on a canvas:

- **Clouds:** soft cloud shapes drawn ahead of time, in three layers that drift at different speeds.
- **Rain:** about a thousand drops at varying depths, blown by gusting wind, splashing at the bottom of the screen.
- **Lightning:** each bolt is generated fresh, with branches, a re-strike flicker and light that spreads through nearby clouds.

The flash also brightens the logo, the headline and the header edge. Rating something five bolts, searching or clicking the logo calls down a strike.

The weather button in the header switches between Calm, Drizzle, Storm and Supercell. The three color themes are Thunderhead, Overcast and Supercell. The animation pauses when the tab is hidden, and visitors whose device asks for reduced motion get a still sky.
