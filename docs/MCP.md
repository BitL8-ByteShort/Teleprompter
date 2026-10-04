# Add scripts with MCP

Requires Teleprompter **1.2.0 or later**. Install the
[current public preview](https://github.com/BitL8-ByteShort/Teleprompter/releases/tag/v1.2.1-public-preview.1)
or build the source with `./script/build_and_run.sh --verify`.

## Connect your agent

The app includes its own MCP server. Run the executable inside the app bundle
with `--mcp`; no Node.js, Python, or separate server install is needed to use it.
The app and your agent must run under the same Mac user account.

For Codex, with the app installed in Applications:

```sh
codex mcp add teleprompter -- "/Applications/Teleprompter.app/Contents/MacOS/Teleprompter" --mcp
```

Start a new agent session so it loads the connection. To disconnect it later:

```sh
codex mcp remove teleprompter
```

For clients that use an `mcpServers` JSON configuration:

```json
{
  "mcpServers": {
    "teleprompter": {
      "command": "/Applications/Teleprompter.app/Contents/MacOS/Teleprompter",
      "args": ["--mcp"]
    }
  }
}
```

If you rename the app or build from source, replace the command with your app
bundle's full executable path. For a source build, that's
`/absolute/path/to/Teleprompter/build/Build/Products/Debug/Teleprompter.app/Contents/MacOS/Teleprompter`.
Check the version under **Teleprompter → About Teleprompter** before connecting.

Discovery doesn't open the app. The first script request opens it in the
background if needed. Closing the MCP connection stops the helper; the normal
app stays open.

## Tools

`add_script` creates a new saved script:

```json
{"title": "Episode 2", "text": "Here's the opening.\n\nHere's the next paragraph."}
```

It returns the actual saved title and UUID. Existing scripts aren't overwritten.
Adding during a take keeps the current editor, reading position, and playback
state, including a pending countdown or scroll resume. If the library is empty,
the new script becomes the selected script and remains stopped.

Titles must contain text and be at most 200 characters. Script text can be empty
and is limited to 500,000 UTF-8 bytes. Text is stored literally, including
paragraphs, quotes, Unicode, and anything that looks like a command.

`list_scripts` returns saved script metadata. Optional arguments:

```json
{"query": "Episode", "offset": 0, "limit": 20}
```

Search checks names and saved text. The default page has up to 50 items; the
maximum is 100. Use `nextOffset`, when returned, to request the next page.
Trash and full script text aren't returned. The response also reports the active
script ID and whether a take is running.

`open_script` takes an ID returned by either tool:

```json
{"script_id": "00000000-0000-0000-0000-000000000000"}
```

This is an explicit selection change. It saves current edits, pauses playback,
and restores that script's saved position. It never starts reading or captures
audio. Missing IDs and scripts in Trash return an error without changing the
current take.

## Privacy and save failures

The GUI app owns every library write. The helper sends requests over a local
Unix socket restricted to your Mac user account. There is no TCP listener or
cloud service in this connection. Grant the connection only to clients you want
to access your saved script metadata and add or open scripts. An agent client
may use its own cloud model; its privacy settings still apply.

A successful add means the app saved the new script and any pending edits to
the current script in one atomic library write. Save failures return tool errors
and preserve the current library and take. An unreadable library blocks agent
access so the original file stays untouched.

Each successful `add_script` call creates a separate script. If a connection
drops after sending an add, list scripts before retrying: the save may have
finished even though the reply was lost. The helper doesn't automatically retry
a request after sending it.

## Troubleshooting and testing

If tools are missing, check the client path and app version, then start a fresh
agent session. If agent access is unavailable, quit older Teleprompter copies
and open the new build. A second GUI instance can't own the same connection.
The editor displays connection errors and the most recent agent add/open.

From the repository root:

```sh
swift test --filter MCPTests
./script/check_library_integration.sh
python3 script/check_mcp.py
```

The final command uses the actual app executable and an isolated AppModel host
with temporary storage and silent speech doubles. It tests stdio framing,
discovery, add/list/open, Unicode, pagination, save failures, playback
preservation, and clean shutdown without touching your scripts or microphone.
Python is needed for this developer test only.
