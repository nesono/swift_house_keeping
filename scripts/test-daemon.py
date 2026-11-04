#!/usr/bin/env python3
"""Exercise the daemon in a subprocess: python3 scripts/test-daemon.py BINARY."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def wait_for_log(process, log_path, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        output = log_path.read_text() if log_path.exists() else ""
        if process.poll() is not None:
            raise AssertionError(
                f"Daemon exited with {process.returncode} waiting for {message!r}:\n{output}"
            )
        if message in output:
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {message!r}:\n{output}")


def check_shutdown(binary, shutdown_signal, pid_path):
    with tempfile.TemporaryDirectory(prefix="house-keeping-test-") as temp:
        root = Path(temp).resolve()
        watched = root / "watched"
        watched.mkdir()
        log_path = root / "daemon.log"
        config_path = root / "config.yaml"
        config_path.write_text(
            f"""version: 1
global:
  log_level: info
  log_file: {log_path}
  state_file: {root / 'state.db'}
rules:
  - name: scheduled
    trigger: {{ type: schedule, interval: 1s }}
    watch_paths: [{watched}]
    conditions:
      all:
        - extension: txt
    actions:
      - log: scheduled-match
  - name: file-event
    trigger: {{ type: file_change, events: [create] }}
    watch_paths: [{watched}]
    conditions:
      all:
        - extension: txt
    actions:
      - log: file-event-match
"""
        )
        with (root / "stderr.log").open("w") as stderr:
            process = subprocess.Popen(
                [str(binary), "daemon", "--config", str(config_path)],
                stdout=stderr,
                stderr=stderr,
            )
            try:
                wait_for_log(process, log_path, "Daemon running.")
                assert pid_path.read_text().strip() == str(process.pid)
                (watched / "example.txt").write_text("test fixture\n")
                wait_for_log(process, log_path, "scheduled-match")
                wait_for_log(process, log_path, "file-event-match")

                # The GUI saves atomically. Verify replacement triggers a live reload.
                replacement = root / "config.new.yaml"
                replacement.write_text(
                    config_path.read_text().replace("file-event-match", "reloaded-file-event-match")
                )
                replacement.replace(config_path)
                wait_for_log(process, log_path, "Config reloaded successfully")
                (watched / "after-reload.txt").write_text("test fixture\n")
                wait_for_log(process, log_path, "reloaded-file-event-match")

                process.send_signal(shutdown_signal)
                assert process.wait(timeout=10) == 0, "Daemon did not exit cleanly"
                assert not pid_path.exists(), "Daemon left its PID file behind"
                assert "Shutting down daemon..." in log_path.read_text()
            except Exception:
                print((root / "stderr.log").read_text(), file=sys.stderr)
                raise
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()
                if pid_path.exists() and pid_path.read_text().strip() == str(process.pid):
                    pid_path.unlink()
        print(f"PASS: startup, scheduled rule, file event, atomic config reload, {shutdown_signal.name}, PID cleanup")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/test-daemon.py /path/to/house-keeping")
    executable = Path(sys.argv[1]).resolve(strict=True)
    agent = subprocess.run(
        ["/bin/launchctl", "list", "com.house-keeping.agent"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if agent.returncode == 0:
        sys.exit("Run house_keeping uninstall before running this regression test.")
    # Foundation uses the per-user Darwin temp directory, even when TMPDIR is set.
    temp_directory = subprocess.check_output(
        ["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True
    ).strip()
    pid_file = Path(temp_directory) / "house_keeping.pid"
    if pid_file.exists():
        try:
            existing_pid = int(pid_file.read_text().strip())
            if existing_pid > 0:
                os.kill(existing_pid, 0)
                sys.exit("Stop the existing daemon before running this regression test.")
        except (ValueError, ProcessLookupError):
            pass
    for termination_signal in (signal.SIGINT, signal.SIGTERM):
        check_shutdown(executable, termination_signal, pid_file)
