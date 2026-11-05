# Multiverse Arena
A lightweight fictional-character battle archive for GitHub Pages. No build step or paid services.

## Publish
In this repository, open **Settings → Pages → Build and deployment → Source → GitHub Actions**.
The **Check and publish Arena** workflow tests and publishes the site. If the initial deployment runs before Pages is enabled, enable it, then rerun the workflow from Actions.
Expected address after a successful deployment: https://360Signs.github.io/Fictional/

Alternatively, use **Deploy from a branch → main → /(root)**. The five website files already live at the repository root; the Actions deployment job is not needed for this mode.

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
**This version stores records in your browser's IndexedDB, not on GitHub or in a shared database.** Other visitors get their own separate archives. Another device or browser will not see your records automatically. Clearing browser storage can remove the archive. Export regular JSON backups; a CSV leaderboard export is not a full backup.
The storage URL matters: moving the site to a different domain or browser profile creates a separate archive. Private browsing may delete data when closed.
No passwords, API secrets or account sign-in are needed. GitHub holds the public source code, not your browser's roster. Cross-device live sync requires a separately configured database and authentication.

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
Syntax and scoring tests were run during creation. CI covers rules, negative scores, undo, CSV, validation, worker ranking, search and pagination. Browser interactions and device-specific IndexedDB behavior still require a browser smoke test after deployment.
