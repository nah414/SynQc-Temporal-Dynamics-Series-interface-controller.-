from __future__ import annotations

import asyncio
import importlib
import os
import sys
import warnings
from pathlib import Path
from types import ModuleType


def _append_cached_wheel() -> None:
    """Add a cached httpx wheel to sys.path if present.

    CI can drop httpx wheels into ``backend/synqc_backend/vendor/httpx_wheels`` so this works
    even without outbound package downloads. An environment override is also supported:
    ``SYNQC_HTTPX_VENDOR=/path/to/wheels``.
    """
    override = os.getenv("SYNQC_HTTPX_VENDOR")
    vendor_dir = Path(override) if override else Path(__file__).resolve().parent / "httpx_wheels"
    if not vendor_dir.exists():
        return
    wheels = sorted(vendor_dir.glob("httpx-*.whl"))
    if not wheels:
        return
    wheel_path = str(wheels[-1])
    if wheel_path not in sys.path:
        sys.path.insert(0, wheel_path)


def _ensure_event_loop() -> None:
    """Guarantee an event loop is available for httpx AsyncClient tests."""

    try:
        asyncio.get_running_loop()
        return
    except RuntimeError:
        pass

    try:
        asyncio.get_event_loop()
    except RuntimeError:
        asyncio.set_event_loop(asyncio.new_event_loop())


def load_httpx() -> ModuleType:
    """Return an httpx-compatible module, using a cached wheel or stub fallback."""

    _append_cached_wheel()
    _ensure_event_loop()
    try:
        return importlib.import_module("httpx")
    except ModuleNotFoundError:
        try:
            return importlib.import_module("httpx")
        except ModuleNotFoundError:
            # Fall back to bundled stub so load_test works without internet.
            from . import httpx_stub as httpx  # type: ignore

            warnings.warn(
                "Using bundled httpx_stub; cache an official httpx wheel under "
                "backend/synqc_backend/vendor/httpx_wheels/ or set SYNQC_HTTPX_VENDOR.",
                RuntimeWarning,
                stacklevel=2,
            )
            return httpx
