"""Bounded decoding and clean re-encoding. Never read GPS or retain EXIF."""

import hashlib
import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 16_000_000
MAX_DIMENSION = 8192
SIGNATURES = {"image/jpeg": b"\xff\xd8\xff", "image/png": b"\x89PNG\r\n\x1a\n"}


class InvalidImage(ValueError):
    pass


@dataclass(frozen=True)
class CleanImage:
    data: bytes
    width: int
    height: int
    sha256: str


def sanitize_image(raw: bytes, mime: str) -> CleanImage:
    if not raw or len(raw) > MAX_UPLOAD_BYTES:
        raise InvalidImage("Image must be nonempty and at most 10 MiB")
    if mime not in SIGNATURES or not raw.startswith(SIGNATURES[mime]):
        raise InvalidImage("Use a JPEG or PNG with a matching MIME type and signature")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as image:
                expected = "PNG" if mime == "image/png" else "JPEG"
                if image.format != expected or getattr(image, "n_frames", 1) != 1:
                    raise InvalidImage(
                        "Only single-frame JPEG/PNG images are supported"
                    )
                width, height = image.size
                if (
                    min(width, height) < 1
                    or max(width, height) > MAX_DIMENSION
                    or width * height > MAX_PIXELS
                ):
                    raise InvalidImage("Image exceeds dimension or pixel limits")
                image.verify()
            with Image.open(io.BytesIO(raw)) as image:
                # Orientation is applied, then fresh pixels remove all metadata,
                # including text, ICC profiles, XMP and EXIF thumbnails/GPS.
                oriented = ImageOps.exif_transpose(image)
                rgb = oriented.convert("RGB")
                clean = Image.frombytes("RGB", rgb.size, rgb.tobytes())
                output = io.BytesIO()
                clean.save(output, format="PNG")
                data = output.getvalue()
                if len(data) > MAX_UPLOAD_BYTES:
                    raise InvalidImage(
                        "Sanitized image exceeds 10 MiB; resize it first"
                    )
                return CleanImage(
                    data, clean.width, clean.height, hashlib.sha256(data).hexdigest()
                )
    except InvalidImage:
        raise
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ) as exc:
        raise InvalidImage("Image could not be safely decoded") from exc
