"""Volatile, bounded result cache for single-process stateless diagnostics."""
from copy import deepcopy
import threading
import time
from typing import Any

_lock = threading.RLock()
_results: dict[str, tuple[float, dict[str, Any]]] = {}
_MAX_RESULTS = 100


def _purge_expired(now: float) -> None:
    for run_id in [key for key, (expiry, _) in _results.items() if expiry <= now]:
        _results.pop(run_id, None)


def store_result(run_id: str, result: dict[str, Any], *, ttl_seconds: int) -> bool:
    now = time.monotonic()
    with _lock:
        _purge_expired(now)
        if run_id in _results:
            return False
        if len(_results) >= _MAX_RESULTS:
            _results.pop(min(_results, key=lambda key: _results[key][0]), None)
        _results[run_id] = (now + ttl_seconds, deepcopy(result))
        return True


def get_result(run_id: str) -> dict[str, Any] | None:
    now = time.monotonic()
    with _lock:
        _purge_expired(now)
        item = _results.get(run_id)
        return deepcopy(item[1]) if item else None


def clear_results() -> None:
    with _lock:
        _results.clear()
