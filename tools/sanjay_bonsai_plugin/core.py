"""
Core state, HTTP, and timer driver for the YConstruction Bonsai plugin.

Design:
- Blender's Python is not thread-safe for bpy.* calls. We use a worker
  thread pool for HTTP only; all bpy mutations happen inside the
  `bpy.app.timers` main-thread tick.
- Polling (default 5s) is simpler and more robust than supabase-py's
  async realtime client inside Blender. Latency is plenty good for
  a human reviewer.
- Uses only stdlib (urllib + concurrent.futures) to keep install trivial.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Optional

import bpy


_TIMER_INTERVAL = 1.0  # main-thread drain cadence
_POLL_BACKOFF_ON_ERROR = 15.0  # seconds


@dataclass
class Issue:
    id: str = ""
    project_id: str = ""
    defect_type: str = ""
    severity: str = ""
    storey: str = ""
    space: Optional[str] = None
    orientation: Optional[str] = None
    element_type: str = ""
    reporter: str = ""
    timestamp: str = ""
    bcf_path: Optional[str] = None
    resolved: bool = False
    synced: bool = True
    updated_at: str = ""

    @classmethod
    def from_row(cls, row: dict) -> "Issue":
        """Construct safely from a PostgREST row that may have NULLs."""
        def s(k: str) -> str:
            v = row.get(k)
            return "" if v is None else str(v)

        def opt_s(k: str) -> Optional[str]:
            v = row.get(k)
            return None if v is None else str(v)

        def b(k: str, default: bool = False) -> bool:
            v = row.get(k)
            return default if v is None else bool(v)

        return cls(
            id=s("id"),
            project_id=s("project_id"),
            defect_type=s("defect_type"),
            severity=s("severity"),
            storey=s("storey"),
            space=opt_s("space"),
            orientation=opt_s("orientation"),
            element_type=s("element_type"),
            reporter=s("reporter"),
            timestamp=s("timestamp"),
            bcf_path=opt_s("bcf_path"),
            resolved=b("resolved", False),
            synced=b("synced", True),
            updated_at=s("updated_at"),
        )


@dataclass
class State:
    issues: list[Issue] = field(default_factory=list)
    last_fetched_at: float = 0.0
    last_fetch_ok: bool = False
    last_error: str = ""
    next_poll_at: float = 0.0
    in_flight: int = 0
    cache_dir: str = ""
    pool: Optional[concurrent.futures.ThreadPoolExecutor] = None
    pending_fetch: Optional[concurrent.futures.Future] = None
    pending_uploads: list[concurrent.futures.Future] = field(default_factory=list)
    log: list[str] = field(default_factory=list)


_STATE: Optional[State] = None


def register_state() -> None:
    global _STATE
    cache_dir = os.path.join(tempfile.gettempdir(), "yconstruction_bcf_cache")
    os.makedirs(cache_dir, exist_ok=True)
    _STATE = State(
        cache_dir=cache_dir,
        pool=concurrent.futures.ThreadPoolExecutor(max_workers=2),
    )


def release_state() -> None:
    global _STATE
    if _STATE is None:
        return
    if _STATE.pool is not None:
        _STATE.pool.shutdown(wait=False, cancel_futures=True)
    _STATE = None


def state() -> State:
    assert _STATE is not None, "State accessed before register_state()"
    return _STATE


# ---------- preferences access ----------

def prefs() -> Any:
    return bpy.context.preferences.addons[__package__].preferences


def supabase_base() -> str:
    return prefs().supabase_url.rstrip("/")


def auth_headers() -> dict[str, str]:
    key = prefs().supabase_anon_key
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }


# ---------- HTTP helpers (run in worker thread) ----------

def _http_request(
    url: str,
    method: str = "GET",
    headers: Optional[dict[str, str]] = None,
    data: Optional[bytes] = None,
    timeout: float = 15.0,
) -> tuple[int, bytes]:
    req = urllib.request.Request(url, method=method, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _fetch_issues_worker(
    base: str,
    headers: dict[str, str],
    project_id: str,
) -> list[Issue]:
    query = urllib.parse.urlencode({
        "project_id": f"eq.{project_id}",
        "order": "updated_at.desc",
        "select": ",".join([
            "id", "project_id", "defect_type", "severity",
            "storey", "space", "orientation", "element_type",
            "reporter", "timestamp", "bcf_path", "resolved",
            "synced", "updated_at",
        ]),
    })
    url = f"{base}/rest/v1/project_changes?{query}"
    status, body = _http_request(url, headers=headers)
    if status >= 400:
        raise RuntimeError(f"fetch {status}: {body[:200].decode('utf-8', 'replace')}")
    rows = json.loads(body.decode("utf-8"))
    return [Issue.from_row(row) for row in rows]


def _download_bcf_worker(
    base: str,
    headers: dict[str, str],
    bucket: str,
    object_path: str,
    dest: str,
) -> str:
    url = f"{base}/storage/v1/object/{bucket}/{object_path}"
    status, body = _http_request(url, headers=headers, timeout=60.0)
    if status >= 400:
        raise RuntimeError(f"download {status}: {body[:200].decode('utf-8', 'replace')}")
    with open(dest, "wb") as f:
        f.write(body)
    return dest


def _upload_bcf_worker(
    base: str,
    headers: dict[str, str],
    bucket: str,
    object_path: str,
    source: str,
) -> str:
    url = f"{base}/storage/v1/object/{bucket}/{object_path}"
    with open(source, "rb") as f:
        data = f.read()
    hdrs = {**headers, "Content-Type": "application/zip", "x-upsert": "true"}
    status, body = _http_request(url, method="POST", headers=hdrs, data=data, timeout=60.0)
    if status >= 400:
        raise RuntimeError(f"upload {status}: {body[:200].decode('utf-8', 'replace')}")
    return object_path


def _bump_row_worker(
    base: str,
    headers: dict[str, str],
    row_id: str,
    fields: dict[str, Any],
) -> None:
    url = f"{base}/rest/v1/project_changes?id=eq.{urllib.parse.quote(row_id)}"
    hdrs = {**headers, "Content-Type": "application/json", "Prefer": "return=minimal"}
    data = json.dumps(fields).encode("utf-8")
    status, body = _http_request(url, method="PATCH", headers=hdrs, data=data)
    if status >= 400:
        raise RuntimeError(f"bump {status}: {body[:200].decode('utf-8', 'replace')}")


# ---------- main-thread tick ----------

def _log(msg: str) -> None:
    st = state()
    ts = time.strftime("%H:%M:%S")
    st.log.append(f"[{ts}] {msg}")
    del st.log[:-20]  # keep last 20
    print(f"[YConstruction] {msg}")


def _schedule_fetch_if_due() -> None:
    st = state()
    if st.pending_fetch is not None and not st.pending_fetch.done():
        return
    now = time.time()
    if now < st.next_poll_at:
        return
    try:
        p = prefs()
    except (KeyError, AttributeError):
        return
    if not p.supabase_url or not p.supabase_anon_key:
        return

    assert st.pool is not None
    st.in_flight += 1
    st.pending_fetch = st.pool.submit(
        _fetch_issues_worker,
        supabase_base(),
        auth_headers(),
        p.project_id,
    )


def _drain_pending_fetch() -> None:
    st = state()
    if st.pending_fetch is None or not st.pending_fetch.done():
        return
    st.in_flight = max(0, st.in_flight - 1)
    try:
        issues = st.pending_fetch.result()
        st.issues = issues
        st.last_fetch_ok = True
        st.last_error = ""
        st.last_fetched_at = time.time()
        try:
            p = prefs()
            st.next_poll_at = time.time() + p.poll_seconds
        except Exception:
            st.next_poll_at = time.time() + 5
    except Exception as exc:
        st.last_fetch_ok = False
        st.last_error = str(exc)
        st.next_poll_at = time.time() + _POLL_BACKOFF_ON_ERROR
        _log(f"fetch error: {exc}")
    finally:
        st.pending_fetch = None
        _request_redraw()


def _drain_uploads() -> None:
    st = state()
    remaining = []
    for fut in st.pending_uploads:
        if fut.done():
            st.in_flight = max(0, st.in_flight - 1)
            try:
                fut.result()
            except Exception as exc:
                st.last_error = f"upload: {exc}"
                _log(f"upload error: {exc}")
            else:
                _log("upload ok")
        else:
            remaining.append(fut)
    if len(remaining) != len(st.pending_uploads):
        st.pending_uploads = remaining
        _request_redraw()


def _request_redraw() -> None:
    wm = getattr(bpy.context, "window_manager", None)
    if wm is None:
        return
    for window in wm.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                area.tag_redraw()


def _tick() -> float:
    try:
        _drain_pending_fetch()
        _drain_uploads()
        _schedule_fetch_if_due()
    except Exception as exc:
        _log(f"tick error: {exc}")
    return _TIMER_INTERVAL


def start_timer() -> None:
    if bpy.app.timers.is_registered(_tick):
        return
    bpy.app.timers.register(_tick, first_interval=0.5, persistent=True)


def stop_timer() -> None:
    if bpy.app.timers.is_registered(_tick):
        bpy.app.timers.unregister(_tick)


# ---------- high-level ops called from operators ----------

def cached_bcf_path(issue: Issue) -> str:
    fname = os.path.basename(issue.bcf_path) if issue.bcf_path else f"{issue.id}.bcfzip"
    return os.path.join(state().cache_dir, fname)


def trigger_refresh_now() -> None:
    st = state()
    st.next_poll_at = 0
    _schedule_fetch_if_due()


def submit_download(issue: Issue) -> Optional[concurrent.futures.Future]:
    st = state()
    if st.pool is None or not issue.bcf_path:
        return None
    p = prefs()
    dest = cached_bcf_path(issue)
    st.in_flight += 1
    return st.pool.submit(
        _download_bcf_worker,
        supabase_base(),
        auth_headers(),
        p.issues_bucket,
        issue.bcf_path,
        dest,
    )


def submit_upload_reply(topic_guid: str, local_bcf_path: str) -> concurrent.futures.Future:
    st = state()
    assert st.pool is not None
    p = prefs()
    stamp = time.strftime("%Y%m%dT%H%M%S")
    object_path = f"{p.project_id}/{topic_guid}-reply-{stamp}.bcfzip"

    def do_upload_and_bump() -> None:
        _upload_bcf_worker(
            supabase_base(), auth_headers(),
            p.issues_bucket, object_path, local_bcf_path,
        )
        _bump_row_worker(
            supabase_base(), auth_headers(), topic_guid,
            {"bcf_path": object_path, "synced": False},
        )

    fut = st.pool.submit(do_upload_and_bump)
    st.pending_uploads.append(fut)
    st.in_flight += 1
    return fut
