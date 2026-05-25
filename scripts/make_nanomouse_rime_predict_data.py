#!/usr/bin/env python3
"""Generate librime-predict TSV data from iDvel/rime-ice dictionaries."""

from __future__ import annotations

import argparse
import signal
from collections import defaultdict
from pathlib import Path
from typing import DefaultDict, Iterable


SOURCE_WEIGHTS = (
    ("cn_dicts/base.dict.yaml", 1.0),
    ("cn_dicts/ext.dict.yaml", 0.45),
    ("cn_dicts/tencent.dict.yaml", 0.28),
    ("cn_dicts/others.dict.yaml", 0.20),
)

SUFFIX_LENGTH_WEIGHTS = {
    1: 1.25,
    2: 1.0,
    3: 0.72,
    4: 0.52,
    5: 0.38,
    6: 0.30,
}


def is_common_han_word(text: str) -> bool:
    return bool(text) and all("\u4e00" <= char <= "\u9fff" for char in text)


def iter_dict_entries(path: Path) -> Iterable[tuple[str, float]]:
    in_body = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not in_body:
            if raw_line.strip() == "...":
                in_body = True
            continue
        if not raw_line or raw_line.lstrip().startswith("#"):
            continue

        parts = raw_line.split("\t")
        if not parts:
            continue
        text = parts[0].strip()
        weight = 100.0
        for part in reversed(parts[1:]):
            value = part.strip()
            if value.isdigit():
                weight = float(value)
                break
        yield text, weight


def build_predict_data(rime_ice_dir: Path, max_candidates_per_key: int) -> dict[str, dict[str, int]]:
    data: DefaultDict[str, dict[str, int]] = defaultdict(dict)
    for relative_path, source_weight in SOURCE_WEIGHTS:
        dict_path = rime_ice_dir / relative_path
        if not dict_path.exists():
            raise FileNotFoundError(dict_path)
        for text, original_weight in iter_dict_entries(dict_path):
            text_length = len(text)
            if text_length < 2 or text_length > 7 or not is_common_han_word(text):
                continue
            base_weight = max(1.0, original_weight * source_weight)
            for split_index in range(1, text_length):
                key = text[:split_index]
                value = text[split_index:]
                suffix_length = len(value)
                length_weight = SUFFIX_LENGTH_WEIGHTS.get(suffix_length, 0.25)
                context_weight = 1.0 + min(split_index, 4) * 0.04
                score = int(max(1, base_weight * length_weight * context_weight))
                if score > data[key].get(value, 0):
                    data[key][value] = score

    if max_candidates_per_key <= 0:
        return dict(data)

    trimmed: dict[str, dict[str, int]] = {}
    for key, candidates in data.items():
        best = sorted(candidates.items(), key=lambda item: (-item[1], len(item[0]), item[0]))
        trimmed[key] = dict(best[:max_candidates_per_key])
    return trimmed


def main() -> None:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rime-ice-dir",
        default=".tmp/.rime-ice",
        type=Path,
        help="Path to the checked-out iDvel/rime-ice directory.",
    )
    parser.add_argument(
        "--max-candidates-per-key",
        default=20,
        type=int,
        help="Maximum candidates kept in the generated TSV for each prediction key.",
    )
    args = parser.parse_args()

    data = build_predict_data(args.rime_ice_dir, args.max_candidates_per_key)
    for key in sorted(data):
        candidates = sorted(data[key].items(), key=lambda item: (-item[1], len(item[0]), item[0]))
        for value, weight in candidates:
            print(f"{key}\t{value}\t{weight}")


if __name__ == "__main__":
    main()
