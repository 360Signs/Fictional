# Multiverse Arena
A lightweight fictional-character battle archive for GitHub Pages. No build step. Supports Supabase cloud saves within your project’s plan limits.

## Publish
Use **Settings → Pages → Deploy from a branch → main → /(root)**.
The built-in GitHub Pages workflow publishes changes. The Check Arena workflow runs verification.

## Cloud setup
1. In your Supabase project, open SQL Editor, create a query, paste the contents of [supabase-setup.sql](supabase-setup.sql), and click Run.
2. Open Authentication → Users → Add user → Create new user. Enter your email and a password you choose. Enable Auto Confirm User if offered.
3. Open the Arena website, go to Data & settings, and sign in using that account.
4. On the device with your original data, export a device backup, then click Upload this device’s archive. The cloud account must be empty.
5. Sign in with the same email and password on your phone.

The URL and publishable key in cloud.js identify the Supabase project. SQL setup requires project-owner access. Keep passwords, service-role keys and secret keys out of this repository.

Each signed-in account has a private archive. Other registered users cannot access it. Signed-out mode opens the original local archive. Signing out retains that original device archive, which may be older than your cloud records. Export a cloud backup while signed in when needed.

## Use
- Add combatants individually or import CSV. All start at 100 MMR.
- Search names and universes, filter, and sort the rankings.
- Click a character to view stats, notes, recent battles, or edit the profile.
- Record a winner, loser, result and optional notes. Both ratings update.
- Undo mistaken results in Battle history; the original record remains marked as undone.
- Export JSON backups from Data & settings. Restore them on another device to transfer your archive.
- CSV imports skip existing name + universe pairs (case insensitive). Use a distinct name for each character version.
- Paste a direct HTTPS image URL for a portrait. Missing or unavailable images display initials. Remote image hosts can see image requests.
- Eight optional starter characters are available for an empty archive. These start at 100 with no fabricated battle history and use initial avatars until you add portraits.

## Scoring
| Result | Winner | Loser |
|---|---:|---:|
| Hard-fought victory / normal loss | +10 | -10 |
| Easy victory / brutal loss | +20 | -20 |
Negative MMR is permitted without a minimum. This is a fixed-points system, not opponent-adjusted Elo.
Ties sort by wins, name, then ID. Unbeaten fighters with at least one win show an infinite W/L ratio. Unplayed fighters show 0.00 and 0% win rate.

## Data storage
Signed-in edits save to Supabase through atomic RPCs. Every save checks the archive revision, and stale writes fail with a refresh prompt. Retried requests reuse an ID to prevent duplicate application. Read and write functions derive the account from the authenticated session. Direct table access is revoked and Row Level Security is enabled.

Cloud editing requires an internet connection. Changes are checked every 30 seconds while the tab is visible, when returning to the tab, and before saves. Unchanged reads return only the revision. Changed reads download the complete text archive. Save requests upload changed records only. Large initial archives and large imports can still take time.

Existing IndexedDB archives remain available while signed out. The migration button only uploads into an empty cloud account and retains the original device copy. JSON restore replaces the currently open archive and, when signed in, affects all devices using the account. Export backups regularly.

## Performance design
- Ranking/search/filtering run in a dedicated web worker.
- A maximum of 50 leaderboard rows and 50 battle-history cards are rendered per page.
- Portraits load lazily.
- IndexedDB saves records in atomic transactions. MMR/W/L are derived from battle history so undo cannot leave a half-updated result.
- Where Web Locks is supported, concurrent same-origin tab writes are serialized. BroadcastChannel refreshes other open tabs. Avoid concurrent editing in browsers without Web Locks.
- The complete text roster and battle list are loaded into memory. Very large histories/imports still have memory and startup costs; the website is not an unlimited server database.
- 50,000-character worker smoke tests run in CI. They do not measure browser rendering or guarantee speed on every phone.

## CSV format
```csv
name,verse,image,notes
Darth Vader,Star Wars,,Original trilogy
Master Chief,Halo,,Standard equipment
```
Quote fields containing commas or line breaks. Images must be HTTPS URLs. Name and verse are required (120-character limit each). Notes are limited to 5,000 characters. CSV export prefixes spreadsheet formula-like cells with an apostrophe for safety; use JSON for lossless backups.

## Files
- `index.html`, `style.css`: responsive dark interface
- `app.js`: UI, IndexedDB, backup, import, battle recording
- `core.js`: scoring, validation, CSV parsing
- `worker.js`: background ranking and search
- `tests.cjs`: Node tests
- `.github/workflows/pages.yml`: verification and publishing

Run checks with Node 22: `node tests.cjs`.
Serve over HTTP/HTTPS; directly opening index.html as a file is not supported because workers and storage require a consistent web origin.

## Verification limits
Cloud adapter and PostgreSQL regression tests cover retries, conflicting writes, account isolation, anonymous access, migration transactions and restore. Live project setup and sign-in must also be verified after applying the SQL.
Syntax and scoring tests were run during creation. CI covers rules, negative scores, undo, CSV, validation, worker ranking, search and pagination. Browser interactions and device-specific IndexedDB behavior still require a browser smoke test after deployment.
