"""Upstream data providers for the lookup waterfall.

Every provider is best-effort: a failure or timeout returns an empty dict and
the waterfall continues with whatever the earlier steps produced.
"""

import hashlib
import logging

import httpx

from .config import Settings
from .models import CallerProfile

log = logging.getLogger("deskcall.providers")

MOCK_DIRECTORY: dict[str, dict] = {
    "+14155551234": {
        "name": "Dana Whitfield",
        "title": "VP of Partnerships",
        "company": "Northline Freight",
        "linkedin_url": "https://www.linkedin.com/in/example-dana",
        "line_type": "mobile",
        "carrier": "Verizon Wireless",
    },
    "+12125558899": {
        "name": "Harrow & Finch LLP",
        "title": "Business",
        "company": "Harrow & Finch LLP",
        "line_type": "landline",
        "carrier": "Verizon",
    },
    "+18005559999": {
        "name": "Auto Warranty Services",
        "title": "Robocall",
        "company": "N/A",
        "line_type": "voip",
        "spam_score": 92,
    },
}


def mock_lookup(number: str, profile: CallerProfile) -> CallerProfile:
    """Deterministic offline data so the app is fully usable without paid keys."""
    record = MOCK_DIRECTORY.get(number)
    if record:
        for field, value in record.items():
            setattr(profile, field, value)
        profile.source = "mock"
        return profile

    # Derive a stable pseudo-identity so arbitrary test numbers still render.
    digest = hashlib.sha256(number.encode()).hexdigest()
    if int(digest[:2], 16) % 4 == 0:
        profile.spam_score = 70 + int(digest[2:4], 16) % 30
        profile.name = "Likely Spam"
        profile.title = "Reported by users"
        profile.line_type = "voip"
    else:
        profile.line_type = ["mobile", "landline", "voip"][int(digest[4:6], 16) % 3]
    profile.source = "mock"
    return profile


async def telecom_lookup(
    client: httpx.AsyncClient, settings: Settings, number: str, profile: CallerProfile
) -> CallerProfile:
    """Step 2 of the waterfall: carrier / CNAM registry."""
    url = (
        f"https://lookups.twilio.com/v2/PhoneNumbers/{number}"
        "?Fields=caller_name,line_type_intelligence"
    )
    try:
        resp = await client.get(
            url, auth=(settings.twilio_account_sid, settings.twilio_auth_token)
        )
    except httpx.HTTPError as exc:
        log.warning("telecom lookup failed: %s", type(exc).__name__)
        return profile

    if resp.status_code != 200:
        log.warning("telecom lookup returned %s", resp.status_code)
        return profile

    data = resp.json()
    line = data.get("line_type_intelligence") or {}
    if line.get("type"):
        profile.line_type = line["type"]
    if line.get("carrier_name"):
        profile.carrier = line["carrier_name"]

    cnam = data.get("caller_name") or {}
    if cnam.get("caller_name"):
        profile.name = cnam["caller_name"]
        if cnam.get("caller_type") == "BUSINESS":
            profile.company = cnam["caller_name"]
            profile.title = "Business"
    profile.source = "telecom"
    return profile


async def b2b_enrich(
    client: httpx.AsyncClient, settings: Settings, number: str, profile: CallerProfile
) -> CallerProfile:
    """Step 3 of the waterfall: professional / B2B enrichment."""
    headers = {"x-api-key": settings.b2b_api_key, "Content-Type": "application/json"}
    try:
        resp = await client.post(
            settings.b2b_base_url, json={"phone": number}, headers=headers
        )
    except httpx.HTTPError as exc:
        log.warning("b2b enrichment failed: %s", type(exc).__name__)
        return profile

    if resp.status_code != 200:
        log.warning("b2b enrichment returned %s", resp.status_code)
        return profile

    data = resp.json()
    # Providers vary; accept the common shapes without exploding on absence.
    person = data.get("person") or data.get("data") or data
    if person.get("full_name") or person.get("name"):
        profile.name = person.get("full_name") or person["name"]
    if person.get("title") or person.get("job_title"):
        profile.title = person.get("title") or person["job_title"]
    company = person.get("company")
    if isinstance(company, dict):
        profile.company = company.get("name", profile.company)
    elif isinstance(company, str) and company:
        profile.company = company
    if person.get("linkedin_url"):
        profile.linkedin_url = person["linkedin_url"]
    profile.source = "telecom+b2b" if profile.source == "telecom" else "b2b"
    return profile
