"""Offline release/package regression harness: no Swift builds, network or keys."""
import datetime
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("releaseTooling", root / "scripts/releaseTooling.py")
tooling = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tooling)


class SemverTests(unittest.TestCase):
    def testValidVersionsAndPrereleaseFlag(self):
        for version, prerelease in [("0.0.0", False), ("1.2.3", False), ("1.2.3+build.01", False),
                                    ("1.2.3-rc.1+build.01", True), ("1.2.3-0", True), ("1.2.3-alpha-beta", True)]:
            with self.subTest(version=version):
                self.assertEqual(tooling.parseSemver(version), prerelease)

    def testInvalidVersions(self):
        for version in ("01.2.3", "1.02.3", "1.2.03", "1.2", "v1.2.3", "1.2.3-01", "1.2.3-rc..1",
                        "1.2.3+", "1.2.3-", "1.2.3+build+other", "1.2.3\n", "1.2.3/../../file", None):
            with self.subTest(version=version), self.assertRaises(tooling.ReleaseError):
                tooling.parseSemver(version)

    def testRetryAfterDateAndLimits(self):
        now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        self.assertEqual(tooling.retryDelay("Retry-After: 9\n", 0, now), 9)
        self.assertEqual(tooling.retryDelay("Retry-After: Thu, 01 Jan 2026 00:00:12 GMT\n", 0, now), 12)
        self.assertEqual(tooling.retryDelay("", 2, now), 4)
        for header in ("Retry-After: 61", "Retry-After: invalid", "X-RateLimit-Remaining: 0"):
            with self.subTest(header=header), self.assertRaises(tooling.ReleaseError):
                tooling.retryDelay(header, 0, now)

    def testSafeReadRetriesBounded(self):
        calls = []
        def fail():
            calls.append(1)
            raise tooling.ReleaseError("unavailable")
        with patch.object(tooling.time, "sleep") as sleep, self.assertRaises(tooling.ReleaseError):
            tooling.retryRead(fail)
        self.assertEqual(len(calls), 4)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2, 4])

    def testPackageInstallNoClobber(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.zip"
            destination = Path(directory) / "package.zip"
            source.write_bytes(b"neutral fixture")
            tooling.installPackage(source, destination)
            self.assertEqual(destination.read_bytes(), b"neutral fixture")
            self.assertEqual(Path(str(destination) + ".sha256").read_text(),
                             f"{tooling.sha256(source)}  package.zip\n")
            with self.assertRaises(tooling.ReleaseError):
                tooling.installPackage(source, destination)
            destination.unlink()
            destination.symlink_to(source)
            with self.assertRaises(tooling.ReleaseError):
                tooling.installPackage(source, destination)


class OfflineReleaseTests(unittest.TestCase):
    def runFixture(self, scenario="success", version="1.2.3", dryRun=False, localTag=False, remoteTag=False,
                   command="release.sh", existingPackage=False, extraArgs=(), existingRelease=None):
        with tempfile.TemporaryDirectory(prefix="offline-release-test-") as directory:
            fixture = Path(directory)
            (fixture / "scripts").mkdir()
            (fixture / "packaging").mkdir()
            for filename in ("release.sh", "package.sh", "scripts/releaseTooling.py"):
                shutil.copy2(root / filename, fixture / filename)
            with (fixture / "packaging/Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleShortVersionString": version}, stream)
            binDir = fixture / "bin"
            binDir.mkdir()
            mock = binDir / "mockTool.py"
            shutil.copy2(Path(__file__).with_name("mockTool.py"), mock)
            mock.chmod(0o755)
            for tool in ("git", "make", "codesign", "lipo", "ditto", "curl"):
                (binDir / tool).symlink_to(mock)
            statePath = fixture / "state.json"
            state = {"scenario": scenario, "version": version, "localTag": localTag, "remoteTag": remoteTag}
            if existingRelease is not None:
                state["release"] = {"id": 7, "tag_name": "v" + version, "draft": existingRelease,
                                    "prerelease": "-" in version.split("+")[0],
                                    "upload_url": "https://uploads.github.com/repos/example/sample/releases/7/assets{?name,label}"}
            statePath.write_text(json.dumps(state))
            if existingPackage:
                (fixture / "dist").mkdir()
                package = fixture / f"dist/Bucky-{version}-macos-arm64.zip"
                package.write_bytes(b"existing neutral user artifact")
            env = {key: value for key, value in os.environ.items()
                   if key not in ("REMOTE", "DEFAULT_BRANCH", "GITHUB_API_URL", "BUCKY_PACKAGE_DIST_DIR")}
            env.update(PATH=str(binDir) + os.pathsep + os.environ["PATH"], MOCK_STATE=str(statePath),
                       GITHUB_TOKEN="offline-placeholder", PYTHONDONTWRITEBYTECODE="1", MAKEFLAGS="-n")
            args = ["bash", str(fixture / command)] + (["--dry-run"] if dryRun else []) + list(extraArgs)
            result = subprocess.run(args, cwd=fixture, env=env, capture_output=True, text=True, timeout=30)
            state = json.loads(statePath.read_text())
            if existingPackage:
                self.assertEqual(package.read_bytes(), b"existing neutral user artifact")
            self.assertNotIn("offline-placeholder", result.stdout + result.stderr + json.dumps(state))
            self.assertNotIn("private response must never be logged", result.stdout + result.stderr)
            events = state.get("events", [])
            for event in events:
                self.assertNotIn("DELETE", event)
                self.assertNotIn("clean", event)
                if event[0] == "git" and event[1:2] == ["tag"]:
                    self.assertNotIn("-d", event)
            return result, state

    def writes(self, state):
        return [event for event in state.get("events", []) if
                (event[0] == "git" and event[1:2] in (["push"], ["tag"]) and "--list" not in event)
                or (event[0] == "curl" and event[event.index("--request") + 1] != "GET")]

    def testSuccessfulReleaseGateOrdering(self):
        result, state = self.runFixture(existingPackage=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = state["events"]
        testIndex = events.index(["make", "test"])
        bundleIndex = events.index(["make", "bundle"])
        signatureIndex = next(index for index, event in enumerate(events) if event[0] == "codesign")
        firstWriteIndex = next(index for index, event in enumerate(events) if event in self.writes(state))
        self.assertLess(testIndex, bundleIndex)
        self.assertLess(bundleIndex, signatureIndex)
        self.assertLess(signatureIndex, firstWriteIndex)
        self.assertFalse(state["release"]["draft"])
        self.assertTrue(state["isolatedTestGate"])
        self.assertEqual(len(state["assets"]), 2)

    def testFailuresBlockAllRemoteMutations(self):
        for scenario in ("tests-fail", "build-fail", "bundle-signature-fail", "archive-tampered", "checksum-fail", "dirty",
                         "read-forbidden", "read-exhausted", "read-malformed", "long-retry", "remote-branch-changed"):
            with self.subTest(scenario=scenario):
                result, state = self.runFixture(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.writes(state), [])

    def testDryRunDoesNotBuildOrMutate(self):
        result, state = self.runFixture(dryRun=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(state), [])
        self.assertFalse(any(event[0] in ("make", "curl", "ditto", "codesign") for event in state["events"]))

    def testStrictSemverStopsBeforeCommands(self):
        result, state = self.runFixture(version="01.2.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state.get("events", []), [])

    def testSkipTestsShortcutIsRejected(self):
        result, state = self.runFixture(extraArgs=("--skip-tests",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state.get("events", []), [])

    def testExistingPublishedReleaseStopsBeforeBuildAndWrites(self):
        result, state = self.runFixture(existingRelease=False, localTag=True, remoteTag=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(state), [])
        self.assertNotIn(["make", "test"], state["events"])

    def testExistingDraftIsReused(self):
        result, state = self.runFixture(existingRelease=True, localTag=True, remoteTag=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("POST /repos/example/sample/releases", state["counts"])
        self.assertFalse(state["release"]["draft"])

    def testPrereleaseFlag(self):
        result, state = self.runFixture(version="2.0.0-rc.1+build.01")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(state["release"]["prerelease"])

    def testSignedExistingTagsAreVerified(self):
        for localTag, remoteTag in ((True, False), (False, True), (True, True)):
            with self.subTest(local=localTag, remote=remoteTag):
                result, state = self.runFixture(localTag=localTag, remoteTag=remoteTag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any("verify-tag" in event for event in state["events"]))
                self.assertFalse(any(event[:3] == ["git", "tag", "-s"] for event in state["events"]))
                if remoteTag:
                    self.assertFalse(any(event[:2] == ["git", "push"] for event in state["events"]))

    def testRejectUnsignedAndLightweightTags(self):
        for scenario in ("lightweight", "bad-signature", "wrong-tag-name", "wrong-commit", "remote-mismatch"):
            for localTag, remoteTag in ((True, False), (False, True)):
                if scenario == "remote-mismatch" and not remoteTag:
                    continue
                with self.subTest(scenario=scenario, local=localTag):
                    result, state = self.runFixture(scenario, localTag=localTag, remoteTag=remoteTag)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.writes(state), [])

    def testSafeReadRetry(self):
        for scenario in ("read-retry", "read-rate-limit", "read-transport"):
            with self.subTest(scenario=scenario):
                result, state = self.runFixture(scenario)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("API read retry 1/3 after 0s", result.stderr)
        result, state = self.runFixture("read-exhausted")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["counts"]["GET /repos/example/sample/releases"], 4)

    def testAmbiguousWritesReconcileWithoutRetry(self):
        for scenario in ("push-ambiguous", "create-ambiguous", "upload-ambiguous", "publish-ambiguous"):
            with self.subTest(scenario=scenario):
                result, state = self.runFixture(scenario)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(state["release"]["draft"])
                self.assertEqual(state["counts"]["POST /repos/example/sample/releases"], 1)
                self.assertEqual(state["counts"]["PATCH /repos/example/sample/releases/7"], 1)
                self.assertEqual(state["counts"]["POST /repos/example/sample/releases/7/assets"], 2)
                self.assertEqual(sum(event[:2] == ["git", "push"] for event in state["events"]), 1)

    def testUnconfirmedMutationsPreserveState(self):
        for scenario in ("push-rejected", "create-absent", "upload-absent", "publish-unconfirmed",
                         "asset-mismatch", "untrusted-upload"):
            with self.subTest(scenario=scenario):
                result, state = self.runFixture(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(state["localTag"])
                self.assertLessEqual(state.get("counts", {}).get("POST /repos/example/sample/releases", 0), 1)
                self.assertLessEqual(state.get("counts", {}).get("PATCH /repos/example/sample/releases/7", 0), 1)
                if state.get("release"):
                    self.assertTrue(state["release"]["draft"])

    def testPackagePreservesExistingArtifacts(self):
        result, state = self.runFixture(command="package.sh", existingPackage=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exist", result.stderr)

    def testPackageBuildsWithoutClean(self):
        result, state = self.runFixture(command="package.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["make", "bundle"], state["events"])
        self.assertFalse(any("clean" in event for event in state["events"]))


if __name__ == "__main__":
    unittest.main()
