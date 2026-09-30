#!/usr/bin/env python3
"""Exercise the app's actual stdio executable against an isolated real AppModel."""
import argparse
import json
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent


class Client:
    def __init__(self, executable, socket_path):
        self.process = subprocess.Popen([str(executable), '--mcp', '--mcp-socket', str(socket_path)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.next_id = 0

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False).encode() + b'\n')
        self.process.stdin.flush()

    def read(self):
        assert self.selector.select(15), 'Timed out waiting for MCP reply'
        line = self.process.stdout.readline()
        assert line, f'MCP exited: {self.process.poll()}'
        return json.loads(line)

    def rpc(self, method, params=None):
        self.next_id += 1
        self.send({'jsonrpc': '2.0', 'id': self.next_id, 'method': method, 'params': params or {}})
        result = self.read()
        assert result['jsonrpc'] == '2.0' and result['id'] == self.next_id
        return result

    def tool(self, name, arguments=None):
        reply = self.rpc('tools/call', {'name': name, 'arguments': arguments or {}})
        assert 'result' in reply, reply
        return reply['result']

    def finish(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        assert self.process.returncode == 0, self.process.stderr.read().decode()
        assert self.process.stdout.read() == b'', 'Unexpected stdout after EOF'
        self.selector.close()


def check(condition, message):
    assert condition, message
    print('PASS:', message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/Build/Products/Debug/Teleprompter.app')
    args = parser.parse_args()
    executable = args.app.resolve() / 'Contents/MacOS/Teleprompter'
    fixture = ROOT / 'build/script-library/integration-check'
    assert executable.is_file(), 'Build the app with ./script/build_and_run.sh --verify first'
    assert fixture.is_file(), 'Run ./script/check_library_integration.sh first'
    folder = Path(tempfile.mkdtemp(prefix='tp-mcp-e2e-', dir='/tmp'))
    socket_path = folder / 'scripts.sock'
    host = subprocess.Popen([str(fixture), '--mcp-fixture', str(folder)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    client = None
    try:
        deadline = time.monotonic() + 15
        while not socket_path.exists() and host.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
        assert socket_path.exists(), host.communicate(timeout=1)
        check(stat.S_IMODE(folder.stat().st_mode) == 0o700 and stat.S_IMODE(socket_path.stat().st_mode) == 0o600,
              'Bridge directory and socket are restricted to the current user')
        client = Client(executable, socket_path)
        check('error' in client.rpc('tools/list'), 'Legacy tools require initialization')
        init = client.rpc('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {},
                                        'clientInfo': {'name': 'teleprompter-integration', 'version': '1'}})['result']
        check(init['protocolVersion'] == '2025-11-25', 'Actual executable negotiates MCP without GUI output on stdout')
        client.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        tools = client.rpc('tools/list')['result']['tools']
        check([t['name'] for t in tools] == ['add_script', 'list_scripts', 'open_script'], 'All three tools are discoverable')
        initial = client.tool('list_scripts')['structuredContent']
        original = initial['activeID']
        check(initial['running'] and initial['totalCount'] == 1, 'Listing preserves the running take and excludes Trash')
        body = 'A quoted "opening".\n\nCafé 🎥 日本語.\nScript text stays data: $(echo nope).'
        added = client.tool('add_script', {'title': 'Agent episode 🎥', 'text': body})
        saved = added['structuredContent']
        new_id = saved['scripts'][0]['id']
        check(not added['isError'] and saved['activeID'] == original and saved['running'], 'Adding over stdio leaves the current take running')
        disk = json.loads((folder / 'library.json').read_text())
        original_item = next(s for s in disk['scripts'] if s['id'] == original)
        new_item = next(s for s in disk['scripts'] if s['id'] == new_id)
        check(new_item['text'] == body and original_item['text'].startswith('Fixture pending edits') and 2 <= original_item['position'] < 10,
              'New Unicode/multiline script and pending editor changes are saved atomically')
        duplicate = client.tool('add_script', {'title': 'Agent episode 🎥', 'text': 'Another take'})['structuredContent']
        check(duplicate['scripts'][0]['title'] == 'Agent episode 🎥 2', 'Duplicate names receive a unique saved title')
        page = client.tool('list_scripts', {'query': 'Agent episode', 'limit': 1})['structuredContent']
        check(page['totalCount'] == 2 and page['nextOffset'] == 1 and 'text' not in page['scripts'][0], 'Search returns bounded metadata pages')
        second = client.tool('list_scripts', {'query': 'Agent episode', 'offset': 1, 'limit': 1})['structuredContent']
        check(len(second['scripts']) == 1 and second['scripts'][0]['id'] != page['scripts'][0]['id'] and 'nextOffset' not in second,
              'Pagination continues without repeating the first item')
        before = (folder / 'library.json').read_bytes()
        bad = client.rpc('tools/call', {'name': 'add_script', 'arguments': {'title': 'No', 'text': 5}})
        check('error' in bad and (folder / 'library.json').read_bytes() == before, 'Invalid arguments cannot write scripts')
        missing = client.tool('open_script', {'script_id': str(uuid.uuid4())})
        check(missing['isError'] and client.tool('list_scripts')['structuredContent']['running'], 'Opening a missing script reports an error and keeps the take running')
        # Force a real filesystem failure rather than a mocked error response.
        library_path = folder / 'library.json'
        library_path.unlink()
        library_path.mkdir()
        failed = client.tool('add_script', {'title': 'Not saved', 'text': 'Disk failure'})
        check(failed['isError'] and not failed['structuredContent']['success'], 'Actual disk-write failure never acknowledges a saved script')
        library_path.rmdir()
        library_path.write_bytes(before)
        after_failure = client.tool('list_scripts')['structuredContent']
        check(after_failure['running'] and after_failure['activeID'] == original and after_failure['totalCount'] == 3,
              'Save failure preserves the in-memory library, selection, and playback')
        opened = client.tool('open_script', {'script_id': new_id})['structuredContent']
        check(opened['success'] and opened['activeID'] == new_id and not opened['running'], 'Explicit open selects the script and pauses playback')
        client.process.stdin.write(b'not JSON\n')
        client.process.stdin.flush()
        check(client.read()['error']['code'] == -32700 and 'result' in client.rpc('ping'), 'Malformed input returns an error and the next request still works')
        client.finish()
        client = None
        check(True, 'Closing stdin cleanly stops the MCP helper')
        # A fresh helper also exercises stateless discovery without initialize.
        client = Client(executable, socket_path)
        discovery = client.rpc('server/discover')['result']
        meta = {'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': {}}
        modern = client.rpc('tools/call', {'name': 'list_scripts', 'arguments': {}, '_meta': meta})['result']
        check('2026-07-28' in discovery['supportedVersions'] and modern['resultType'] == 'complete' and not modern['isError'],
              'Stateless discovery and per-request protocol metadata work in a fresh helper')
        client.finish()
        client = None
        (folder / 'stop').touch()
        output, errors = host.communicate(timeout=10)
        assert host.returncode == 0, errors.decode()
        final = json.loads((folder / 'library.json').read_text())
        check(final['activeID'] == new_id and next(s for s in final['scripts'] if s['id'] == new_id)['text'] == body,
              'Selected script and exact content survive host shutdown')
        print('MCP integration checks passed.')
    finally:
        if client and client.process.poll() is None:
            client.process.kill()
            client.process.wait()
        if host.poll() is None:
            host.kill()
            host.wait()
        shutil.rmtree(folder)


if __name__ == '__main__':
    main()
