#!/usr/bin/env python3
"""Enable the saved main ruleset; never change repository visibility or access."""

import json
from pathlib import Path
import subprocess
import sys


REPO = "BitL8-ByteShort/Teleprompter"
ROOT = Path(__file__).resolve().parent.parent


def api(endpoint, method="GET", body=None):
    command = [
        "gh", "api", endpoint, "--method", method,
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2026-03-10",
    ]
    if body is not None:
        command += ["--input", "-"]
    result = subprocess.run(
        command, input=json.dumps(body) if body is not None else None,
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def main():
    desired = json.loads((ROOT / ".github/main-ruleset.json").read_text())
    repository = api(f"repos/{REPO}")
    if not repository["private"] or not repository["permissions"].get("admin"):
        raise RuntimeError("Expected the private Teleprompter repo and an administrator account.")
    if repository["owner"]["id"] != desired["bypass_actors"][0]["actor_id"]:
        raise RuntimeError("Repository ownership changed; review the saved bypass before applying.")

    rulesets = api(f"repos/{REPO}/rulesets")
    matches = [item for item in rulesets if item["name"] == desired["name"]]
    if len(matches) > 1:
        raise RuntimeError("Multiple matching rulesets exist; resolve them before applying.")
    endpoint = f"repos/{REPO}/rulesets"
    method = "POST"
    if matches:
        endpoint += f"/{matches[0]['id']}"
        method = "PUT"
    applied = api(endpoint, method, desired)
    confirmed = api(f"repos/{REPO}/rulesets/{applied['id']}")
    for field in ("target", "enforcement", "conditions", "bypass_actors"):
        if confirmed.get(field) != desired[field]:
            raise RuntimeError(f"GitHub did not confirm the expected {field}; inspect the ruleset.")
    actual_rules = {rule["type"]: rule for rule in confirmed["rules"]}
    for rule in desired["rules"]:
        actual = actual_rules.get(rule["type"], {})
        parameters = actual.get("parameters", {})
        if actual.get("type") != rule["type"] or any(
            parameters.get(key) != value for key, value in rule.get("parameters", {}).items()
        ):
            raise RuntimeError(f"GitHub did not confirm the expected {rule['type']} rule.")
    print(f"Verified active main protection: {confirmed['name']} (ID {confirmed['id']}).")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"Main protection could not be confirmed: {error}", file=sys.stderr)
        print("Private-repository rulesets require GitHub Pro or a supported organization plan. "
              "Repository visibility and collaborator access were not changed.", file=sys.stderr)
        sys.exit(1)
