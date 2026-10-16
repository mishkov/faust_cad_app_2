# Local MCP control

Faust CAD 2 exposes the running document through `bin/faust_mcp.dart`, a stdio
MCP adapter. It connects to a token-protected WebSocket bridge bound only to
127.0.0.1. No cloud service, API key, or additional package is required.
The adapter implements the 2025-11-25 MCP lifecycle and tools capability.

## Start and connect

Run the desktop app, click **Enable MCP**, then **Copy MCP connection**. This
copies a local endpoint containing a randomly generated connection token. Keep
the endpoint private. It remains valid until the app closes. A second app cannot
silently take over an occupied port.

Configure an MCP client with this command and environment (replace both paths
and the endpoint):

```json
{
  "mcpServers": {
    "faust-cad": {
      "command": "/absolute/path/to/dart",
      "args": ["run", "/absolute/path/to/faust_cad_app_2/bin/faust_mcp.dart"],
      "env": {
        "FAUST_CAD_ENDPOINT": "ws://127.0.0.1:47831/COPIED_CONNECTION_TOKEN"
      }
    }
  }
}
```

The Dart executable bundled with Flutter works. The app must remain running.
This JSON describes a generic MCP client configuration; client-specific setup
may use different configuration syntax. The adapter writes only MCP messages to
stdout and diagnostics to stderr.

For repeatable development, supply a token of at least 16 ASCII letters, numbers,
hyphens or underscores, and optionally a different port:

```sh
flutter run -d macos --dart-define=FAUST_MCP_TOKEN=local-development-token --dart-define=FAUST_MCP_PORT=47831
```

This opts into starting the bridge at launch. Ordinary launches require the
Enable MCP button. Browser origins are rejected, including local browser pages.
The web/widget-preview build has no network bridge. The macOS release app has
the network-server sandbox entitlement, matching the existing debug entitlement.

## Tools and coordinates

| Tool | Behavior |
| --- | --- |
| `cad_get_document` | Features, parameters, semantic outputs, revision, history. |
| `cad_begin` / `cad_finish` | Acquire/release exclusive editing. |
| `cad_set_sketch` | Create/update points, shared-endpoint lines, circles on XY/XZ/YZ. |
| `cad_get_profiles` | Current bounded regions, material areas and hole counts. |
| `cad_extrude` | New linked extrusion from current region IDs. |
| `cad_set_extrusion` | Edit distance and direction while preserving references. |
| `cad_delete_feature` | Delete a feature when the remaining model stays valid. |
| `cad_undo` / `cad_redo` | One document history step. |
| `cad_render` | PNG of current bodies using an independent inspection camera. |

All lengths are **millimetres**. Camera yaw and pitch are **degrees**.
Principal plane conventions are inherited from `PlanarFrame`: XY has normal +Z,
XZ has normal -Y, and YZ has normal +X. Extrusion starts at the sketch plane and
follows its normal; `reverse` flips that direction. Geometry never depends on
the user's viewport. The inspection camera can specify its own target, distance,
yaw, pitch and image dimensions. Without arguments, it fits document bodies.
It excludes viewer fixtures, diagnostic geometry and sketches.

Get the actual schemas through `tools/list`. Example sketch arguments, in
addition to the mutation fields below:

```json
{
  "featureId": "washer-sketch",
  "plane": "xy",
  "points": [{"id": "center", "x": 0, "y": 0}],
  "segments": [],
  "circles": [
    {"id": "outer", "center": "center", "radius": 10},
    {"id": "bore", "center": "center", "radius": 2.5}
  ]
}
```

Use stable entity IDs on updates; deleted identities cannot be reused for
different entities. This first interface supplies numeric geometry. Existing
constraints on an updated sketch remain in force; creating/editing constraints
through MCP is deferred.

## Editing, cancellation and retry rules

1. Call `cad_begin`; retain the returned `sessionId` and `revision`.
2. Each mutation supplies `sessionId`, a unique `requestId`, and
   `expectedRevision`. A successful call returns the current document.
3. Each accepted modeling operation is a separate undo entry. Reading,
   rendering, beginning/finishing, failed operations and unchanged definitions
   add no history entries.
4. Before extrusion, call `cad_get_profiles`, choose material region IDs and
   use its revision. A region with `holeCount: 1` preserves a bore. Also selecting
   the bore disk fills the hole.
5. Call `cad_finish` in a finally step, including after a recoverable error.

The document controller enforces exclusive mutation authority, covering human
controls, shortcuts, and other automation clients. Inspection, selection, camera
orbit/pan/zoom, and **Stop AI** remain available. Human sketch/extrusion editing
or an open modal dialog prevents AI control from starting.

Draft geometry is evaluated in a worker isolate and published only if all
features remain valid and the same session/revision is still current. Failure
leaves the prior model, revision, undo and redo history untouched and returns
diagnostics. **Stop AI** revokes the session immediately; an in-flight worker
may finish computing but cannot publish. Completed steps remain. New sessions
require **Re-enable AI** after Stop. A dropped bridge connection or five minutes
without an editing call releases the lock. A process that remains connected but
forgets to finish therefore cannot retain control indefinitely.

After a lost response, retry using the **same request ID and arguments**. The
session retains receipts (including failures) for up to 512 operations. A reused
ID with different arguments is rejected. After session loss, inspect the current
document and begin a fresh session rather than replaying old commands. An
intentional alternative attempt uses a new ID and the current revision.

Inputs are bounded to 64 features, 256 points/segments and 16 circles per supplied
sketch, 32 selected regions and 1024-pixel images. These are demonstration limits,
not general CAD performance guarantees. General solid booleans, motion checks,
native document persistence and STL/3MF export are outside this milestone.

## Gear demonstration

From the repository root, with the app running:

```sh
FAUST_CAD_ENDPOINT=ws://127.0.0.1:47831/COPIED_CONNECTION_TOKEN dart run tool/mcp_gear_demo.dart
```

The demo uses the real stdio MCP adapter to create two 24-tooth polygon profiles,
each with an exact **5 mm bore**, at **(0, 0)** and **(30, 0)** on XY, then
extrudes each to **Z = 5 mm**. The second profile has a half-tooth phase offset.
Tapered teeth and deliberately generous gaps illustrate meshing. The helper is
client-side example geometry, not a special app gear API or an involute design.
The bore is modeled at exactly the requested diameter; physical shaft clearance
has not been calibrated to a printer.

The four creation operations remain individually undoable. The independent
camera image is saved to `build/mcp_gears.png`. Current main starts empty.
Optional `--replace-demo-cubes` removes the old demo's `cube-a`/`cube-b` features
when they are still cube features, as separate undo steps. Other geometry stays.
The regular viewer's ground grid is not a document feature.

Verification:

```sh
flutter analyze
flutter test
```
