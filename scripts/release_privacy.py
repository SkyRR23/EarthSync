"""Keep raw browser verification outside source/public artifacts by default."""

from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def private_output(value):
    path = Path(value).absolute()
    if (
        path.resolve() != path
        or path == ROOT
        or ROOT in path.parents
        or path in ROOT.parents
        or path in {Path("/tmp").absolute(), Path(tempfile.gettempdir()).absolute()}
    ):
        raise ValueError(
            "Raw receipts need a dedicated private directory outside the checkout. Publish only summarize_release_evidence.py output."
        )
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path
