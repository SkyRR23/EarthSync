"""Authenticated, byte-budgeted random access to official NASA assets.

Earthaccess handles login. Bearer credentials go only to official NASA hosts;
signed CDN redirects use a separate unauthenticated session. Signed URLs never
enter provenance or logs. Raster/HDF readers cannot download an entire file.
"""

from contextlib import redirect_stdout
import hashlib
import io
import os
import re
import time
from urllib.parse import urljoin, urlsplit

from .http import SourceError
from .nasa import ASSET_HOSTS


class AssetSession:
    def __init__(self, cancel_event=None):
        self.cancel_event = cancel_event
        if not os.getenv("EARTHDATA_TOKEN"):
            raise SourceError("AUTHENTICATION_REQUIRED")
        import earthaccess
        import requests

        with redirect_stdout(io.StringIO()):
            auth = earthaccess.login(strategy="environment", persist=False)
        if not auth.authenticated:
            raise SourceError("AUTHENTICATION_REQUIRED")
        self.authenticated = auth.get_session()
        self.anonymous = requests.Session()
        self.receipts = []
        self.etags = {}
        self.downloaded = 0
        self.deadline = time.monotonic() + 120

    def close(self):
        self.authenticated.close()
        self.anonymous.close()

    def range(self, original, start, end, resolved=None):
        if time.monotonic() >= self.deadline or (
            self.cancel_event and self.cancel_event.is_set()
        ):
            raise SourceError("PROVIDER_TIMEOUT")
        if self.downloaded + end - start + 1 > 64 * 1024 * 1024:
            raise SourceError("ASSET_BYTE_LIMIT")
        url = resolved or original
        if urlsplit(original).hostname not in ASSET_HOSTS or urlsplit(original).query:
            raise SourceError("UNSUPPORTED_ENDPOINT")
        for _ in range(5):
            if time.monotonic() >= self.deadline:
                raise SourceError("PROVIDER_TIMEOUT")
            parsed = urlsplit(url)
            if parsed.scheme != "https" or parsed.username:
                raise SourceError("UNSUPPORTED_ENDPOINT")
            if parsed.hostname in ASSET_HOSTS:
                session = self.authenticated
            elif parsed.hostname and (
                parsed.hostname.endswith(".cloudfront.net")
                or parsed.hostname.endswith(".s3.us-west-2.amazonaws.com")
                or parsed.hostname.endswith(".s3.amazonaws.com")
            ):
                session = self.anonymous
            elif parsed.hostname == "urs.earthdata.nasa.gov":
                raise SourceError("AUTHENTICATION_REQUIRED")
            else:
                raise SourceError("UNSUPPORTED_ASSET_REDIRECT")
            with session.get(
                url,
                headers={"Range": f"bytes={start}-{end}"},
                stream=True,
                timeout=25,
                allow_redirects=False,
            ) as response:
                status = response.status_code
                if status in (301, 302, 303, 307, 308):
                    url = urljoin(url, response.headers["location"])
                    continue
                if status in (401, 403):
                    raise SourceError(
                        "AUTHENTICATION_REQUIRED"
                        if status == 401
                        else "AUTHORIZATION_DENIED"
                    )
                if status == 429:
                    from .http import retry_seconds

                    raise SourceError(
                        "RATE_LIMIT",
                        retry_after=retry_seconds(
                            response.headers.get("retry-after"), time.time()
                        ),
                    )
                if status >= 500:
                    raise SourceError("PROVIDER_OUTAGE")
                etag = response.headers.get("etag")
                if original in self.etags and etag != self.etags[original]:
                    raise SourceError("ASSET_CHANGED_DURING_READ")
                if etag:
                    self.etags[original] = etag
                match = re.fullmatch(
                    r"bytes (\d+)-(\d+)/(\d+)",
                    response.headers.get("content-range", ""),
                )
                if (
                    status != 206
                    or not match
                    or int(match[1]) != start
                    or int(match[2]) > end
                ):
                    raise SourceError("BYTE_RANGE_NOT_SUPPORTED")
                content = bytearray()
                for chunk in response.iter_content(65536):
                    content.extend(chunk)
                    if len(content) > end - start + 1:
                        raise SourceError("ASSET_BYTE_LIMIT")
                if len(content) != int(match[2]) - start + 1:
                    raise SourceError("INTERRUPTED_DOWNLOAD")
                self.downloaded += len(content)
                self.receipts.append(
                    {
                        "source_url": original,
                        "range_start": start,
                        "range_end": int(match[2]),
                        "sha256": hashlib.sha256(content).hexdigest(),
                    }
                )
                return bytes(content), int(match[3]), url
        raise SourceError("ASSET_REDIRECT_LIMIT")


class RangeFile(io.RawIOBase):
    """Seekable 1 MiB block reader with a hard 16 MiB download budget."""

    block_size = 1048576

    def __init__(self, session, url, *, budget=16 * 1024 * 1024, block_size=None):
        if block_size is not None:
            self.block_size = block_size
        self.session, self.url, self.budget = session, url, budget
        self.position, self.downloaded, self.blocks = 0, 0, {}
        initial, self.length, self.resolved = session.range(url, 0, self.block_size - 1)
        self.blocks[0] = initial
        self.downloaded = len(initial)

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        position = (
            offset
            if whence == 0
            else self.position + offset
            if whence == 1
            else self.length + offset
        )
        if position < 0:
            raise ValueError("Negative seek")
        self.position = position
        return position

    def read(self, size=-1):
        if size is None or size < 0:
            raise SourceError("UNBOUNDED_ASSET_READ_REJECTED")
        end = min(self.length, self.position + size)
        output = bytearray()
        while self.position < end:
            block = self.position // self.block_size
            if block not in self.blocks:
                start = block * self.block_size
                stop = min(self.length - 1, start + self.block_size - 1)
                if self.downloaded + stop - start + 1 > self.budget:
                    raise SourceError("ASSET_BYTE_LIMIT")
                content, length, _ = self.session.range(
                    self.url, start, stop, self.resolved
                )
                if length != self.length:
                    raise SourceError("ASSET_CHANGED_DURING_READ")
                self.blocks[block] = content
                self.downloaded += len(content)
            content = self.blocks[block]
            offset = self.position - block * self.block_size
            part = content[offset : min(len(content), offset + end - self.position)]
            if not part:
                raise SourceError("INTERRUPTED_DOWNLOAD")
            output.extend(part)
            self.position += len(part)
        return bytes(output)

    def readinto(self, buffer):
        content = self.read(len(buffer))
        buffer[: len(content)] = content
        return len(content)
