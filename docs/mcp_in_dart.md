# Adding MCP to a Flutter CAD app

## What is MCP and why might we need it?

### MCP in brief

MCP (Model Context Protocol) standardizes how AI applications connect to external tools and data. An agent can use an MCP server to fetch a weather forecast, read documentation, or edit a document. The host application manages the connection and tool execution; the model selects tools and supplies arguments. See the [MCP architecture overview](https://modelcontextprotocol.io/docs/2026-07-28/learn/architecture).

In this article, I will add MCP support to my Flutter CAD app so an agent can edit 3D models.

### When should we add MCP to a Flutter app?

For a mobile news client, a backend MCP server is usually a simpler way to expose articles and search. An app-level server becomes useful when the agent needs local state or functionality available only inside the app. The decision depends on where the required data and operations live.

Desktop editors such as Figma, AutoCAD, Photoshop, and Final Cut Pro are natural candidates. Their workflows contain repeated operations on structured documents. Exposing those operations lets an agent work without reproducing every mouse and keyboard action.

### Why does my CAD app need MCP?

The expected benefits are:

- **Less visual interpretation.** The agent can read feature IDs, dimensions, and parameters as JSON instead of inferring them from screenshots. Compact responses may reduce token use, but large tool descriptions and results also consume context. Savings require measurement.
- **No dependency on window focus.** Tool calls can edit the document without moving the pointer or bringing the app to the foreground. The app must still prevent conflicting edits from the user and agent.
- **Discoverable operations.** MCP exposes tool names, descriptions, and argument schemas through `tools/list`. This documents the operations the server actually exposes. UI features still need explicit MCP handlers. See the [tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).
- **Direct model access.** The agent can address features by ID and pass dimensions directly, avoiding camera movement and repeated selection. This depends on the tools provided; MCP does not add CAD operations by itself.

Computer use can also occupy the user's input devices. In the example below, the agent asks the user to leave the computer untouched:

![Codex asking the user not to use the keyboard, mouse, or trackpad while it controls the app.](images/codex-computer-use.png)

These benefits can reduce interaction overhead. They do not establish that MCP is faster or cheaper for every task. Screenshots remain useful for checking the result.

Even when an agent can operate the UI, MCP may be a useful optimization. Keeping document operations separate from widgets makes it easier to add automation.

## How can we implement MCP in Dart/Flutter?

### Available packages

These are three relevant options. Let's look at them.

| Package | Version | Scope and transports | Main consideration | License |
| --- | --- | --- | --- | --- |
| [`dart_mcp`](https://pub.dev/packages/dart_mcp) | 0.5.2 | Client and server APIs; built-in stdio and custom stream channels. | Maintained in `dart-lang/ai`. Marked experimental; Streamable HTTP and authorization are not built in. | BSD-3-Clause |
| [`mcp_dart`](https://pub.dev/packages/mcp_dart) | 2.4.3 | Client and server APIs; stdio, Streamable HTTP, and custom transports. | Documents support for both 2026-07-28 and earlier protocol revisions, with authentication hooks. | MIT |
| [`mcp_server`](https://pub.dev/packages/mcp_server) | 3.0.0 | Server package; stdio, Streamable HTTP, and legacy SSE. | Server-focused alternative; documents support through 2026-07-28 and requires `dart:io`. | MIT |

`dart_mcp` provides the local stdio transport I need. `mcp_dart` also includes Streamable HTTP and broader protocol-version support, but I will keep this integration local and target a single protocol revision.

### Writing from scratch

Of course, we don't need to write the entire MCP protocol implementation manually; we will ask AI to do that! The decision is similar to choosing whether to use a library or write the code ourselves. We ask questions such as:

- Is the library well supported?
- Does its license fit how we use our app?
- Will migrating away from it be difficult?
- How is it implemented under the hood?
- Can we extend it later?

An AI-written solution has its own advantages: we can inspect the entire implementation, extend it when needed, and choose code and dependencies that fit our licensing requirements. But maintaining its quality and fixing bugs, including security issues, becomes our responsibility. Choose carefully.

### Which approach will we use in the CAD app?

I will build [a custom stdio adapter and local bridge](https://github.com/mishkov/faust_cad_app_2/tree/3b473595f128766e386ccfd543f73780542fccba). I need local access to the running CAD document and a small set of modeling tools. I want to inspect and extend the adapter directly without adding an MCP package dependency, so I will ask AI to generate it and review the result against the specification.

An SDK would save me protocol implementation and maintenance work. I am choosing direct control over this small adapter and accepting responsibility for compatibility, tests, and security fixes. I will keep the CAD operations in separate controllers so I can replace the protocol layer later without rewriting the modeling logic.

I will target the initialization-based **2025-11-25** protocol and expose tools. The latest published revision checked for this article is **2026-07-28**, which replaces that handshake with per-request version and capability metadata. Supporting it would require additional implementation and testing. See [versioning and compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning).

## Implementing MCP in the CAD app

### Connect the agent to the running app

I will connect the agent to the running app through two connections:

```text
Agent host -> stdio MCP adapter -> local WebSocket bridge -> CAD controllers
```

The host launches the [stdio adapter](https://github.com/mishkov/faust_cad_app_2/blob/3b473595f128766e386ccfd543f73780542fccba/bin/faust_mcp.dart) as a subprocess. The adapter reads newline-delimited JSON-RPC messages from stdin and writes responses to stdout. Logs go to stderr, as required by the [stdio transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

The desktop app runs the bridge on `127.0.0.1`. Connections require a generated token; browser Origin headers are rejected. The WebSocket connection is an internal app bridge. The MCP client uses stdio.

The bridge starts when the user enables MCP in Settings. The app must remain running while the agent uses it.

### Define tools and their arguments

The [tool definitions](https://github.com/mishkov/faust_cad_app_2/blob/3b473595f128766e386ccfd543f73780542fccba/lib/automation/automation_tools.dart) include a name, description, and JSON Schema for each tool's arguments.

| Tools | Purpose |
| --- | --- |
| `cad_get_document`, `cad_get_profiles` | Inspect features, revisions, and available sketch regions. |
| `cad_begin`, `cad_finish` | Acquire and release exclusive editing control. |
| `cad_set_sketch` | Create or update points, segments, and circles on a principal plane. |
| `cad_extrude`, `cad_set_extrusion` | Create a linked extrusion or change its distance and direction. |
| `cad_delete_feature`, `cad_undo`, `cad_redo` | Delete a feature or navigate edit history. |
| `cad_render` | Render document bodies with an independent camera. |

Document lengths are millimeters; camera angles are degrees. Descriptions also explain profile selection, revision requirements, and retry behavior. The server validates arguments before applying operations.

I will start with numeric sketch geometry and leave constraint editing outside this version's scope. Tool coverage must be explicit; adding a UI feature does not automatically expose it.

### Handle MCP messages

For the adapter's target revision, the main sequence is:

1. `initialize`: exchange server information, the supported revision, and capabilities.
2. `notifications/initialized`: mark the client ready.
3. `tools/list`: return tool definitions.
4. `tools/call`: validate arguments and dispatch a tool.

The adapter also handles `ping`. This sequence follows the [2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle). A custom implementation must also handle malformed requests, unknown methods, disconnects, and timeouts. An SDK takes over much of this protocol work; it does not implement the CAD commands.

### Apply edits through the document controller

The [automation controller](https://github.com/mishkov/faust_cad_app_2/blob/3b473595f128766e386ccfd543f73780542fccba/lib/automation/automation_controller.dart) uses the document command layer rather than manipulating widgets. Each mutation supplies:

- `sessionId`: the current editing session.
- `expectedRevision`: the document version the command was prepared against.
- `requestId`: an application-level identifier used to detect retries.

The server evaluates a draft before publishing it. Failed operations preserve the previous model and history. Each successful modeling change becomes an undo step.

While the agent owns editing control, human document mutations are blocked. Camera movement and inspection remain available. **Stop AI** revokes the session and prevents an unfinished draft from being published. Disconnects and an idle timeout release the lock.

After a lost response, the client retries with the same application `requestId` and arguments. Within the active session's receipt limit, this returns the stored result instead of repeating the edit. This identifier is separate from the JSON-RPC message ID. After losing the session, inspect the document before issuing new commands.

To build the keyboard shown below, I will create sketches for the enclosure, keycaps, and label outlines, then extrude them. Before each extrusion, I will read the current profiles and use their IDs with the returned revision. After inspecting the model, I will finish the editing session.

### Run the app and configure the client

For this example, I will run the macOS desktop app. With Flutter and the macOS desktop toolchain installed, check out the [source revision used here](https://github.com/mishkov/faust_cad_app_2/tree/3b473595f128766e386ccfd543f73780542fccba) and run these commands from the repository root:

```sh
flutter pub get
flutter run -d macos
```

Open **Settings → AI Integration**, enable MCP, and use **Copy MCP connection**. Supply that endpoint to the adapter:

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

Replace the paths and endpoint. The Dart executable bundled with Flutter works for the adapter. This is an example configuration shape; use the format required by the chosen MCP client. The endpoint contains a secret and should not appear in published logs.

### Read the document through MCP

After initialization, the client can inspect the document with this request. It is formatted for readability; the stdio transport sends it on one line.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "cad_get_document",
    "arguments": {}
  }
}
```

The result includes the model units, current revision, feature IDs, parameters, and evaluation states. The agent can use that information to prepare edits, acquire a session with `cad_begin`, and call the modeling tools.

## Result

With MCP connected, I had the agent model a keyboard using sketches and extrusions. The result has 87 keys on a 19.05 mm pitch, a 360 × 140 mm sloped enclosure, and labels raised 0.35 mm above the keycaps. The saved document snapshot contains 40 features, all evaluated as valid.

These are the top and angled views returned by `cad_render` from the running app:

![Top view of the 87-key keyboard modeled through MCP.](images/mcp-keyboard-top.png)

![Angled view of the keyboard, showing the sloped enclosure and raised labels.](images/mcp-keyboard-angled.png)

The result also reflects the tools I exposed. It uses one gray material because there is no material or color tool. The keycap tops are horizontal at increasing row heights; there is no transform tool to tilt them individually. I saved a replayable MCP recipe and a feature snapshot because native document saving is not exposed through MCP.

## Conclusion

For my CAD app, MCP gives an agent a direct way to inspect the document, create geometry, and render the result. The keyboard demonstrates what the sketch and extrusion tools can produce without driving the UI.

I chose a custom adapter so I can control and extend its implementation. That also makes protocol compatibility and maintenance my responsibility. The next gaps are in the tools I expose: transforms, materials, and native document saving.
