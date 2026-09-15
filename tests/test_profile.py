"""Integration tests using disposable Linux containers; no server changes/dependencies.

python3 -m unittest discover -s tests -v
SSH_HELLO_TEST_IMAGE=alpine:3.20 python3 -m unittest discover -s tests -v
SSH_HELLO_TEST_SHELL=/bin/bash python3 -m unittest discover -s tests -v
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
IMAGE = os.environ.get("SSH_HELLO_TEST_IMAGE", "python:3.12-slim")
SHELL = os.environ.get("SSH_HELLO_TEST_SHELL", "/bin/sh")
HISTORY = """tester pts/0 192.0.2.10 Tue Sep 15 10:00:00 2026 still logged in
tester pts/3 192.0.2.30 Mon Sep 14 09:00:00 2026 - 10:00:00 (01:00)
"""


class ProfileTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".tmp-", dir=ROOT / "tests")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.profile = self.work / "profile.sh"
        self.mock("figlet", "exit 1")
        self.mock("df", "printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\n/dev/root 10000 2000 8000 20%% /\\n'")
        self.mock("who", "printf 'tester pts/0 2026-09-15 10:00 (192.0.2.10)\\n'")
        self.mock("last", "cat <<'ROWS'\n" + HISTORY + "ROWS")
        self.mock("journalctl", "printf 'Failed password for bad from 192.0.2.99\\npam_unix: authentication failure\\nFailed password for other from 192.0.2.98\\n'")
        self.render("test-host")

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\nprintf '%s\\n' \"" + name + " $*\" >> /test/calls\n" + body + "\n")
        path.chmod(0o755)

    def render(self, banner):
        # figlet's local stub must not write the container-only trace path.
        (self.bin / "figlet").write_text("#!/bin/sh\nexit 1\n")
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}")
        subprocess.run(["bash", str(ROOT / "ssh_info.sh"), "--output", str(self.profile)],
                       input=banner + "\n5\n", text=True, capture_output=True,
                       env=env, check=True, timeout=5)

    def run_profile(self, *, interactive=True, tty=True, ssh=True, setup="", suffix="", restricted=False, mounts=()):
        cmd = ["docker", "run", "--rm", "--network", "none"]
        if tty:
            cmd += ["-t"]
        cmd += ["-v", f"{self.work}:/test", "-e", "USER=tester", "-e", "SSH_TTY=/dev/pts/0",
                "-e", "LC_ALL=C", "-e", "TERM=dumb"]
        if ssh:
            cmd += ["-e", "SSH_CONNECTION=192.0.2.10 54321 2001:db8::20 22"]
        for path, target in mounts:
            cmd += ["-v", f"{path}:{target}:ro"]
        path_setup = 'PATH=/test/bin:$PATH; export PATH; '
        if restricted:
            path_setup = 'for x in awk date uname sleep tail; do ln -s "$(command -v "$x")" /test/bin/"$x"; done; PATH=/test/bin; export PATH; '
        # /proc/uptime measures script execution without Docker startup overhead.
        script = (path_setup + setup + '; read start rest < /proc/uptime; '
                  '. /test/profile.sh; read finish rest < /proc/uptime; '
                  'printf "\\nTEST_ELAPSED=%s,%s\\n" "$start" "$finish"; '
                  + suffix + '; echo LOGIN_OK')
        script = script.replace('; ;', ';')
        cmd += [IMAGE, SHELL, "-ic" if interactive else "-c", script]
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("LOGIN_OK", result.stdout)
        match = re.search(r"TEST_ELAPSED=([\d.]+),([\d.]+)", result.stdout)
        self.assertIsNotNone(match, result.stdout)
        elapsed = float(match[2]) - float(match[1])
        self.calls = (self.work / "calls").read_text() if (self.work / "calls").exists() else ""
        self.elapsed = elapsed
        return result.stdout

    def test_normal_output_and_query_limits(self):
        out = self.run_profile()
        self.assertIn("test-host", out)
        self.assertIn("设备 IP  : 2001:db8::20", out)
        self.assertIn("上次 IP  : 192.0.2.30", out)
        self.assertIn("密码失败 : 2（24h", out)
        self.assertIn("可用存储 : 80.0%", out)
        self.assertEqual(self.calls.count("last "), 1)
        self.assertIn("last -wFi -n 20 tester", self.calls)
        self.assertIn("-n 1000 --since=-24h", self.calls)
        self.assertLess(self.elapsed, 1)
        print(f"\n  normal ({IMAGE}, {SHELL}): {self.elapsed:.2f}s")

    def test_noninteractive_is_silent(self):
        out = self.run_profile(interactive=False)
        self.assertNotIn("test-host", out)
        self.assertEqual(self.calls, "")

    def test_redirected_output_is_silent(self):
        out = self.run_profile(tty=False)
        self.assertNotIn("test-host", out)
        self.assertEqual(self.calls, "")

    def test_local_login_is_silent(self):
        out = self.run_profile(ssh=False)
        self.assertNotIn("test-host", out)
        self.assertEqual(self.calls, "")

    def test_banner_is_literal(self):
        banner = "team'\" $(touch /test/injected) `touch /test/injected2` \\n %s"
        self.render(banner)
        out = self.run_profile()
        self.assertIn(banner, out)
        self.assertFalse((self.work / "injected").exists())
        self.assertFalse((self.work / "injected2").exists())

    def test_caller_state_is_preserved(self):
        out = self.run_profile(
            setup="set -eu; HOST_NAME=keep; LC_ALL=POSIX; set -- first second; bounded() { echo original; }",
            suffix='printf "PRESERVED=%s,%s,%s,%s,%s\\n" "$HOST_NAME" "$LC_ALL" "$1" "$2" "$(bounded)"; case $- in *e*u*|*u*e*) echo OPTIONS_OK;; esac')
        self.assertIn("PRESERVED=keep,POSIX,first,second,original", out)
        self.assertIn("OPTIONS_OK", out)

    def test_last_timeout_is_not_retried(self):
        self.mock("last", "exec /bin/sleep 10")
        out = self.run_profile()
        self.assertIn("近期无可用记录", out)
        self.assertEqual(self.calls.count("last "), 1)
        self.assertLess(self.elapsed, 2.5)
        print(f"\n  slow last ({IMAGE}, {SHELL}): {self.elapsed:.2f}s")

    def test_df_timeout_does_not_block_other_fields(self):
        self.mock("df", "exec /bin/sleep 10")
        out = self.run_profile()
        self.assertIn("可用存储 : 已跳过", out)
        self.assertIn("上次 IP  : 192.0.2.30", out)
        self.assertLess(self.elapsed, 2.5)

    def test_journal_timeout_is_not_reported_as_zero(self):
        self.mock("journalctl", "exec /bin/sleep 10")
        out = self.run_profile()
        self.assertIn("密码失败 : 无法统计", out)
        self.assertLess(self.elapsed, 2.5)

    def test_term_ignoring_command_is_killed(self):
        self.mock("last", "trap '' TERM; exec /bin/sleep 10")
        self.run_profile()
        self.assertLess(self.elapsed, 3.5)
        self.assertEqual(self.calls.count("last "), 1)

    def test_legacy_last_keeps_limit(self):
        self.mock("last", 'if [ "$1" = -wFi ]; then exit 1; fi\ncat <<\'ROWS\'\n' + HISTORY + "ROWS")
        out = self.run_profile()
        self.assertIn("上次 IP  : 192.0.2.30", out)
        self.assertEqual(self.calls.count("last "), 2)
        self.assertIn("last -i -n 20 tester", self.calls)

    def test_unsupported_last_never_uses_unbounded_fallback(self):
        self.mock("last", "exit 1")
        self.run_profile()
        self.assertEqual(self.calls.count("last "), 2)
        for line in self.calls.splitlines():
            if line.startswith("last "):
                self.assertIn("-n 20 tester", line)

    def test_no_timeout_skips_expensive_commands(self):
        out = self.run_profile(restricted=True)
        self.assertIn("可用存储 : 已跳过", out)
        self.assertIn("密码失败 : 无法统计", out)
        self.assertEqual(self.calls, "")
        self.assertLess(self.elapsed, 1)

    def test_log_file_fallback_is_bounded_and_labelled(self):
        self.mock("journalctl", "exit 1")
        log = self.work / "auth.log"
        log.write_text("sshd: Failed password for old from 192.0.2.99\n" * 40000
                       + "sshd: Accepted password for tester from 192.0.2.10\n" * 998
                       + "other-service: Failed password for nobody\n"
                       + "sshd: Failed password for recent from 192.0.2.99\n")
        out = self.run_profile(mounts=[(log, "/var/log/auth.log")])
        self.assertIn("密码失败 : 1（日志末尾最多 1000 行 / 256KiB，未按时间筛选", out)
        self.assertLess(self.elapsed, 1)

    def test_cpu_sampling_preserves_large_counters(self):
        # Long uptimes / many cores exceed awk's default six significant digits.
        stat = self.work / "stat"
        stat.write_text("cpu 3000000123 0 0 7000000456 0 0 0 0 0 0\ncpu0 1 0 0 1 0 0 0 0\n")
        self.mock("sleep", "printf 'cpu 3000000153 0 0 7000000526 0 0 0 0 0 0\\ncpu0 1 0 0 1 0 0 0 0\\n' > /test/stat")
        out = self.run_profile(mounts=[(stat, "/proc/stat")])
        self.assertIn("CPU 占用 : 30.0%", out)

    def test_query_failure_is_not_reported_as_zero(self):
        self.mock("journalctl", "exit 1")
        out = self.run_profile()
        self.assertIn("密码失败 : 无法统计", out)

    def test_installer_rejects_symlink(self):
        original = self.work / "original"
        original.write_text("keep me")
        output = self.work / "link"
        output.symlink_to(original)
        result = subprocess.run(["bash", str(ROOT / "ssh_info.sh"), "--output", str(output)],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(original.read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
