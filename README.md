# licarsware

Private Roblox script with a real key system: **one key per script, one IP per key, instant blacklist on second IP**, plus a Vape-style GUI (RightShift menu, bottom-right "Injected" toast, gear menu with Dark/Light themes — Dark is default).

## Layout
```
Licarsware/
  loader.lua          remote loader (dev convenience)
  src/                modules (Config, Util, Theme, Notifications, Components, Auth, Main, init)
  server/server.py    auth server (stdlib only, no pip)
  tools/build.py      bundles src/ into dist/Licarsware.lua (one file)
  dist/Licarsware.lua generated
```

## 1) Generate your key (only you can)
```bash
python3 Licarsware/server/server.py          # starts on :8787
curl -X POST http://localhost:8787/admin/gen \
  -H "Authorization: Bearer changeme-admin-token" \
  -d '{"script": "licarsware", "duration": "lifetime"}'
# -> {"status":"ok","key":"A1B2-C3D4-E5F6-G7H8","script":"licarsware","duration":"lifetime"}
```
That key is **per-script** and stored server-side. Send it to nobody but your one user.

### License durations
Pass `duration` to `/admin/gen`: `1d` (1 day), `7d` (1 week) or `lifetime` (default).
- The clock starts on **first use** (activation), not creation — an unused 1d key doesn't decay.
- Timed keys return `expires_in` (seconds) on every verify; the client shows it on the key card and as a toast.
- Expired keys always answer `{'status': 'expired'}`, never bind an IP, and the client wipes the saved key.
- `/admin/reset` unbinds IP/HWID but **keeps the expiry** — no reset-to-full-duration trickery.

## 2) Enforced rules (server-side, tamper-proof)
- First successful verify **binds the key to that IP + HWID**.
- Same key from a **different IP** → HWID **blacklisted permanently**, key destroyed. Even the original IP can no longer use it.
- Blacklisted HWID → every future attempt is denied, even with a new key.
- 5 wrong keys → 10-minute lockout per device.

## 3) Deploy the auth server (free) and wire it in

### 3a. Create the persistence gist (1 minute, once)
Render's free tier has an **ephemeral disk** — every restart would wipe your keys.
Fix: a private GitHub "secret" gist that backs the key database.

1. GitHub → create a **secret gist** containing an empty file named `licarsware_db.json`.
2. Create a **personal access token** (classic, scope: `gist` only).
3. Save the gist ID (the string in the gist URL) and the token — you'll paste both into Render.

### 3b. Deploy on Render (free web service)
1. Push this project to a **private GitHub repo** (or just the `Licarsware/server/` folder).
2. [render.com](https://render.com) → **New → Web Service** → connect the repo.
3. Settings:
   - **Runtime:** Python 3
   - **Build command:** (leave empty)
   - **Start command:** `python3 Licarsware/server/server.py`
   - **Instance type:** Free
4. **Environment → add:"
   - `LW_ADMIN` = a long random string (your admin token — never the default)
   - `LW_GIST_ID` = your gist ID from 3a
   - `LW_GIST_TOKEN` = your GitHub token from 3a
5. Deploy. You get `https://licarsware-xxxx.onrender.com`.

> Free-tier note: Render spins the service down after ~15 min idle and cold-starts
> in ~30–60s. The key card's "Contacting auth server..." state covers this — the
> first verify may just take a bit longer. Gist persistence means restarts are harmless.

### 3c. Generate your key against the live server
```bash
curl -X POST https://licarsware-xxxx.onrender.com/admin/gen \
  -H "Authorization: Bearer YOUR_LW_ADMIN_VALUE" \
  -d '{"script": "licarsware", "duration": "lifetime"}'
```

### 3d. Wire it into the client
Edit `src/Config.lua`:
```lua
AuthUrl = 'https://licarsware-xxxx.onrender.com/verify',
```
Then `python3 Licarsware/tools/build.py` and ship `dist/Licarsware.lua`.

Optionally set `Cdn.Base` if you host `src/` remotely (not needed with the single-file build).

## 4) Build & distribute one file
```bash
python3 Licarsware/tools/build.py
# ship dist/Licarsware.lua — no loader/CDN required
```

## GUI
- **RightShift** toggles the menu.
- **⚙ (top right)** → theme dropdown: Dark (normal) / Light.
- **Self destruct** (main window) unloads all modules (restores WalkSpeed/jump/fog/etc.), kills every licarsware ScreenGui, and freezes its hooks — clean removal, no residual state.
- Bottom-right toast fires on inject: "Injected • licarsware loaded successfully".
- Demo tabs: Dashboard, Player, Visuals, Settings — wire your own modules into `src/Main.lua`.

## Admin
- `GET /admin/list` — dump keys + blacklist (Bearer token).
- `POST /admin/reset {"key": "..."}` — unbind a key from its IP (expiry is preserved).
- `POST /admin/unban {"hwid": "..."}` — remove a blacklist entry.

## Notes / honesty section
- HWID is a salted hash of executor+userId+jobId — strong enough to stop casual key-sharing, not a cryptographic identity.
- The Roblox client can't see the user's true public IP; the **server** reads it from the request — that's the only trustworthy source, so all IP logic lives server-side.
