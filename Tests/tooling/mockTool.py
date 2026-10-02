#!/usr/bin/env python3
"""Offline command doubles; only operate inside the test's temporary repository."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sys
import urllib.parse
import zipfile


statePath = Path(os.environ["MOCK_STATE"])
state = json.loads(statePath.read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = state.get("scenario", "success")
state.setdefault("events", []).append([tool, *args])


def finish(output="", code=0):
    statePath.write_text(json.dumps(state))
    print(output, end="")
    sys.exit(code)


if tool == "git":
    actual = args[2:] if args[:1] == ["-C"] else args
    if actual[:1] == ["-c"]:
        assert actual[1].startswith("include.path="), "remote tag trust must reuse repository config"
        actual = actual[2:]
    command = actual[0]
    commit = "a" * 40
    tagObject = "b" * 40
    tag = "v" + state["version"]
    if command == "remote":
        finish("git@github.com:example/sample.git\n")
    if command == "symbolic-ref":
        finish("origin/main\n")
    if command == "check-ref-format":
        finish()
    if command == "branch":
        finish("main\n")
    if command == "status":
        finish(" M local-file\n" if scenario == "dirty" else "")
    if command == "rev-parse":
        if actual[-1] == "--git-common-dir":
            finish(".git\n")
        if scenario == "wrong-commit" and actual[-1].endswith("^{commit}"):
            finish("c" * 40 + "\n")
        finish((commit if actual[-1] == "HEAD" or actual[-1].endswith("^{commit}") else tagObject) + "\n")
    if command == "ls-remote":
        state["refReads"] = state.get("refReads", 0) + 1
        refs = f"{commit}\trefs/heads/main\n"
        if state.get("remoteTag"):
            remoteObject = "c" * 40 if scenario == "remote-mismatch" else tagObject
            refs += f"{remoteObject}\trefs/tags/{tag}\n{commit}\trefs/tags/{tag}^{{}}\n"
        if scenario == "remote-branch-changed" and state["refReads"] > 1:
            refs = refs.replace(commit, "c" * 40)
        finish(refs)
    if command == "tag":
        if actual[1] == "--list":
            finish(tag + "\n" if state.get("localTag") else "")
        assert actual[1] == "-s", "only signed tag creation is authorized"
        state["localTag"] = True
        finish()
    if command == "cat-file":
        if actual[1] == "-p":
            finish(f"object {commit}\ntype commit\ntag {'v9.9.9' if scenario == 'wrong-tag-name' else tag}\n\nneutral message\n")
        finish("commit\n" if scenario == "lightweight" else "tag\n")
    if command == "verify-tag":
        finish(code=1 if scenario == "bad-signature" else 0)
    if command in ("init", "fetch"):
        finish()
    if command == "push":
        assert not any("delete" in value or value.startswith(":") or value.startswith("+") for value in actual)
        assert actual[-1] == tagObject + ":refs/tags/" + tag, "push must pin the verified signed object"
        if scenario != "push-rejected":
            state["remoteTag"] = True
        finish(code=1 if scenario in ("push-ambiguous", "push-rejected") else 0)
    raise AssertionError("unexpected git operation")

if tool == "make":
    assert args in (["test"], ["bundle"]), "clean or unrecognized build operation"
    assert not any(key in os.environ for key in ("MAKEFLAGS", "MFLAGS", "GNUMAKEFLAGS", "MAKELEVEL"))
    if args == ["test"]:
        testDirectory = Path(os.environ["BUCKY_DATA_DIRECTORY"])
        assert testDirectory.is_absolute() and testDirectory.name == "test-data"
        assert testDirectory.parent.stat().st_mode & 0o777 == 0o700
        assert "GITHUB_TOKEN" not in os.environ, "test gate must not inherit the publication credential"
        state["isolatedTestGate"] = True
        finish(code=1 if scenario == "tests-fail" else 0)
    if scenario == "build-fail":
        finish(code=1)
    app = Path("build/Bucky.app/Contents")
    (app / "MacOS").mkdir(parents=True, exist_ok=True)
    executable = app / "MacOS/Bucky"
    executable.write_bytes(b"neutral executable fixture")
    executable.chmod(0o755)
    (app / "Info.plist").write_bytes(Path("packaging/Info.plist").read_bytes())
    finish()

if tool == "codesign":
    assert args[:3] == ["--verify", "--deep", "--strict"]
    if scenario == "checksum-fail" and sum(event[0] == "codesign" for event in state["events"]) == 2:
        for path in Path(state["packageDir"]).glob("*.sha256"):
            path.write_text("invalid checksum\n")
    finish(code=1 if scenario == "bundle-signature-fail" else 0)

if tool == "lipo":
    finish("arm64\n")

if tool == "ditto":
    app, destination = Path(args[-2]), Path(args[-1])
    state["packageDir"] = str(destination.parent.parent)
    with zipfile.ZipFile(destination, "w") as archive:
        for path in app.rglob("*"):
            if path.is_file():
                archive.write(path, path.relative_to(app.parent))
        if scenario == "archive-tampered":
            archive.writestr("Bucky.app/extra-file", "neutral")
    finish()

if tool == "curl":
    assert args[0] == "-q" and "--max-time" in args and "--connect-timeout" in args
    assert "--location" not in args and "-L" not in args
    privateDirectory = Path(args[args.index("--output") + 1]).parent
    assert privateDirectory.stat().st_mode & 0o777 == 0o700
    config = sys.stdin.read()
    assert "Authorization: Bearer " in config
    assert not any("Authorization" in value for value in args)
    method = args[args.index("--request") + 1]
    url = urllib.parse.urlsplit(args[-1])
    path = url.path
    countKey = method + " " + path
    count = state.setdefault("counts", {}).get(countKey, 0)
    state["counts"][countKey] = count + 1
    status, code, headers = 200, 0, ""
    response = {}
    release = state.get("release")
    if method == "GET" and path.endswith("/releases"):
        response = [release] if release else []
        if scenario in ("read-retry", "read-exhausted") and (count == 0 or scenario == "read-exhausted"):
            status, headers = 429, "Retry-After: 0\n"
        if scenario == "read-forbidden":
            status, response = 403, {"message": "private response must never be logged"}
        if scenario == "long-retry":
            status, headers = 429, "Retry-After: 3600\n"
        if scenario == "read-malformed":
            response = "malformed"
        if scenario == "read-transport" and count == 0:
            status, code, headers = 0, 28, "Retry-After: 0\n"
        if scenario == "read-rate-limit" and count == 0:
            status, headers = 403, "Retry-After: 0\n"
    elif method == "POST" and path.endswith("/releases"):
        state["release"] = {
            "id": 7, "tag_name": "v" + state["version"], "draft": True,
            "prerelease": "-" in state["version"].split("+")[0],
            "upload_url": "https://uploads.github.com/repos/example/sample/releases/7/assets{?name,label}"}
        response = state["release"]
        if scenario == "untrusted-upload":
            response["upload_url"] = "https://invalid.example/assets"
        if scenario == "create-ambiguous":
            status, code, headers = 0, 28, "Retry-After: 0\n"
        if scenario == "create-absent":
            state.pop("release")
            status, code, headers = 0, 28, "Retry-After: 0\n"
    elif path.endswith("/assets") and method == "GET":
        response = state.get("assets", [])
    elif path.endswith("/assets") and method == "POST":
        assetPath = Path(args[args.index("--data-binary") + 1][1:])
        name = urllib.parse.parse_qs(url.query)["name"][0]
        response = {"name": name, "state": "uploaded", "size": assetPath.stat().st_size,
                    "digest": "sha256:" + hashlib.sha256(assetPath.read_bytes()).hexdigest()}
        if scenario == "asset-mismatch":
            response["digest"] = "sha256:" + "0" * 64
        state.setdefault("assets", []).append(response)
        if scenario == "upload-ambiguous":
            status, code, headers = 0, 28, "Retry-After: 0\n"
        if scenario == "upload-absent":
            state["assets"].pop()
            status, code, headers = 0, 28, "Retry-After: 0\n"
    elif path.endswith("/releases/7") and method == "GET":
        response = release
    elif path.endswith("/releases/7") and method == "PATCH":
        if scenario != "publish-unconfirmed":
            state["release"]["draft"] = False
        response = state["release"]
        if scenario in ("publish-ambiguous", "publish-unconfirmed"):
            status, code, headers = 0, 28, "Retry-After: 0\n"
    else:
        raise AssertionError("unexpected API operation")
    Path(args[args.index("--output") + 1]).write_text(
        "{" if scenario == "read-malformed" and method == "GET" else json.dumps(response))
    Path(args[args.index("--dump-header") + 1]).write_text(headers)
    finish(str(status), code)

raise AssertionError("unexpected mock tool")
