"""Transient, in-memory lookup cache.

Privacy note: keys are SHA-256 digests of the E.164 number, never the number
itself, and every entry carries a hard expiry. Nothing is written to disk, so a
process restart wipes all record of what was looked up.
"""

import hashlib
import time
from threading import Lock
from typing import Any


class TransientCache:
    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._lock = Lock()
        self._store: dict[str, tuple[float, Any]] = {}

    @staticmethod
    def _key(number: str) -> str:
        return hashlib.sha256(number.encode()).hexdigest()

    def get(self, number: str) -> Any | None:
        key = self._key(number)
        now = time.time()
        with self._lock:
            hit = self._store.get(key)
            if hit is None:
                return None
            expires_at, value = hit
            if expires_at <= now:
                del self._store[key]
                return None
            return value

    def set(self, number: str, value: Any) -> None:
        with self._lock:
            self._store[self._key(number)] = (time.time() + self._ttl, value)

    def purge_expired(self) -> int:
        now = time.time()
        with self._lock:
            stale = [k for k, (exp, _) in self._store.items() if exp <= now]
            for k in stale:
                del self._store[k]
        return len(stale)

    def __len__(self) -> int:
        with self._lock:
            return len(self._store)


class RateLimiter:
    """Fixed-window per-caller limiter. Windows are keyed by a salted hash of the IP."""

    def __init__(self, limit_per_minute: int) -> None:
        self._limit = limit_per_minute
        self._lock = Lock()
        self._hits: dict[str, tuple[int, int]] = {}

    def allow(self, caller_id: str) -> bool:
        if self._limit <= 0:
            return True
        window = int(time.time() // 60)
        key = hashlib.sha256(caller_id.encode()).hexdigest()[:16]
        with self._lock:
            current_window, count = self._hits.get(key, (window, 0))
            if current_window != window:
                current_window, count = window, 0
            if count >= self._limit:
                return False
            self._hits[key] = (current_window, count + 1)
            if len(self._hits) > 10_000:
                self._hits = {
                    k: v for k, v in self._hits.items() if v[0] == window
                }
        return True
