#!/usr/bin/env python3
"""Convert exported character offset text files into project offsets JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


DEFAULT_SOURCE_DIR = Path("D:/软件/素材导出工具/导出素材")
DEFAULT_ASSET_DIR = Path("assets/character")
OFFSET_FILE_RE = re.compile(r"^偏移信息(?P<character_id>\d+)\.txt$")
SUPPLEMENTAL_OFFSET_FILE_RE = re.compile(
    r"^偏移信息\(代表(?P<frame_ids>[0-9,，\s]+).*?是\s*(?P<character_id>\d+)\s*的一部分\)\.txt$"
)


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


def discover_source_files(source_dir: Path) -> dict[str, Path]:
    discovered: dict[str, Path] = {}
    for path in sorted(source_dir.glob("偏移信息*.txt")):
        match = OFFSET_FILE_RE.match(path.name)
        if match:
            discovered[match.group("character_id")] = path
    return discovered


def discover_supplemental_files(source_dir: Path) -> dict[str, list[tuple[Path, list[int]]]]:
    discovered: dict[str, list[tuple[Path, list[int]]]] = {}
    for path in sorted(source_dir.glob("偏移信息*.txt")):
        match = SUPPLEMENTAL_OFFSET_FILE_RE.match(path.name)
        if not match:
            continue

        frame_ids = [
            int(value)
            for value in re.split(r"[,，\s]+", match.group("frame_ids").strip())
            if value
        ]
        if not frame_ids:
            continue

        character_id = match.group("character_id")
        discovered.setdefault(character_id, []).append((path, frame_ids))
    return discovered


def discover_tpsheets(asset_dir: Path) -> dict[str, Path]:
    return {
        path.stem: path
        for path in sorted(asset_dir.glob("*.tpsheet"))
        if path.stem.isdigit()
    }


def build_payload(
    character_id: str,
    source_file: Path,
    frame_ids: list[int],
    offsets: list[dict[str, int]],
    supplemental_source_files: list[Path] | None = None,
) -> dict:
    payload = {
        "character_id": int(character_id),
        "source_file": source_file.name,
        "first_frame_id": frame_ids[0],
        "frame_count": len(frame_ids),
        "offsets": {
            str(frame_id): offset
            for frame_id, offset in zip(frame_ids, offsets)
        },
    }
    if supplemental_source_files:
        payload["supplemental_source_files"] = [
            path.name
            for path in supplemental_source_files
        ]
    return payload


def combine_offsets(
    character_id: str,
    source_file: Path,
    frame_ids: list[int],
    supplemental_files: list[tuple[Path, list[int]]],
) -> tuple[list[int], list[dict[str, int]], list[Path], str]:
    primary_offsets = parse_offsets(source_file)
    if not supplemental_files:
        if len(frame_ids) != len(primary_offsets):
            raise RuntimeError(
                f"frame_count={len(frame_ids)} offset_count={len(primary_offsets)} 文件行数不匹配"
            )
        return frame_ids, primary_offsets, [], ""

    supplemental_by_frame: dict[int, dict[str, int]] = {}
    supplemental_source_files: list[Path] = []
    for supplemental_file, supplemental_frame_ids in supplemental_files:
        supplemental_offsets = parse_offsets(supplemental_file)
        if len(supplemental_frame_ids) != len(supplemental_offsets):
            raise RuntimeError(
                f"{supplemental_file.name} frame_count={len(supplemental_frame_ids)} "
                f"offset_count={len(supplemental_offsets)} 文件行数不匹配"
            )

        supplemental_source_files.append(supplemental_file)
        for frame_id, offset in zip(supplemental_frame_ids, supplemental_offsets):
            if frame_id in supplemental_by_frame:
                raise RuntimeError(f"补充偏移重复 frame id: {frame_id}")
            supplemental_by_frame[frame_id] = offset

    frame_id_set = set(frame_ids)
    unknown_frame_ids = sorted(set(supplemental_by_frame) - frame_id_set)
    if unknown_frame_ids:
        raise RuntimeError(f"补充偏移包含 tpsheet 中不存在的 frame id: {unknown_frame_ids}")

    primary_frame_ids = [
        frame_id
        for frame_id in frame_ids
        if frame_id not in supplemental_by_frame
    ]
    if len(primary_frame_ids) != len(primary_offsets):
        raise RuntimeError(
            f"主偏移行数不匹配: primary_frames={len(primary_frame_ids)} "
            f"primary_offsets={len(primary_offsets)} supplemental={len(supplemental_by_frame)}"
        )

    offsets_by_frame = {
        frame_id: offset
        for frame_id, offset in zip(primary_frame_ids, primary_offsets)
    }
    offsets_by_frame.update(supplemental_by_frame)

    missing_frame_ids = [
        frame_id
        for frame_id in frame_ids
        if frame_id not in offsets_by_frame
    ]
    if missing_frame_ids:
        raise RuntimeError(f"组合偏移缺少 frame id: {missing_frame_ids}")
    if len(offsets_by_frame) != len(frame_ids):
        raise RuntimeError(
            f"组合偏移数量不匹配: combined={len(offsets_by_frame)} frames={len(frame_ids)}"
        )

    combined_offsets = [
        offsets_by_frame[frame_id]
        for frame_id in frame_ids
    ]
    detail = f" supplemental={len(supplemental_by_frame)}"
    return frame_ids, combined_offsets, supplemental_source_files, detail


def export_one(
    character_id: str,
    source_file: Path,
    tpsheet_path: Path,
    asset_dir: Path,
    supplemental_files: list[tuple[Path, list[int]]],
    *,
    dry_run: bool,
    overwrite: bool,
) -> bool:
    output_path = asset_dir / f"{character_id}.offsets.json"

    frame_ids = load_sorted_frame_ids(tpsheet_path)
    try:
        combined_frame_ids, offsets, supplemental_source_files, detail = combine_offsets(
            character_id,
            source_file,
            frame_ids,
            supplemental_files,
        )
    except RuntimeError as exc:
        print(f"[ERROR] character={character_id} {exc}")
        return False

    if output_path.exists() and not overwrite:
        print(f"[SKIP] character={character_id} 已存在: {output_path.name} (use --overwrite)")
        return True

    print(
        f"[OK] character={character_id} frames={len(combined_frame_ids)} "
        f"first={combined_frame_ids[0]} last={combined_frame_ids[-1]}{detail} -> {output_path.name}"
    )
    if dry_run:
        return True

    payload = build_payload(
        character_id,
        source_file,
        combined_frame_ids,
        offsets,
        supplemental_source_files,
    )
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return True


def normalize_character_ids(values: Iterable[str]) -> set[str] | None:
    character_ids = {value.strip() for value in values if value.strip()}
    if not character_ids:
        return None
    invalid = [value for value in character_ids if not value.isdigit()]
    if invalid:
        raise RuntimeError(f"character id 必须是数字: {', '.join(sorted(invalid))}")
    return character_ids


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export character offsets JSON files.")
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--asset-dir", type=Path, default=DEFAULT_ASSET_DIR)
    parser.add_argument(
        "--character-id",
        action="append",
        default=[],
        help="Character id to export; can be repeated.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Validate and print actions without writing files.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing offsets JSON files.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_dir: Path = args.source_dir
    asset_dir: Path = args.asset_dir
    character_ids = normalize_character_ids(args.character_id)

    if not source_dir.exists():
        print(f"[ERROR] source-dir 不存在: {source_dir}")
        return 1
    if not asset_dir.exists():
        print(f"[ERROR] asset-dir 不存在: {asset_dir}")
        return 1

    source_files = discover_source_files(source_dir)
    supplemental_files = discover_supplemental_files(source_dir)
    tpsheets = discover_tpsheets(asset_dir)
    candidate_ids = character_ids if character_ids is not None else set(tpsheets)
    if not candidate_ids:
        print("[ERROR] 没有找到角色 tpsheet")
        return 1

    ok_count = 0
    fail_count = 0
    skip_count = 0
    for character_id in sorted(candidate_ids, key=int):
        source_file = source_files.get(character_id)
        tpsheet_path = tpsheets.get(character_id)
        if source_file is None:
            print(f"[SKIP] character={character_id} 缺少 source: 偏移信息{character_id}.txt")
            skip_count += 1
            continue
        if tpsheet_path is None:
            print(f"[SKIP] character={character_id} 缺少 tpsheet: {asset_dir / f'{character_id}.tpsheet'}")
            skip_count += 1
            continue

        try:
            ok = export_one(
                character_id,
                source_file,
                tpsheet_path,
                asset_dir,
                supplemental_files.get(character_id, []),
                dry_run=args.dry_run,
                overwrite=args.overwrite,
            )
        except RuntimeError as exc:
            print(f"[ERROR] character={character_id} {exc}")
            ok = False

        if ok:
            ok_count += 1
        else:
            fail_count += 1

    print(f"[DONE] ok={ok_count} skipped={skip_count} failed={fail_count} dry_run={args.dry_run}")
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
