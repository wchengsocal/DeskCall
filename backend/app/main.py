"""DeskCall lookup API.

Waterfall: transient cache -> telecom/CNAM registry -> B2B enrichment.
No phone number, IP, or result is ever persisted to disk.
"""

import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse

from .cache import RateLimiter, TransientCache
from .config import Settings, get_settings
from .directory import SpamDirectory
from .models import (
    CallerProfile,
    DirectoryResponse,
    LookupRequest,
    ReportRequest,
)
from .providers import b2b_enrich, mock_lookup, telecom_lookup

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("deskcall")

settings = get_settings()
cache = TransientCache(settings.cache_ttl_seconds)
limiter = RateLimiter(settings.rate_limit_per_minute)
spam_directory = SpamDirectory()


@asynccontextmanager
async def lifespan(app: FastAPI):
    timeout = httpx.Timeout(settings.upstream_timeout_seconds)
    async with httpx.AsyncClient(timeout=timeout) as client:
        app.state.http = client
        mode = "MOCK" if settings.mock_mode else "LIVE"
        log.info(
            "DeskCall API up in %s mode (telecom=%s b2b=%s)",
            mode,
            settings.telecom_configured,
            settings.b2b_configured,
        )
        yield


app = FastAPI(
    title="DeskCall Lookup API",
    version="1.0.0",
    description="Privacy-first caller identification backend.",
    lifespan=lifespan,
)


def client_fingerprint(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def require_client(
    request: Request,
    x_deskcall_key: str | None = Header(default=None),
    cfg: Settings = Depends(get_settings),
) -> str:
    allowed = cfg.allowed_client_keys
    if allowed and x_deskcall_key not in allowed:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid client key"
        )
    fingerprint = client_fingerprint(request)
    if not limiter.allow(fingerprint):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate limit exceeded, try again in a minute",
        )
    return fingerprint


@app.get("/health")
async def health(cfg: Settings = Depends(get_settings)) -> dict:
    return {
        "status": "ok",
        "mode": "mock" if cfg.mock_mode else "live",
        "telecom_configured": cfg.telecom_configured,
        "b2b_configured": cfg.b2b_configured,
        "cached_entries": len(cache),
        "directory": spam_directory.stats(),
    }


@app.post("/api/v1/lookup", response_model=CallerProfile)
async def lookup(
    payload: LookupRequest,
    request: Request,
    _fingerprint: str = Depends(require_client),
    cfg: Settings = Depends(get_settings),
) -> CallerProfile:
    number = payload.phone_number

    cached = cache.get(number)
    if cached is not None:
        profile = CallerProfile(**cached)
        profile.cached = True
        profile.spam_score = max(profile.spam_score, spam_directory.spam_score(number))
        return profile

    profile = CallerProfile(phone_number=number)

    if cfg.mock_mode or not cfg.telecom_configured:
        profile = mock_lookup(number, profile)
    else:
        client: httpx.AsyncClient = request.app.state.http
        profile = await telecom_lookup(client, cfg, number, profile)
        # Only spend B2B credits once the carrier step produced an identity.
        if cfg.b2b_configured and profile.name != "Unknown Caller":
            profile = await b2b_enrich(client, cfg, number, profile)

    profile.spam_score = max(profile.spam_score, spam_directory.spam_score(number))
    cache.set(number, profile.model_dump())
    return profile


@app.post("/api/v1/report")
async def report_spam(
    payload: ReportRequest,
    fingerprint: str = Depends(require_client),
) -> dict:
    count = spam_directory.report(payload.phone_number, fingerprint)
    return {"reports": count, "directory_version": spam_directory.version()}


@app.get("/api/v1/directory", response_model=DirectoryResponse)
async def directory() -> DirectoryResponse:
    """Blocklist for the Call Directory extension.

    Deliberately unauthenticated and identity-free: the extension fetches it
    without sending anything about the device or the user.
    """
    return DirectoryResponse(
        version=spam_directory.version(),
        blocked=spam_directory.blocked_numbers(),
        identified=[],
    )


@app.post("/api/v1/cache/purge")
async def purge_cache(_fingerprint: str = Depends(require_client)) -> dict:
    return {"purged": cache.purge_expired(), "remaining": len(cache)}


@app.exception_handler(ValueError)
async def value_error_handler(_request: Request, exc: ValueError) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": str(exc)})
