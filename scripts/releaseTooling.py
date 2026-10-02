"""Release gates and bounded, non-destructive GitHub publishing.

All subprocess arguments are passed as data. API credentials travel through curl's
stdin configuration, never its argv; raw command/API errors are not logged.
"""

import argparse
import datetime
import email.utils
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile


class ReleaseError(Exception):
    pass


def parseSemver(version):
    if not isinstance(version, str) or len(version) > 200:
        raise ReleaseError("version must be strict SemVer")
    match = re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
        r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", version)
    if not match:
        raise ReleaseError("version must be strict SemVer")
    prerelease = match.group(4)
    if prerelease and any(part.isdigit() and len(part) > 1 and part[0] == "0"
                          for part in prerelease.split(".")):
        raise ReleaseError("numeric prerelease identifiers cannot have leading zeroes")
    return bool(prerelease)


def plistVersion(path):
    with open(path, "rb") as stream:
        version = plistlib.load(stream).get("CFBundleShortVersionString")
    parseSemver(version)
    return version


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def installPackage(source, destination):
    """Publish without overwriting an existing asset, including symlinks/races."""
    source, destination = Path(source), Path(destination)
    checksum = Path(str(destination) + ".sha256")
    if os.path.lexists(destination) or os.path.lexists(checksum):
        raise ReleaseError("package assets already exist; review them manually")
    stagedChecksum = source.with_suffix(".sha256")
    with stagedChecksum.open("x", encoding="ascii") as stream:
        stream.write(f"{sha256(source)}  {destination.name}\n")
    # Hard links provide atomic no-clobber creation on the staging filesystem.
    # On partial installation, preserve the file for manual review, never delete it.
    os.link(source, destination)
    os.link(stagedChecksum, checksum)


def runProcess(args, timeout, **kwargs):
    """Reap the whole command group on timeout, including compiler/git children."""
    with subprocess.Popen(args, start_new_session=True, **kwargs) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
            raise
        return subprocess.CompletedProcess(args, process.returncode, stdout, stderr)


def runCommand(args, timeout=60, visible=False, env=None):
    try:
        result = runProcess(args, timeout, stdin=subprocess.DEVNULL,
                                stdout=None if visible else subprocess.PIPE,
                                stderr=None if visible else subprocess.DEVNULL,
                            text=True, env=env)
    except (subprocess.TimeoutExpired, OSError) as error:
        raise ReleaseError(f"{Path(args[0]).name} timed out or could not start") from error
    if result.returncode:
        raise ReleaseError(f"{Path(args[0]).name} failed; remote/local state is preserved")
    return (result.stdout or "").strip()


def retryRead(operation):
    for attempt in range(4):
        try:
            return operation()
        except ReleaseError:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)


def retryDelay(headers, attempt, now=None):
    fields = {}
    for line in headers.splitlines():
        name, separator, value = line.partition(":")
        if separator:
            fields[name.strip().lower()] = value.strip()
    now = now or datetime.datetime.now(datetime.timezone.utc)
    value = fields.get("retry-after")
    if value is not None:
        if re.fullmatch(r"[0-9]+", value):
            delay = int(value)
        else:
            try:
                date = email.utils.parsedate_to_datetime(value)
                delay = max(0, (date - now).total_seconds())
            except (ValueError, TypeError, OverflowError, AttributeError) as error:
                raise ReleaseError("invalid Retry-After; stop and review throttling") from error
    elif fields.get("x-ratelimit-remaining") == "0":
        try:
            delay = max(0, int(fields["x-ratelimit-reset"]) - now.timestamp())
        except (KeyError, ValueError) as error:
            raise ReleaseError("invalid rate-limit reset; stop and review throttling") from error
    else:
        delay = 2 ** attempt
    if delay > 60:
        raise ReleaseError("server requests a longer pause; state preserved, rerun later")
    return delay


class GitHub:
    def __init__(self, owner, repo, token, tempDir):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", owner) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", repo):
            raise ReleaseError("invalid repository identifiers")
        if not token or any(ord(char) < 32 or ord(char) == 127 for char in token):
            raise ReleaseError("GITHUB_TOKEN is required and must not contain control characters")
        if os.environ.get("GITHUB_API_URL", "https://api.github.com") != "https://api.github.com":
            raise ReleaseError("only the trusted GitHub API origin is supported")
        self.baseUrl = f"https://api.github.com/repos/{owner}/{repo}"
        self.uploadPrefix = f"https://uploads.github.com/repos/{owner}/{repo}/releases/"
        self.token = token
        self.tempDir = Path(tempDir)

    def request(self, method, url, payload=None, asset=None, contentType="application/json"):
        if not (url.startswith(self.baseUrl + "/") or url.startswith(self.uploadPrefix)):
            raise ReleaseError("refusing an untrusted API/upload URL")
        for attempt in range(4 if method == "GET" else 1):
            bodyPath = self.tempDir / "response.json"
            headerPath = self.tempDir / "headers"
            args = ["curl", "-q", "--config", "-", "--silent", "--proto", "=https",
                    "--tlsv1.3", "--connect-timeout", "10", "--max-time", "60",
                    "--max-filesize", "8388608", "--request", method,
                    "--header", "Accept: application/vnd.github+json",
                    "--header", "X-GitHub-Api-Version: 2022-11-28",
                    "--output", str(bodyPath), "--dump-header", str(headerPath),
                    "--write-out", "%{http_code}"]
            if payload is not None:
                args += ["--header", "Content-Type: application/json", "--data", json.dumps(payload)]
            if asset is not None:
                args += ["--header", f"Content-Type: {contentType}", "--data-binary", f"@{asset}"]
            args.append(url)
            escapedToken = self.token.replace("\\", "\\\\").replace('"', '\\"')
            config = f'header = "Authorization: Bearer {escapedToken}"\n'
            for path in (bodyPath, headerPath):
                path.write_bytes(b"")
            try:
                # communicate(input) is deliberately separate from the generic
                # command runner so the credential is never attached to argv.
                with subprocess.Popen(args, stdin=subprocess.PIPE, text=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL, start_new_session=True) as process:
                    try:
                        stdout, _ = process.communicate(input=config, timeout=65)
                    except BaseException:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.communicate()
                        raise
                    response = subprocess.CompletedProcess(args, process.returncode, stdout)
                status = int(response.stdout) if response.stdout.isdigit() else 0
                transport = response.returncode
            except (subprocess.TimeoutExpired, OSError):
                status, transport = 0, 28
            headers = headerPath.read_text(encoding="utf-8", errors="replace")
            transient = transport in (5, 6, 7, 18, 28, 52, 55, 56) or status in (429, 500, 502, 503, 504)
            transient |= status == 403 and ("retry-after:" in headers.lower() or
                                           "x-ratelimit-remaining: 0" in headers.lower())
            if transient:
                delay = retryDelay(headers, attempt)
                if method != "GET":
                    # A write can have succeeded despite a failed response. Pause,
                    # then let the caller reconcile using GET, never repeat it here.
                    time.sleep(delay)
                    return None
                if attempt < 3:
                    print(f"API read retry {attempt + 1}/3 after {delay:g}s", file=sys.stderr)
                    time.sleep(delay)
                    continue
            if transport or not 200 <= status < 300:
                if method != "GET":
                    return None
                raise ReleaseError(f"API read failed (HTTP {status}); state preserved")
            try:
                return json.loads(bodyPath.read_text(encoding="utf-8"))
            except (ValueError, UnicodeError):
                if method != "GET":
                    return None
                raise ReleaseError("invalid API response; state preserved")
        raise ReleaseError("API read retry limit reached; state preserved")

    def pages(self, endpoint):
        items = []
        for page in range(1, 21):
            data = self.request("GET", f"{self.baseUrl}/{endpoint}?per_page=100&page={page}")
            if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
                raise ReleaseError("invalid API list; state preserved")
            items.extend(data)
            if len(data) < 100:
                return items
        raise ReleaseError("API pagination limit reached; refusing incomplete reconciliation")

    def findRelease(self, tag):
        matches = [item for item in self.pages("releases") if item.get("tag_name") == tag]
        if len(matches) > 1:
            raise ReleaseError("multiple releases match the tag; review manually")
        return matches[0] if matches else None


class Release:
    def __init__(self, dryRun, tempDir):
        self.dryRun = dryRun
        self.tempDir = Path(tempDir)
        self.version = plistVersion("packaging/Info.plist")
        self.prerelease = parseSemver(self.version)
        self.tag = "v" + self.version
        self.remote = os.environ.get("REMOTE", "origin")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", self.remote):
            raise ReleaseError("invalid remote name")
        remoteUrl = runCommand(["git", "remote", "get-url", self.remote])
        match = re.fullmatch(r"(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)"
                             r"([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?", remoteUrl)
        if not match:
            raise ReleaseError("expected a GitHub remote without embedded credentials")
        self.remoteUrl = remoteUrl
        self.owner, self.repo = match.groups()
        self.api = None if dryRun else GitHub(self.owner, self.repo, os.environ.get("GITHUB_TOKEN", ""), tempDir)
        self.assetDir = self.tempDir / "dist"

    def remoteRefs(self):
        output = retryRead(lambda: runCommand(["git", "ls-remote", self.remote,
                                              f"refs/heads/{self.branch}", f"refs/tags/{self.tag}",
                                              f"refs/tags/{self.tag}^{{}}"], timeout=30))
        refs = {}
        for line in output.splitlines():
            parts = line.split()
            if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", parts[0]):
                raise ReleaseError("invalid remote ref response")
            refs[parts[1]] = parts[0]
        return refs

    def verifyTag(self, ref, repository=None):
        git = ["git"]
        if repository:
            # The private object database must use the same repository signing
            # trust configuration (including SSH allowed signers) as local tags.
            configDir = runCommand(["git", "rev-parse", "--git-common-dir"])
            configPath = (Path(configDir) / "config").resolve()
            git += ["-C", str(repository), "-c", "include.path=" + str(configPath)]
        if runCommand(git + ["cat-file", "-t", ref]) != "tag":
            raise ReleaseError("release tag must be annotated and signed")
        tagHeaders = runCommand(git + ["cat-file", "-p", ref]).split("\n\n", 1)[0].splitlines()
        if "tag " + self.tag not in tagHeaders or "type commit" not in tagHeaders:
            raise ReleaseError("signed tag identity does not match the release")
        runCommand(git + ["verify-tag", ref])
        if runCommand(git + ["rev-parse", ref + "^{commit}"]) != self.commit:
            raise ReleaseError("release tag points to a different commit")
        return runCommand(git + ["rev-parse", ref])

    def preflight(self):
        self.branch = os.environ.get("DEFAULT_BRANCH", "")
        if not self.branch:
            try:
                ref = runCommand(["git", "symbolic-ref", "--quiet", "--short", f"refs/remotes/{self.remote}/HEAD"])
                self.branch = ref.removeprefix(self.remote + "/")
            except ReleaseError:
                self.branch = "main"
        runCommand(["git", "check-ref-format", "refs/heads/" + self.branch])
        if runCommand(["git", "branch", "--show-current"]) != self.branch:
            raise ReleaseError("release requires the default branch")
        if runCommand(["git", "status", "--porcelain", "--untracked-files=all"]):
            raise ReleaseError("release requires a clean worktree")
        self.commit = runCommand(["git", "rev-parse", "HEAD"])
        refs = self.remoteRefs()
        if refs.get("refs/heads/" + self.branch) != self.commit:
            raise ReleaseError("HEAD differs from the remote default branch")
        localExists = bool(runCommand(["git", "tag", "--list", self.tag]))
        self.tagObject = self.verifyTag("refs/tags/" + self.tag) if localExists else None
        remoteObject = refs.get("refs/tags/" + self.tag)
        if remoteObject:
            # Fetch into a private bare repository: never overwrite local tags.
            tagRepo = self.tempDir / "tag-verification.git"
            runCommand(["git", "init", "--bare", "--quiet", str(tagRepo)])
            retryRead(lambda: runCommand(["git", "-C", str(tagRepo), "fetch", "--no-tags",
                                          self.remoteUrl, "refs/tags/" + self.tag], timeout=30))
            verified = self.verifyTag("FETCH_HEAD", tagRepo)
            if verified != remoteObject or (self.tagObject and verified != self.tagObject):
                raise ReleaseError("remote tag changed or differs from the signed local tag")
            self.tagObject = verified
        self.remoteTag = remoteObject

    def validateRelease(self, release):
        if not isinstance(release, dict) or type(release.get("id")) is not int or release["id"] <= 0:
            raise ReleaseError("invalid release identity; review preserved state")
        if release.get("tag_name") != self.tag or type(release.get("draft")) is not bool:
            raise ReleaseError("release state does not match the expected tag")
        if release.get("prerelease") is not self.prerelease:
            raise ReleaseError("release prerelease flag does not match SemVer")
        return release

    def verifyAssets(self):
        app = Path("build/Bucky.app")
        executable = app / "Contents/MacOS/Bucky"
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ReleaseError("packaged executable is missing")
        if plistVersion(app / "Contents/Info.plist") != self.version:
            raise ReleaseError("packaged version differs from release version")
        # Ad-hoc signing remains allowed; the bundle must still verify consistently.
        runCommand(["codesign", "--verify", "--deep", "--strict", str(app)])
        archs = runCommand(["lipo", "-archs", str(executable)]).split()
        if not archs or len(set(archs)) != len(archs) or any(arch not in ("arm64", "x86_64") for arch in archs):
            raise ReleaseError("invalid package architectures")
        archive = self.assetDir / f"Bucky-{self.version}-macos-{'-'.join(archs)}.zip"
        checksum = Path(str(archive) + ".sha256")
        if not archive.is_file() or not checksum.is_file() or archive.is_symlink() or checksum.is_symlink():
            raise ReleaseError("package assets are missing or unsafe")
        expected = f"{sha256(archive)}  {archive.name}\n"
        if checksum.read_text(encoding="ascii") != expected:
            raise ReleaseError("package checksum mismatch")
        with zipfile.ZipFile(archive) as zipped:
            entries = zipped.infolist()
            if len(entries) > 10000 or sum(entry.file_size for entry in entries) > 1024 * 1024 * 1024:
                raise ReleaseError("archive exceeds verification limits")
            names = [entry.filename for entry in entries]
            if len(set(names)) != len(names):
                raise ReleaseError("duplicate archive paths")
            if zipped.testzip() is not None:
                raise ReleaseError("package archive integrity failed")
            archivedFiles = set()
            for entry in entries:
                if entry.filename.startswith("__MACOSX/") or entry.is_dir():
                    continue
                relative = Path(entry.filename)
                if relative.parts[0] != "Bucky.app" or ".." in relative.parts or relative.is_absolute():
                    raise ReleaseError("unexpected archive path")
                bundleFile = Path("build") / relative
                if not bundleFile.is_file() or bundleFile.is_symlink():
                    raise ReleaseError("archive file missing from verified bundle")
                digest = hashlib.sha256()
                with zipped.open(entry) as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                if digest.hexdigest() != sha256(bundleFile):
                    raise ReleaseError("archive contents differ from verified bundle")
                archivedFiles.add(bundleFile)
            bundleFiles = {path for path in app.rglob("*") if path.is_file()}
            if archivedFiles != bundleFiles:
                raise ReleaseError("archive does not contain the complete verified bundle")
        return archive, checksum

    def unchanged(self):
        if runCommand(["git", "rev-parse", "HEAD"]) != self.commit or plistVersion("packaging/Info.plist") != self.version:
            raise ReleaseError("release inputs changed during verification")
        if runCommand(["git", "status", "--porcelain", "--untracked-files=all"]):
            raise ReleaseError("worktree changed during verification")
        refs = self.remoteRefs()
        if refs.get("refs/heads/" + self.branch) != self.commit:
            raise ReleaseError("remote default branch changed during verification")
        return refs

    def execute(self):
        self.preflight()
        if self.dryRun:
            print(f"Dry run: verified source/ref plan for {self.tag}; no build, tag, or API writes performed.")
            print("Publishing will require tests, build, bundle signature, archive and checksum verification.")
            return
        existing = self.api.findRelease(self.tag)
        if existing and not self.validateRelease(existing)["draft"]:
            raise ReleaseError("published release already exists; review it manually")
        print("Running required tests before packaging...", flush=True)
        gateEnv = {key: value for key, value in os.environ.items()
                   if key not in ("MAKEFLAGS", "MFLAGS", "GNUMAKEFLAGS", "MAKELEVEL", "GITHUB_TOKEN")}
        gateEnv["BUCKY_DATA_DIRECTORY"] = str(self.tempDir / "test-data")
        runCommand(["make", "test"], timeout=1800, visible=True, env=gateEnv)
        print("Building and verifying package...", flush=True)
        packageEnv = dict(gateEnv, BUCKY_PACKAGE_DIST_DIR=str(self.assetDir))
        runCommand(["./package.sh"], timeout=1800, visible=True, env=packageEnv)
        assets = self.verifyAssets()
        refs = self.unchanged()
        currentRemoteTag = refs.get("refs/tags/" + self.tag)
        if currentRemoteTag != self.remoteTag:
            raise ReleaseError("remote tag changed during verification")
        if not self.tagObject:
            runCommand(["git", "tag", "-s", self.tag, "-m", "Bucky " + self.version, self.commit])
            self.tagObject = self.verifyTag("refs/tags/" + self.tag)
        if not self.remoteTag:
            try:
                # Pin the already verified object, even if a concurrent process
                # moves the local tag between verification and push.
                runCommand(["git", "push", self.remote, f"{self.tagObject}:refs/tags/{self.tag}"])
            except ReleaseError:
                print("Tag push response uncertain; reconciling remote state without retry/deletion.", file=sys.stderr)
            if self.remoteRefs().get("refs/tags/" + self.tag) != self.tagObject:
                raise ReleaseError("tag push not confirmed; signed local tag preserved")
        # A concurrent publisher may have created a release while gates ran.
        release = self.api.findRelease(self.tag)
        if release is None:
            self.api.request("POST", self.api.baseUrl + "/releases", {
                "tag_name": self.tag, "name": "Bucky " + self.version,
                "draft": True, "prerelease": self.prerelease, "generate_release_notes": True})
            release = self.api.findRelease(self.tag)
        release = self.validateRelease(release)
        if not release["draft"]:
            raise ReleaseError("release was published concurrently; state preserved")
        releaseId = release["id"]
        print(f"Preserving release {releaseId} on any failure; no automatic deletion.", flush=True)
        if not isinstance(release.get("upload_url"), str):
            raise ReleaseError("invalid upload URL; draft preserved")
        uploadUrl = release["upload_url"].split("{", 1)[0]
        if uploadUrl != f"{self.api.uploadPrefix}{releaseId}/assets":
            raise ReleaseError("untrusted upload URL; draft preserved")
        for asset in assets:
            def matchingAsset():
                matches = [item for item in self.api.pages(f"releases/{releaseId}/assets")
                           if item.get("name") == asset.name]
                if len(matches) > 1:
                    raise ReleaseError("duplicate release assets; draft preserved")
                if not matches:
                    return False
                item = matches[0]
                if (item.get("state") != "uploaded" or item.get("size") != asset.stat().st_size
                        or item.get("digest") != "sha256:" + sha256(asset)):
                    raise ReleaseError("existing asset cannot be verified; draft preserved for review")
                return True
            if not matchingAsset():
                self.api.request("POST", uploadUrl + "?name=" + urllib.parse.quote(asset.name, safe=""),
                                 asset=asset, contentType="application/zip" if asset.suffix == ".zip" else "text/plain")
                if not matchingAsset():
                    raise ReleaseError("asset upload not confirmed; draft preserved")
        if self.unchanged().get("refs/tags/" + self.tag) != self.tagObject:
            raise ReleaseError("remote tag changed before publish; draft preserved")
        self.verifyAssets()
        releaseUrl = f"{self.api.baseUrl}/releases/{releaseId}"
        beforePublish = self.validateRelease(self.api.request("GET", releaseUrl))
        if not beforePublish["draft"]:
            raise ReleaseError("release was published concurrently; state preserved")
        self.api.request("PATCH", releaseUrl, {"draft": False})
        published = self.validateRelease(self.api.request("GET", releaseUrl))
        if published["draft"]:
            raise ReleaseError("publish not confirmed; draft and assets preserved, review before rerunning")
        print(f"Released {self.tag}; server confirms published release {releaseId}.")


def main():
    parser = argparse.ArgumentParser(description="Verify and publish a signed tag with package assets; never delete remote state.")
    parser.add_argument("--dry-run", action="store_true", help="read-only source/ref checks; no build or publishing")
    parser.add_argument("--plist-version", metavar="PATH", help=argparse.SUPPRESS)
    parser.add_argument("--install-package", nargs=2, metavar=("SOURCE", "DESTINATION"), help=argparse.SUPPRESS)
    options = parser.parse_args()
    try:
        if options.plist_version:
            print(plistVersion(options.plist_version))
        elif options.install_package:
            installPackage(*options.install_package)
        else:
            # mkdtemp uses unpredictable names and mode 0700; all API bodies and
            # fetched tag objects remain private and are cleaned on exit.
            with tempfile.TemporaryDirectory(prefix="bucky-release-") as tempDir:
                Release(options.dry_run, tempDir).execute()
    except (ReleaseError, OSError, ValueError, KeyError, TypeError, RecursionError,
            zipfile.BadZipFile, plistlib.InvalidFileException):
        # Exception text from parsers, paths, curl or git may contain private data.
        # Our own errors contain only controlled diagnostics.
        error = sys.exc_info()[1]
        print("error: " + (str(error) if isinstance(error, ReleaseError) else "invalid or unavailable release input; state preserved"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
