#!/usr/bin/env python3
"""Convert exported pet offset text files into project offsets JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


DEFAULT_SOURCE_DIR = Path("D:/软件/素材导出工具/导出素材")
DEFAULT_ASSET_DIR = Path("assets/pet")
OFFSET_FILE_RE = re.compile(r"^偏移信息(?P<pet_id>\d+)\.txt$")


def read_text_with_fallback(path: Path) -> str:
    encodings = ["mbcs", "utf-8-sig", "gbk"]
    last_error: Exception | None = None
    for encoding in encodings:
        try:
            return path.read_text(encoding=encoding)
        except (LookupError, UnicodeDecodeError) as exc:
            last_error = exc
    raise RuntimeError(f"无法读取偏移文件编码: {path.name}: {last_error}")


def parse_offsets(path: Path) -> list[dict[str, int]]:
    text = read_text_with_fallback(path)
    rows: list[dict[str, int]] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line_number == 1:
            continue

        parts = re.split(r"\s+", line)
        if len(parts) < 2:
            raise RuntimeError(f"{path.name}:{line_number} 偏移行格式错误: {raw_line!r}")

        try:
            rows.append({"x": int(parts[0]), "y": int(parts[1])})
        except ValueError as exc:
            raise RuntimeError(f"{path.name}:{line_number} 偏移不是整数: {raw_line!r}") from exc

    return rows


def load_sorted_frame_ids(tpsheet_path: Path) -> list[int]:
    data = json.loads(tpsheet_path.read_text(encoding="utf-8"))
    frame_ids: list[int] = []
    for texture in data.get("textures", []):
        for sprite in texture.get("sprites", []):
            filename = str(sprite.get("filename", ""))
            if filename.isdigit():
                frame_ids.append(int(filename))

    frame_ids.sort()
    return frame_ids


def discover_offset_files(source_dir: Path, pet_ids: set[str] | None) -> list[tuple[str, Path]]:
    discovered: list[tuple[str, Path]] = []
    for path in sorted(source_dir.glob("偏移信息*.txt")):
        match = OFFSET_FILE_RE.match(path.name)
        if not match:
            continue

        pet_id = match.group("pet_id")
        if pet_ids is not None and pet_id not in pet_ids:
            continue

        discovered.append((pet_id, path))

    return discovered


def build_payload(pet_id: str, source_file: Path, frame_ids: list[int], offsets: list[dict[str, int]]) -> dict:
    return {
        "pet_id": int(pet_id),
        "source_file": source_file.name,
        "first_frame_id": frame_ids[0],
        "frame_count": len(frame_ids),
        "offsets": {
            str(frame_id): offset
            for frame_id, offset in zip(frame_ids, offsets)
        },
    }


def export_one(
    pet_id: str,
    source_file: Path,
    asset_dir: Path,
    *,
    dry_run: bool,
    overwrite: bool,
) -> bool:
    tpsheet_path = asset_dir / f"{pet_id}.tpsheet"
    output_path = asset_dir / f"{pet_id}.offsets.json"

    if not tpsheet_path.exists():
        print(f"[SKIP] pet={pet_id} 缺少 tpsheet: {tpsheet_path}")
        return False

    frame_ids = load_sorted_frame_ids(tpsheet_path)
    offsets = parse_offsets(source_file)
    if len(frame_ids) != len(offsets):
        print(
            f"[ERROR] pet={pet_id} frame_count={len(frame_ids)} "
            f"offset_count={len(offsets)} 文件行数不匹配"
        )
        return False

    if output_path.exists() and not overwrite:
        print(f"[SKIP] pet={pet_id} 已存在: {output_path.name} (use --overwrite)")
        return True

    print(
        f"[OK] pet={pet_id} frames={len(frame_ids)} "
        f"first={frame_ids[0]} last={frame_ids[-1]} -> {output_path.name}"
    )
    if dry_run:
        return True

    payload = build_payload(pet_id, source_file, frame_ids, offsets)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return True


def normalize_pet_ids(values: Iterable[str]) -> set[str] | None:
    pet_ids = {value.strip() for value in values if value.strip()}
    if not pet_ids:
        return None
    invalid = [value for value in pet_ids if not value.isdigit()]
    if invalid:
        raise RuntimeError(f"pet id 必须是数字: {', '.join(sorted(invalid))}")
    return pet_ids


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export pet offsets JSON files.")
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--asset-dir", type=Path, default=DEFAULT_ASSET_DIR)
    parser.add_argument("--pet-id", action="append", default=[], help="Pet id to export; can be repeated.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print actions without writing files.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing offsets JSON files.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_dir: Path = args.source_dir
    asset_dir: Path = args.asset_dir
    pet_ids = normalize_pet_ids(args.pet_id)

    if not source_dir.exists():
        print(f"[ERROR] source-dir 不存在: {source_dir}")
        return 1
    if not asset_dir.exists():
        print(f"[ERROR] asset-dir 不存在: {asset_dir}")
        return 1

    discovered = discover_offset_files(source_dir, pet_ids)
    if not discovered:
        print("[ERROR] 没有找到匹配的 偏移信息{petid}.txt")
        return 1

    ok_count = 0
    fail_count = 0
    for pet_id, source_file in discovered:
        if export_one(
            pet_id,
            source_file,
            asset_dir,
            dry_run=args.dry_run,
            overwrite=args.overwrite,
        ):
            ok_count += 1
        else:
            fail_count += 1

    print(f"[DONE] ok={ok_count} failed={fail_count} dry_run={args.dry_run}")
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
