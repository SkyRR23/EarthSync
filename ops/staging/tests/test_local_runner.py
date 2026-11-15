"""Local lifecycle checks use disposable paths and never signal a real process."""

import importlib.util
from pathlib import Path
import socket

import pytest

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def runner(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location(
        "local_runner", ROOT / "scripts/local/earthsync.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    source = tmp_path / "checkout"
    source.mkdir()
    runtime = source / ".earthsync-runtime"
    runtime.mkdir()
    monkeypatch.setattr(module, "ROOT", source)
    monkeypatch.setattr(module, "RUNTIME", runtime)
    monkeypatch.setattr(module, "RUN", runtime / "run.json")
    monkeypatch.setattr(module, "STATE", tmp_path / "checkout-demo-state")
    return module


def test_port_selection_preserves_existing_listener(runner):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        occupied = listener.getsockname()[1]
        selected = runner.available(occupied, set())
        assert selected != occupied
        assert listener.getsockname()[1] == occupied


def test_unmarked_existing_data_is_never_adopted_or_changed(runner):
    runner.STATE.mkdir()
    original = runner.STATE / "farmer-photo.png"
    original.write_bytes(b"PRIVATE TEST PLACEHOLDER")
    with pytest.raises(RuntimeError, match="left untouched"):
        runner.secure_state()
    assert original.read_bytes() == b"PRIVATE TEST PLACEHOLDER"
    assert not (runner.STATE / runner.MARKER).exists()


def test_stop_uses_unique_instance_file_and_never_a_reused_pid(runner, monkeypatch):
    instance = "a" * 32
    run = {"instance": instance, "pid": 12345, "status": "ready"}
    runner.write(runner.RUN, run)

    def acknowledge(_):
        assert (runner.RUNTIME / ("stop-" + instance)).is_file()
        runner.write(runner.RUN, {**run, "status": "stopped"})

    monkeypatch.setattr(runner.time, "sleep", acknowledge)
    monkeypatch.setattr(
        runner.os, "kill", lambda *args: pytest.fail("Must not signal a PID")
    )
    runner.stop()
    assert runner.read(runner.RUN)["status"] == "stopped"


def test_invalid_process_record_does_not_signal_anything(runner):
    runner.write(runner.RUN, {"instance": "../../other-store", "status": "ready"})
    with pytest.raises(RuntimeError, match="no process was signalled"):
        runner.stop()
    assert list(runner.RUNTIME.iterdir()) == [runner.RUN]
