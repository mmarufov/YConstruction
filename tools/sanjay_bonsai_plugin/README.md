# YConstruction Sync — Bonsai (Blender) plugin

Lives as a sidebar panel inside Blender. Shows a live list of defects from
Supabase, loads them into Bonsai's BCF panel with one click, and pushes replies
back the same way.

No separate terminal process. No folder watching.

## What Sanjay installs

### Step 1 — Blender 4.2+

Download from [blender.org](https://www.blender.org) and install.

### Step 2 — Bonsai add-on inside Blender

- Open Blender → **Edit → Preferences → Get Extensions**.
- Search "Bonsai" → click **Install**.
- Close Preferences.

### Step 3 — This plugin

The plugin folder in this repo is `tools/sanjay_bonsai_plugin`. Install it as
a Blender **Extension** (recommended, Blender 4.2+):

1. On his Mac:
   ```bash
   cd /path/to/yconstruction/tools
   zip -r yconstruction_sync.zip sanjay_bonsai_plugin
   ```
2. In Blender → **Edit → Preferences → Get Extensions**.
3. Click the dropdown arrow next to *Install*, choose **Install from Disk**.
4. Pick `yconstruction_sync.zip`.
5. Enable the "YConstruction Sync (Bonsai)" entry.

That's it. Defaults are already filled in for the demo Supabase project.

### Step 4 — Load the model once per session

In Blender → `File → Open` → pick `duplex.ifc`. Bonsai imports it. This only
has to happen at the start of each session.

## Using it

1. Press `N` to open the sidebar. Click the **YConstruction** tab.
2. **Status line** shows green "All synced" / yellow / red, plus last-synced
   age and any error.
3. **Issues** sub-panel lists every defect from the phone. Each row has:
   - Defect type + location (storey / space / orientation / element)
   - Reporter + timestamp
   - **"Open in Bonsai"** button → downloads the BCF (hidden cache in the
     OS temp dir) and calls Bonsai's built-in `bim.load_bcf_project`. The
     topic appears in Bonsai's own BCF Topics panel with photo + transcripts
     + camera viewpoint.
4. Review / comment / change status in Bonsai's BCF Topics UI (standard Bonsai).
5. Hit **"Push Reply"** on the main panel. The plugin:
   - Calls `bim.save_bcf_project` to a temp file.
   - Reads the Topic GUID from the saved BCF.
   - Uploads to `issues/<project_id>/<guid>-reply-<timestamp>.bcfzip`.
   - Bumps the `project_changes` row so phones' realtime subscription fires.

## Settings

*Edit → Preferences → Add-ons →* **YConstruction Sync** (expand). All fields
have sensible defaults already filled in for the demo Supabase project:

| Field | Default |
|---|---|
| Supabase URL | `https://ammmjwpvlqugolnufdbg.supabase.co` |
| Anon / Publishable key | `sb_publishable_…` (from iOS plist) |
| Project ID | `duplex-demo-001` |
| Issues bucket | `issues` |
| Poll every (s) | `5` |

## How it works under the hood

- **Polling, not WebSocket.** Supabase's realtime client (`supabase-py`)
  requires asyncio and extra packages; Blender's bundled Python can't install
  those reliably. 5-second polling via `bpy.app.timers.register` gives you
  "live enough" latency without threading bugs.
- **HTTP in a worker thread, mutations on main thread.** Blender's `bpy`
  API isn't thread-safe, so HTTP calls run in a tiny `ThreadPoolExecutor`.
  When a request finishes, the next timer tick drains the result on the
  main thread before touching panels or operators.
- **Cache dir:** `$TMPDIR/yconstruction_bcf_cache/`. Cleaned by the OS at
  boot. Sanjay never sees raw files.
- **Bonsai integration:** purely via `bpy.ops.bim.load_bcf_project(filepath=…)`
  and `bpy.ops.bim.save_bcf_project(filepath=…)`. Nothing about the Bonsai
  BCF UI needs to change.

## Files

```
sanjay_bonsai_plugin/
  __init__.py             # entry, AddonPreferences, register/unregister
  blender_manifest.toml   # Blender 4.2+ extension metadata
  core.py                 # state + HTTP + bpy.app.timers tick
  ui.py                   # operators + sidebar panels
  README.md               # this file
```

## Limits / future work

- **Polling latency.** If you need strict realtime, swap the polling tick
  for a WebSocket thread using `supabase-py` + `acreate_client`, and push
  events into the same drain queue. Doable but adds install steps.
- **No reply comment schema.** Right now a push just re-uploads the BCF and
  updates `updated_at`. The BCF itself carries Sanjay's comment (Bonsai
  writes it into `markup.bcf`). If you want to mirror the comment text as a
  structured column, add an `architect_comment` column and PATCH it from
  `submit_upload_reply`.
- **Anon key only.** All traffic uses the iOS app's publishable key, scoped
  to `duplex-demo-001` via Supabase RLS. Fine for demo. For prod, give
  Sanjay a separate user account and tighten the policies.
