# Getting DeskCall onto your iPhone from Windows

Written for: you, on Windows, with Sideloadly and no Mac.

## The one constraint

iOS apps can only be compiled by Xcode, which only runs on macOS. Sideloadly does
not compile anything — it takes an existing `.ipa`, re-signs it with your Apple
ID, and installs it. So the build has to happen on a Mac somewhere, and this repo
uses a free GitHub Actions macOS runner for that.

Total cost: $0. Total Macs you need to own: 0.

---

## Step 1 — Deploy the backend (5 minutes)

The app is useless without a lookup server. Deploy it free on Render:

1. Push this repo to GitHub.
2. Go to [render.com](https://render.com) → **New** → **Blueprint** → pick this repo.
   It reads [render.yaml](render.yaml) and builds the Docker image in [backend/](backend/).
3. When it goes live you get a URL like `https://deskcall-api.onrender.com`.
4. Open `https://<your-url>/health` in a browser. You should see
   `{"status":"ok","mode":"mock",...}`.

`MOCK_MODE=true` is the default, so the server returns realistic demo data with
no paid API keys. Add Twilio and B2B keys later in Render's **Environment** tab
and flip `MOCK_MODE` to `false` when you want real data.

> Render's free tier sleeps after 15 minutes idle; the first lookup after a nap
> takes ~30 seconds. That breaks the "under 1.5 seconds" goal from the blueprint,
> so move to a paid tier or Fly.io if you care about ring-time latency.

## Step 2 — Build the IPA (8 minutes, unattended)

1. In your GitHub repo, open the **Actions** tab and enable workflows.
2. Pick **Build unsigned IPA** → **Run workflow**.
3. Paste your Render URL into the `api_base_url` box. It gets baked into the app
   so you don't have to type it on the phone.
4. Wait for the green check, then download the **DeskCall-ipa** artifact.
5. Unzip it. Inside is `DeskCall.ipa`.

## Step 3 — Sideload it

1. Install [Sideloadly](https://sideloadly.io) and iTunes (the non-Microsoft-Store
   version — Sideloadly needs its drivers).
2. Plug in the iPhone, unlock it, trust the computer.
3. Drag `DeskCall.ipa` into Sideloadly.
4. Enter your Apple ID. Use a throwaway Apple ID if you'd rather not put your main
   one into a third-party tool; it only needs to be a valid free developer account.
5. Leave the bundle ID as `com.deskcall.app`. Click **Start**.
6. On the phone: **Settings ▸ General ▸ VPN & Device Management** → trust your
   developer certificate.

A free Apple ID signature expires after **7 days**. Re-run Sideloadly to refresh
it; your saved data survives. Sideloadly's "anisette"-based remote refresh can
automate this, and a $99/year paid account extends it to a year.

## Step 4 — Turn on caller ID

1. Open DeskCall, go to **Settings**, confirm it says *Connected*.
2. Go to **Caller ID** and tap **Sync to iPhone caller ID**.
3. Go to iOS **Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification** and
   switch **DeskCall** on. (On iOS 17 and earlier: **Settings ▸ Phone ▸ Call
   Blocking & Identification**.)
4. Back in DeskCall, tap Sync once more.

Now look up a number, tap **Show this name when they call**, sync, and that name
appears on the lock screen the next time it rings.

---

## What works on a free Apple ID, and what doesn't

| Feature | Free Apple ID | Paid ($99/yr) |
| :--- | :--- | :--- |
| Manual lookups, history, spam reports | ✅ | ✅ |
| Spam numbers auto-blocked while ringing | ✅ (extension downloads the list itself) | ✅ |
| Your saved names shown while ringing | ❌ needs App Group | ✅ |
| Signature lifetime | 7 days | 1 year |

The gap is App Groups. The Call Directory extension runs in its own sandbox, and
without an App Group entitlement it cannot read the names the app saved. DeskCall
detects this and degrades gracefully — you'll see an "App Group unavailable"
notice on the Caller ID screen, and spam blocking keeps working because the
extension fetches that list over the network instead.

### Enabling App Groups on a paid account

1. At [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list/applicationGroup),
   create the group `group.com.deskcall.app`.
2. Add it to both App IDs: `com.deskcall.app` and `com.deskcall.app.CallDirectory`.
3. In Sideloadly, enable **App Groups** under advanced options before installing.

If you change the group name, update `DeskCallAppGroup` in both
[ios/DeskCall/Info.plist](ios/DeskCall/Info.plist) and
[ios/CallDirectory/Info.plist](ios/CallDirectory/Info.plist).

---

## Why there's no live lookup while ringing

The blueprint's diagram shows a network lookup firing during an incoming call.
On iOS that is not possible the way it is on Android:

- **Call Directory extensions** are preload-only. iOS asks for your whole list in
  advance and consults its own copy while ringing. Your app is never woken up and
  is never told who is calling — which is precisely why it can't leak your call log.
- **Live Caller ID Lookup** (iOS 18+) does allow a real-time query, but it requires
  running an OHTTP relay plus a homomorphic-encryption server so Apple's proxy can
  query you without either side learning the number. That is substantial, paid
  infrastructure, and it needs a real developer account and entitlement.

So DeskCall preloads what you've looked up, and does live queries from the app
itself when you type a number. Overlay-style real-time lookup is an Android-only
capability.

---

## Troubleshooting

**Sideloadly: "Provisioning profile failed"** — You've hit the free-account limit
of 3 App IDs per 7 days. DeskCall uses 2 (app + extension). Delete unused App IDs
at developer.apple.com or wait out the week.

**App installs but the extension is missing from iOS Settings** — The extension
failed to sign. In Sideloadly, make sure "Remove app extensions" / "Remove
PlugIns" is **unchecked**.

**"Couldn't reach the lookup server"** — Render is asleep. Open `/health` in a
browser, wait 30 seconds, retry. Also check Settings uses `https://`.

**Sync says iOS refused the reload** — The extension is off. Enable DeskCall in
Call Blocking & Identification, then sync again.

**Nothing shows while ringing** — iOS caches aggressively. Toggle DeskCall off and
on in Call Blocking & Identification, then re-sync. Also confirm the number is in
the Caller ID tab's saved list, and that the extension matched the exact E.164
digits (a number saved as `+14155551234` won't match a call from `4155551234`
unless your carrier sends the country code — it almost always does in the US).
