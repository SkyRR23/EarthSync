"""Transport tests use explicitly synthetic bytes, never simulated provider data."""

import io
import sys
import tempfile
import unittest
from email.message import Message
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import capture_sources
from catalog import sha256


class Response(io.BytesIO):
    def __init__(
        self,
        raw=b"%PDF-synthetic transport test only",
        content_type="application/pdf",
        status=200,
    ):
        super().__init__(raw)
        self.headers = Message()
        self.headers["Content-Type"] = content_type
        self.status = status

    def geturl(self):
        return "https://example.invalid/synthetic-test"


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name)
        self.source = {
            "id": "synthetic_transport_test",
            "url": "https://example.invalid/test",
        }

    def fetch(self, response):
        return capture_sources.capture(
            self.source, self.output, opener=lambda *a, **kw: response
        )

    def test_exact_raw_response_bytes_and_checksum_preserved(self):
        raw = b"%PDF-synthetic transport bytes\r\n"
        receipt = self.fetch(Response(raw))
        self.assertEqual(receipt["state"], "available_for_review")
        self.assertEqual(receipt["provider_response_sha256"], sha256(raw))
        self.assertEqual((self.output / receipt["raw_path"]).read_bytes(), raw)
        self.assertEqual(receipt["review_status"], "unreviewed")
        self.assertFalse(receipt["recommendation_eligible"])

    def test_proxy_and_http_errors_remain_unavailable_without_zero_values(self):
        for error in (
            URLError("synthetic tunnel 403"),
            HTTPError(self.source["url"], 403, "blocked", {}, None),
        ):
            with self.subTest(error=error):

                def blocked(*args, **kwargs):
                    raise error

                receipt = capture_sources.capture(
                    self.source, self.output, opener=blocked
                )
                self.assertEqual(receipt["state"], "unavailable")
                for key in ("provider_response_sha256", "bytes", "raw_path"):
                    self.assertIsNone(receipt[key])
                self.assertTrue(receipt["error"])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_empty_oversized_and_bad_pdf_responses_rejected(self):
        with patch.object(capture_sources, "MAX_BYTES", 64):
            for raw in (b"", b"x" * 65, b"<html>synthetic sign-in wall</html>"):
                with self.subTest(raw=raw):
                    receipt = self.fetch(Response(raw))
                    self.assertEqual(receipt["state"], "unavailable")
                    self.assertIsNone(receipt["provider_response_sha256"])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_unexpected_content_type_or_status_rejected(self):
        for response in (
            Response(content_type="application/zip"),
            Response(status=204),
        ):
            with self.subTest(response=response):
                self.assertEqual(self.fetch(response)["state"], "unavailable")

    def test_previous_capture_is_not_overwritten(self):
        raw = b"%PDF-first synthetic response"
        first = self.fetch(Response(raw))
        second = self.fetch(Response(b"%PDF-second synthetic response"))
        self.assertEqual(second["state"], "unavailable")
        self.assertEqual((self.output / first["raw_path"]).read_bytes(), raw)


if __name__ == "__main__":
    unittest.main()
