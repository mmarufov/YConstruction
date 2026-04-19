bl_info = {
    "name": "YConstruction Sync (Bonsai)",
    "author": "YConstruction",
    "version": (0, 1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > YConstruction",
    "description": "Live two-way sync of BCF defect topics between the YConstruction iOS app (via Supabase) and Bonsai.",
    "category": "System",
}

import bpy

from . import core
from . import ui


class YConstructionPreferences(bpy.types.AddonPreferences):
    bl_idname = __package__

    supabase_url: bpy.props.StringProperty(
        name="Supabase URL",
        default="https://ammmjwpvlqugolnufdbg.supabase.co",
    )
    supabase_anon_key: bpy.props.StringProperty(
        name="Anon / Publishable key",
        default="sb_publishable_Pp5gr7p2jxvRVJf5QBnLkw_5c4ctOTV",
        subtype="PASSWORD",
    )
    project_id: bpy.props.StringProperty(
        name="Project ID",
        default="duplex-demo-001",
    )
    issues_bucket: bpy.props.StringProperty(
        name="Issues bucket",
        default="issues",
    )
    poll_seconds: bpy.props.IntProperty(
        name="Poll every (s)",
        default=5,
        min=2,
        max=120,
    )

    def draw(self, context):
        layout = self.layout
        for prop in ("supabase_url", "supabase_anon_key", "project_id", "issues_bucket", "poll_seconds"):
            layout.prop(self, prop)


_CLASSES = [YConstructionPreferences, *ui.CLASSES]


def register():
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    core.register_state()
    core.start_timer()


def unregister():
    core.stop_timer()
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)
    core.release_state()
