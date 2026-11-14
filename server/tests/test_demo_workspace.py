from pathlib import Path

import pytest

from earthsync.demo_workspace import provision, read_token


def test_private_local_workspace_is_stable_and_not_derived_from_farm_id(tmp_path):
    first = provision(tmp_path / "first")
    second = provision(tmp_path / "second")
    assert len(read_token(first)) >= 32
    assert read_token(first) != read_token(second)
    assert provision(first.parent) == first


def test_token_symlink_and_invalid_configuration_fail_closed(tmp_path):
    token = provision(tmp_path / "private")
    link = tmp_path / "token-link"
    link.symlink_to(token)
    with pytest.raises(ValueError, match="symlinks"):
        read_token(link)
    token.write_text(
        "farm-label-is-not-a-workspace-credential\nprivate-multiline-value"
    )
    with pytest.raises(ValueError, match="configuration"):
        read_token(token)
    with pytest.raises(ValueError, match="absolute"):
        read_token(Path("relative-token-file"))
