# DeskCall

A privacy-first caller identification app for iPhone, plus the lookup backend it
talks to. Built from [app_blueprint.md](app_blueprint.md).

**Start here if you just want it on your phone: [SIDELOADING.md](SIDELOADING.md).**

## What it does

- Type or paste a number, get back a name, line type, carrier, job title,
  company, and LinkedIn URL where available.
- Save a result so the name appears on the lock screen the next time that number
  calls, via a CallKit Call Directory extension.
- Report spam numbers; numbers with enough reports get blocked on device.
- Keep a local lookup history that never leaves the phone.

## What makes it privacy-first

- **No contacts permission.** The app has no address-book entitlement at all, so
  it cannot upload your contacts even by accident.
- **Outbound only.** A lookup request carries the number being checked and
  nothing else — no device identifier, no account, no analytics.
- **Transient server memory.** Results are cached in RAM under a SHA-256 hash of
  the number, with a hard 24-hour expiry. Nothing touches disk; a restart forgets
  everything.
- **Write-only system hook.** A Call Directory extension can only hand data *to*
  iOS. iOS never tells it who is calling you.
- **No identity on the blocklist endpoint.** `/api/v1/directory` is
  unauthenticated by design, so fetching it reveals nothing about the device.

## Layout

```
backend/           FastAPI lookup server (Docker, deploys to Render free tier)
  app/main.py        routes: /lookup, /report, /directory, /health
  app/providers.py   the waterfall: cache -> telecom/CNAM -> B2B enrichment
  app/cache.py       hashed, TTL-bounded in-memory cache + rate limiter
  app/directory.py   community spam blocklist served to the extension
ios/               SwiftUI app + CallKit extension (project.yml, built by CI)
  Shared/            API client, models, shared storage (compiled into both targets)
  DeskCall/Sources/  the four tabs: Lookup, Recent, Caller ID, Settings
  CallDirectory/     CXCallDirectoryProvider implementation
.github/workflows/ macOS CI that outputs an unsigned .ipa for Sideloadly
```

There is no `.xcodeproj` in the repo — CI generates it from
[ios/project.yml](ios/project.yml) with XcodeGen, which keeps the project file
out of version control and lets a Windows machine own the sources.

## Running the backend locally

Requires Python 3.11+ (this machine has none installed; Docker or Render works
without it).

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
```

Or with Docker:

```bash
docker build -t deskcall-api ./backend
docker run -p 8000:8000 -e MOCK_MODE=true deskcall-api
```

Then:

```bash
curl -X POST http://localhost:8000/api/v1/lookup \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+14155551234"}'
```

Mock mode answers with demo data for `+14155551234`, `+12125558899`, and
`+18005559999`, and derives stable pseudo-results for anything else, so the whole
app is usable before you pay for a single API call.

## Going live with real data

Set these in Render's **Environment** tab and flip `MOCK_MODE` to `false`:

| Variable | Where it comes from | Cost |
| :--- | :--- | :--- |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` | [console.twilio.com](https://console.twilio.com) | ~$0.01 per lookup |
| `B2B_API_KEY` / `B2B_BASE_URL` | any phone-to-person enrichment vendor | ~$0.05–0.10 per match |

B2B enrichment only fires when the carrier step already produced a name, so you
don't burn the expensive credit on numbers that were never going to resolve.

`CLIENT_KEYS` (comma-separated) locks `/lookup` and `/report` to clients sending
a matching `X-DeskCall-Key` header — worth setting once your URL is public.

## Known deviations from the blueprint

- The blueprint's Twilio URL (`/v2/Lookups/{number}`) returns 404. The real v2
  endpoint is `/v2/PhoneNumbers/{number}`, which is what [providers.py](backend/app/providers.py) uses.
- The blueprint shows a live lookup firing while the phone rings. iOS doesn't
  permit that outside of Live Caller ID Lookup, which needs OHTTP relay
  infrastructure and a paid developer account — see the explanation in
  [SIDELOADING.md](SIDELOADING.md). DeskCall preloads instead.
- Saved names require an App Group, which free sideloading certificates don't
  grant. Spam blocking works either way; the app says so plainly when it detects
  the limitation.
