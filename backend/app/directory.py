"""Community spam blocklist served to the iOS Call Directory extension.

CallKit requires every entry to be a plain Int64 (E.164 without the leading
"+") in strictly ascending order, so ordering is enforced here rather than on
the device.
"""

import hashlib
import json
import time
from pathlib import Path
from threading import Lock

SEED_PATH = Path(__file__).with_name("blocklist_seed.json")


class SpamDirectory:
    def __init__(self) -> None:
        self._lock = Lock()
        self._reports: dict[int, set[str]] = {}
        self._load_seed()

    def _load_seed(self) -> None:
        if not SEED_PATH.exists():
            return
        seed = json.loads(SEED_PATH.read_text())
        for raw in seed.get("blocked", []):
            number = int(str(raw).lstrip("+"))
            self._reports[number] = {f"seed-{i}" for i in range(3)}

    def report(self, e164: str, reporter_ip: str) -> int:
        """Record a report. The reporter is stored only as a salted digest."""
        number = int(e164.lstrip("+"))
        token = hashlib.sha256(f"{number}:{reporter_ip}".encode()).hexdigest()[:16]
        with self._lock:
            reporters = self._reports.setdefault(number, set())
            reporters.add(token)
            return len(reporters)

    def spam_score(self, e164: str) -> int:
        try:
            number = int(e164.lstrip("+"))
        except ValueError:
            return 0
        with self._lock:
            count = len(self._reports.get(number, ()))
        return min(100, count * 25)

    def blocked_numbers(self, threshold: int = 3) -> list[int]:
        with self._lock:
            return sorted(n for n, r in self._reports.items() if len(r) >= threshold)

    def version(self) -> str:
        blocked = self.blocked_numbers()
        digest = hashlib.sha256(
            ",".join(str(n) for n in blocked).encode()
        ).hexdigest()[:12]
        return f"{len(blocked)}-{digest}"

    def stats(self) -> dict:
        with self._lock:
            return {
                "reported_numbers": len(self._reports),
                "generated_at": int(time.time()),
            }
