"""Isolated Live Photo worker; do not pair unrelated videos."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import photographic_style_port as engine  # noqa: E402


def main() -> int:
    if len(sys.argv) != 5:
        print("Expected source.HEIC patched.HEIC source.MOV result.MOV", file=sys.stderr)
        return 2
    source_photo, patched_photo, source_video, result_video = map(Path, sys.argv[1:])
    try:
        original_id = engine.live_photo_id(source_photo.read_bytes())
        patched_id = engine.live_photo_id(patched_photo.read_bytes())
        video_id = engine.mov_live_photo_id(source_video.read_bytes())
        if not original_id or not patched_id or not video_id:
            raise engine.PortError(
                "Missing Live Photo pairing ID. Export original HEIC and MOV via Files.")
        if original_id != patched_id or original_id != video_id:
            raise engine.PortError("HEIC/MOV Live Photo IDs do not match.")
        result, _changes = engine.patch_live_video(source_video, original_id)
        result_video.write_bytes(result)
    except (engine.PortError, OSError, ValueError) as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
