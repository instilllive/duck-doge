#!/usr/bin/env python3
"""Fail unless the paid-mint path and the earned-skin minter path are fully covered.

Reads a Foundry LCOV report (lcov 2 function ranges). A function passes when
every instrumented line and branch in that range was executed at least once.
The DuckDogeSkins.sol record must pass the same way, so a gap outside the
named functions still fails the gate. `setMinter` and `mintEarned` are the
free-mint path: a non-minter, a second set, and a bad index all have to run.
"""

from __future__ import annotations

import sys
from pathlib import Path

REQUIRED = ("mint", "pause", "unpause", "withdraw", "setMinter", "mintEarned", "earnedBalancesOf")


def parse_lcov(text: str) -> list[dict]:
    records: list[dict] = []
    current: dict | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("SF:"):
            current = {"file": line[3:], "da": {}, "br": [], "fn": {}}
            records.append(current)
        elif current is None:
            continue
        elif line.startswith("DA:"):
            line_no, hits = line[3:].split(",")[:2]
            number = int(line_no)
            current["da"][number] = current["da"].get(number, 0) + int(hits)
        elif line.startswith("BRDA:"):
            payload = line[5:].split(",")
            taken = payload[3]
            hits = 0 if taken == "-" else int(taken)
            current["br"].append((int(payload[0]), hits))
        elif line.startswith("FN:"):
            payload = line[3:].split(",")
            # lcov 2: FN:start,end,name. lcov 1: FN:start,name.
            if len(payload) >= 3 and payload[1].isdigit():
                start, end = int(payload[0]), int(payload[1])
                name = ",".join(payload[2:])
            else:
                start, end = int(payload[0]), int(payload[0])
                name = ",".join(payload[1:])
            short = name.rsplit(".", 1)[-1]
            current["fn"][short] = (start, end)
        elif line == "end_of_record":
            current = None
    return records


def contract_record(records: list[dict]) -> dict:
    matches = [record for record in records if record["file"].endswith("DuckDogeSkins.sol")]
    if len(matches) != 1:
        found = [record["file"] for record in matches]
        raise SystemExit(f"expected one DuckDogeSkins.sol record, found {found or 'none'}")
    return matches[0]


def stats(record: dict, start: int | None = None, end: int | None = None) -> tuple[int, int, int, int]:
    line_hits = [
        hits for line, hits in record["da"].items() if start is None or start <= line <= end
    ]
    branch_hits = [
        hits for line, hits in record["br"] if start is None or start <= line <= end
    ]
    return (
        sum(1 for hits in line_hits if hits > 0),
        len(line_hits),
        sum(1 for hits in branch_hits if hits > 0),
        len(branch_hits),
    )


def percent(hit: int, total: int) -> str:
    if total == 0:
        return "100.00% (0/0)"
    return f"{(100.0 * hit / total):.2f}% ({hit}/{total})"


def is_short(hit: int, total: int, *, allow_empty: bool) -> bool:
    if total == 0:
        return not allow_empty
    return hit != total


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_skin_coverage.py lcov.info", file=sys.stderr)
        return 2

    record = contract_record(parse_lcov(Path(sys.argv[1]).read_text()))
    rows: list[tuple[str, tuple[int, int, int, int]]] = []
    failed = False

    for name in REQUIRED:
        if name not in record["fn"]:
            print(f"lcov report has no function range for {name}", file=sys.stderr)
            return 1
        start, end = record["fn"][name]
        row = stats(record, start, end)
        rows.append((name, row))
        # Pause and unpause delegate their branches to OpenZeppelin modifiers,
        # so an empty branch list is valid. An empty line list is not.
        if is_short(row[0], row[1], allow_empty=False) or is_short(row[2], row[3], allow_empty=True):
            failed = True

    file_row = stats(record)
    rows.append(("DuckDogeSkins.sol", file_row))
    if is_short(file_row[0], file_row[1], allow_empty=False) or is_short(
        file_row[2], file_row[3], allow_empty=False
    ):
        failed = True

    print("| Function | Lines | Branches |")
    print("| --- | --- | --- |")
    for name, (line_hit, line_total, branch_hit, branch_total) in rows:
        print(f"| {name} | {percent(line_hit, line_total)} | {percent(branch_hit, branch_total)} |")

    if failed:
        print(
            "coverage gate failed: mint, pause, unpause, withdraw, setMinter, "
            "mintEarned, and earnedBalancesOf need 100% lines and branches"
        )
        return 1
    print("coverage gate passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
