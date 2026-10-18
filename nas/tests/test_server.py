"""Isolated HTTP transport tests; no personal photos are needed."""
import io
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

os.environ["SHALIELIE_TOKEN"] = "test-only-access-token-0123456789"
from fastapi.testclient import TestClient  # noqa: E402
from nas import server  # noqa: E402

HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 24
MOV = b"\x00\x00\x00\x18ftypqt  " + b"\x00" * 24
HEADERS = {"Authorization": "Bearer test-only-access-token-0123456789"}


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.original = server.TEMP_ROOT
        server.TEMP_ROOT = Path(self.work.name)
        self.client = TestClient(server.app)
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        server.TEMP_ROOT = self.original
        self.work.cleanup()

    def fake_porter(self, command, cwd):
        kind = b"mov" if command[1] == str(server.WORKER) else b"heic"
        Path(command[-1]).write_bytes(b"patched-" + kind)

    def test_health_no_auth_and_status_requires_auth(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)
        self.assertEqual(self.client.get("/api/status").status_code, 401)
        self.assertEqual(self.client.get("/api/status", headers=HEADERS).status_code, 200)

    def test_reject_jpeg_before_porter(self):
        response = self.client.post("/api/patch", headers=HEADERS,
                                    files={"photo": ("image.jpg", b"\xff\xd8\xff", "image/jpeg")})
        self.assertEqual(response.status_code, 415)
        self.assertFalse(list(server.TEMP_ROOT.glob("job-*")))

    def test_reject_bad_mov(self):
        response = self.client.post("/api/patch", headers=HEADERS,
                                    files={"photo": ("a.HEIC", HEIC, "image/heic"),
                                           "video": ("b.jpg", b"\xff\xd8\xff", "image/jpeg")})
        self.assertEqual(response.status_code, 415)

    def test_heic_response_and_cleanup(self):
        with patch.object(server, "run_command", side_effect=self.fake_porter):
            response = self.client.post("/api/patch", headers=HEADERS,
                                        files={"photo": ("photo.HEIC", HEIC, "image/heic")})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"patched-heic")
        self.assertEqual(response.headers["content-type"], "image/heic")
        self.assertFalse(list(server.TEMP_ROOT.glob("job-*")))

    def test_live_photo_zip_and_cleanup(self):
        with patch.object(server, "run_command", side_effect=self.fake_porter):
            response = self.client.post("/api/patch", headers=HEADERS,
                                        files={"photo": ("IMG_1.HEIC", HEIC, "image/heic"),
                                               "video": ("IMG_1.MOV", MOV, "video/quicktime")})
        self.assertEqual(response.status_code, 200)
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            self.assertEqual(sorted(archive.namelist()),
                             ["IMG_1_Shalielie.HEIC", "IMG_1_Shalielie.MOV"])
            self.assertEqual(archive.read("IMG_1_Shalielie.MOV"), b"patched-mov")
        self.assertFalse(list(server.TEMP_ROOT.glob("job-*")))

    def test_busy(self):
        self.assertTrue(server.GATE.acquire(blocking=False))
        try:
            response = self.client.post("/api/patch", headers=HEADERS,
                                        files={"photo": ("a.HEIC", HEIC, "image/heic")})
            self.assertEqual(response.status_code, 429)
        finally:
            server.GATE.release()

    def test_unauthorized_rejected(self):
        self.assertEqual(self.client.post("/api/patch",
                         files={"photo": ("photo.HEIC", HEIC, "image/heic")}).status_code, 401)


if __name__ == "__main__":
    unittest.main()
