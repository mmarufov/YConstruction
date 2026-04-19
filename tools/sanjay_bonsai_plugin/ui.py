"""Operators and panels for the YConstruction Bonsai plugin."""

# NOTE: do NOT add `from __future__ import annotations` here.
# Blender registers operator properties by reading `cls.__annotations__`
# at class-definition time; PEP 563 would turn them into strings and
# the registration would silently drop the property.

import os
import tempfile
import time
import zipfile
from typing import Optional
from xml.etree import ElementTree as ET

import bpy

from . import core


# ---------- Operators ----------

class YCON_OT_refresh(bpy.types.Operator):
    bl_idname = "yconstruction.refresh"
    bl_label = "Refresh"
    bl_description = "Poll Supabase for the latest defect list now"

    def execute(self, context):
        core.trigger_refresh_now()
        self.report({"INFO"}, "YConstruction: refresh queued")
        return {"FINISHED"}


class YCON_OT_load_issue(bpy.types.Operator):
    bl_idname = "yconstruction.load_issue"
    bl_label = "Open in Bonsai"
    bl_description = "Download this defect's BCF and open it in Bonsai's BCF panel"

    issue_id: bpy.props.StringProperty(options={"SKIP_SAVE"})

    _future = None
    _dest_path: str = ""
    _timer = None
    _in_flight_claimed: bool = False

    def invoke(self, context, event):
        st = core.state()
        match = next((i for i in st.issues if i.id == self.issue_id), None)
        if match is None:
            self.report({"ERROR"}, "Issue not found in current list")
            return {"CANCELLED"}
        if not match.bcf_path:
            self.report({"ERROR"}, "Issue has no attached BCF yet")
            return {"CANCELLED"}

        self._dest_path = core.cached_bcf_path(match)
        self._future = core.submit_download(match)
        if self._future is None:
            self.report({"ERROR"}, "Could not start download")
            return {"CANCELLED"}
        self._in_flight_claimed = True

        wm = context.window_manager
        self._timer = wm.event_timer_add(0.3, window=context.window)
        wm.modal_handler_add(self)
        self.report({"INFO"}, "Downloading BCF…")
        return {"RUNNING_MODAL"}

    def execute(self, context):
        # When invoked from script (no event), fall through to invoke.
        return self.invoke(context, None)

    def modal(self, context, event):
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        if self._future is None or not self._future.done():
            return {"RUNNING_MODAL"}

        self._cleanup_timer(context)

        try:
            self._future.result()
        except Exception as exc:
            core.state().last_error = f"download: {exc}"
            self.report({"ERROR"}, f"Download failed: {exc}")
            self._release_in_flight()
            return {"CANCELLED"}

        self._release_in_flight()

        try:
            bpy.ops.bim.load_bcf_project(filepath=self._dest_path)
        except Exception as exc:
            self.report({"ERROR"}, f"Bonsai could not open BCF: {exc}")
            return {"CANCELLED"}

        self.report({"INFO"}, f"Loaded {os.path.basename(self._dest_path)}")
        return {"FINISHED"}

    def cancel(self, context):
        self._cleanup_timer(context)
        self._release_in_flight()

    def _cleanup_timer(self, context):
        if self._timer is not None and context.window_manager is not None:
            context.window_manager.event_timer_remove(self._timer)
        self._timer = None

    def _release_in_flight(self):
        if not self._in_flight_claimed:
            return
        self._in_flight_claimed = False
        st = core.state()
        st.in_flight = max(0, st.in_flight - 1)


class YCON_OT_push_reply(bpy.types.Operator):
    bl_idname = "yconstruction.push_reply"
    bl_label = "Push Reply"
    bl_description = "Save the current BCF session and upload it to Supabase"

    @classmethod
    def poll(cls, context):
        # save_bcf_project asserts on a non-None BcfStore; require one here
        # so the button greys out instead of erroring.
        return "bim" in dir(bpy.ops) and hasattr(bpy.ops.bim, "save_bcf_project")

    def execute(self, context):
        tmp_path = os.path.join(
            tempfile.gettempdir(),
            f"yconstruction_reply_{time.strftime('%Y%m%dT%H%M%S')}.bcfzip",
        )
        try:
            bpy.ops.bim.save_bcf_project(filepath=tmp_path)
        except Exception as exc:
            self.report(
                {"ERROR"},
                "Could not save BCF — open an issue via 'Open in Bonsai' first "
                f"({exc})",
            )
            return {"CANCELLED"}

        topic_guid = _extract_first_topic_guid(tmp_path)
        if topic_guid is None:
            self.report({"ERROR"}, "Reply BCF has no Topic GUID — open an issue first")
            return {"CANCELLED"}

        core.submit_upload_reply(topic_guid, tmp_path)
        self.report({"INFO"}, f"Uploading reply for {topic_guid[:8]}…")
        return {"FINISHED"}


def _extract_first_topic_guid(bcf_path: str) -> Optional[str]:
    try:
        with zipfile.ZipFile(bcf_path, "r") as zf:
            for name in zf.namelist():
                if name.endswith("markup.bcf"):
                    with zf.open(name) as f:
                        tree = ET.parse(f)
                    topic = tree.getroot().find("Topic")
                    if topic is not None:
                        return topic.get("Guid")
    except Exception:
        return None
    return None


# ---------- Panels ----------

class YCON_PT_main(bpy.types.Panel):
    bl_label = "YConstruction"
    bl_idname = "YCON_PT_main"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "YConstruction"

    def draw(self, context):
        layout = self.layout
        st = core.state()

        # Status line
        row = layout.row(align=True)
        row.label(text=_status_label(st), icon=_status_icon(st))
        row.operator(YCON_OT_refresh.bl_idname, text="", icon="FILE_REFRESH")

        if st.last_fetched_at:
            layout.label(
                text=f"Last synced {int(time.time() - st.last_fetched_at)}s ago"
            )

        if st.last_error and not st.last_fetch_ok:
            box = layout.box()
            box.alert = True
            box.label(text=st.last_error[:80], icon="ERROR")

        layout.separator()
        layout.operator(YCON_OT_push_reply.bl_idname, icon="EXPORT")


class YCON_PT_issues(bpy.types.Panel):
    bl_label = "Issues"
    bl_idname = "YCON_PT_issues"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "YConstruction"
    bl_parent_id = "YCON_PT_main"

    def draw(self, context):
        layout = self.layout
        st = core.state()

        if not st.issues:
            layout.label(text="No defects yet.")
            return

        for issue in st.issues[:50]:
            box = layout.box()
            header = box.row()
            header.label(
                text=_issue_headline(issue),
                icon=_severity_icon(issue.severity),
            )
            meta = box.row()
            meta.scale_y = 0.8
            meta.label(
                text=f"{issue.reporter} · {_short_ts(issue.timestamp)}"
                + (" · resolved" if issue.resolved else ""),
            )
            op = box.operator(
                YCON_OT_load_issue.bl_idname, icon="IMPORT",
            )
            op.issue_id = issue.id


# ---------- Formatting ----------

def _status_label(st) -> str:
    if st.in_flight:
        return "Syncing…"
    if not st.last_fetch_ok and st.last_error:
        return "Offline / error"
    pending_local = len([i for i in st.issues if not i.synced])
    if pending_local:
        return f"{pending_local} pending on cloud"
    return "All synced"


def _status_icon(st) -> str:
    if st.in_flight:
        return "SORTTIME"
    if not st.last_fetch_ok and st.last_error:
        return "ERROR"
    return "CHECKMARK"


def _severity_icon(sev: str) -> str:
    return {
        "low": "INFO",
        "medium": "QUESTION",
        "high": "ERROR",
        "critical": "CANCEL",
    }.get(sev, "DOT")


def _issue_headline(issue) -> str:
    bits = [
        issue.defect_type or "defect",
        "–",
        issue.storey or "?",
        issue.space or "",
        issue.orientation or "",
        issue.element_type or "",
    ]
    return " ".join(b for b in bits if b).strip()


def _short_ts(ts: str) -> str:
    return (ts or "")[:19].replace("T", " ")


CLASSES = [
    YCON_OT_refresh,
    YCON_OT_load_issue,
    YCON_OT_push_reply,
    YCON_PT_main,
    YCON_PT_issues,
]
