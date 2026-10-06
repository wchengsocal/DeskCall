# Professional Caller & Privacy-First Lookup App: Development Blueprint

> Original design document. See [README.md](README.md) for how the shipped code
> differs from it (Twilio endpoint path, iOS preload vs. live lookup, App Groups).

This document outlines the architecture, setup steps, and implementation roadmap for building a mobile application that identifies unknown callers using premium, legal telecom and B2B enrichment APIs while strictly adhering to privacy-first standards.

---

## System Architecture

When an unknown number calls a user's phone, the app initiates a secure, anonymous network request through a **Waterfall Backend Flow**:

```
 [ Incoming Unknown Call ]
            |
            v
+--------------------------------------+
|  Step 1: Check Local App Cache       | --(Found)--> [ Display Info Instantly ]
+--------------------------------------+
            | (Not Found)
            v
+--------------------------------------+
|  Step 2: Query Telecom/CNAM API      | --(Found Name)--+
+--------------------------------------+                 |
            | (Pass Name + Number)                        v
            v
+--------------------------------------+
|  Step 3: Query B2B Data Enrichment   | --(Found)--> [ Title, Company, LinkedIn ]
+--------------------------------------+
            |
            v
[ Render Secure Privacy-First Profile UI ]
```

---

## Pillars of Privacy-First Architecture

1. **No Contact Syncing:** The app never requests permission to read or upload the user's address book. All lookups are purely outbound.
2. **Oblivious Proxies (OHTTP):** For iOS, configure server infrastructure alongside Apple's Live Caller ID Lookup. Queries route through an encrypted proxy relay, separating the user's identity from the number being searched.
3. **Transient Memory Processing:** Lookups are processed in-memory or transiently cached with short-lived expiration tags (24 hours) to minimize persistent logging of communication patterns.

---

## Platform Integration

### iOS (Swift / CallKit)
1. Enable the Call Directory Extension in Xcode.
2. Feed backend data into the local system database using `CXCallDirectoryProvider`.
3. Read encrypted system contexts asynchronously via background fetch workers.

### Android (Kotlin / Telecom Framework)
1. Request `READ_PHONE_STATE` and `ANSWER_PHONE_CALLS` in `AndroidManifest.xml`.
2. Register a `BroadcastReceiver` for `TelephonyManager.ACTION_PHONE_STATE_CHANGED`.
3. On an incoming state, dispatch the payload to the lookup server and draw a
   custom system overlay on top of the default dialer window.

---

## Operational Budget

| Service Layer | Unit Financials | Target Threshold | Implementation Goal |
| :--- | :--- | :--- | :--- |
| **Server Infrastructure** | $0.00 / Dev tier | AWS Lambda / Render Free Tier | Hosts the FastAPI router. |
| **Telecom Registry Lookup** | ~$0.01 per query | Twilio API | Pinpoints the network subscriber. |
| **B2B Persona Data** | ~$0.05 to $0.10 per match | Blitz API / Cognism | Extracts titles and company data. |

### Monetization
Because the privacy architecture precludes selling user telemetry or contact
listings, billing must cover data verification costs directly:
* **Freemium Tier:** 5 free checks per user per month.
* **Pro Tier ($4.99/mo):** Unlimited queries, LinkedIn overlays, deep fraud detection.

---

## Execution Sequence

1. **Sandbox Isolation:** Create accounts on the telecom and B2B enrichment platforms. Extract testing credentials.
2. **Engine Development:** Deploy the FastAPI prototype locally and verify unified JSON responses.
3. **Client Framework Integration:** Configure the mobile codebase to catch call intents and forward anonymized requests.
4. **Launch Testing:** Dial from external business and cell lines to confirm records parse and display within a **< 1.5-second window** before the user decides to accept.
