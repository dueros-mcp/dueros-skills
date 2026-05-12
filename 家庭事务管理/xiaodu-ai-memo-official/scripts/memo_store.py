#!/usr/bin/env python3
"""Local JSON store for the xiaodu-ai-memo-official skill."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_PATH = Path(__file__).resolve()
SKILL_DIR = SCRIPT_PATH.parents[1]
WORKSPACE_DIR = SKILL_DIR.parents[1]
STORE_DIR = WORKSPACE_DIR / "memory" / "ai-memo"
STORE_FILE = STORE_DIR / "memos.json"
IMAGE_DIR = STORE_DIR / "images"


class StoreError(Exception):
    """Raised when the memo store cannot be safely read or written."""


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")


def ensure_dirs() -> None:
    STORE_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)


def backup_damaged_store() -> Path:
    ensure_dirs()
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = STORE_FILE.with_name(f"memos.json.bak.{stamp}")
    shutil.copy2(STORE_FILE, backup_path)
    return backup_path


def load_store() -> dict[str, Any]:
    ensure_dirs()
    if not STORE_FILE.exists():
        return {}

    try:
        with STORE_FILE.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        backup_path = backup_damaged_store()
        raise StoreError(f"memos.json is not valid JSON; backup created at {backup_path}") from exc

    if not isinstance(data, dict):
        raise StoreError("memos.json must contain a JSON object at the top level")

    return data


def atomic_write_store(data: dict[str, Any]) -> None:
    ensure_dirs()
    fd, tmp_name = tempfile.mkstemp(prefix="memos.", suffix=".tmp", dir=str(STORE_DIR))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp_path, STORE_FILE)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def unique_key(store: dict[str, Any], base_key: str) -> str:
    if base_key not in store:
        return base_key

    index = 1
    while True:
        candidate = f"{base_key}-{index:03d}"
        if candidate not in store:
            return candidate
        index += 1


def normalize_list(value: list[str] | None) -> list[str]:
    if not value:
        return []
    return [item for item in value if item]


def save_memo(args: argparse.Namespace) -> dict[str, Any]:
    store = load_store()
    created_at = args.created_at or now_iso()
    key = unique_key(store, created_at)

    memo = {
        "id": key,
        "createdAt": created_at,
        "updatedAt": now_iso(),
        "type": args.type,
        "query": args.query or "",
        "content": args.content or "",
        "imagePaths": normalize_list(args.image_path),
        "imageDescription": args.image_description or "",
        "tags": normalize_list(args.tag),
        "reminder": {
            "needed": args.reminder_needed,
            "timeText": args.reminder_time_text or "",
            "suggestion": args.reminder_suggestion or "",
            "refId": args.reminder_ref_id or "",
        },
        "source": args.source,
        "notes": args.notes or "",
    }

    store[key] = memo
    atomic_write_store(store)
    return {"ok": True, "key": key, "memo": memo, "storeFile": str(STORE_FILE)}


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than 0")
    return parsed


def list_memos(args: argparse.Namespace) -> dict[str, Any]:
    store = load_store()
    total = len(store)
    memos = store

    if args.limit is not None:
        sorted_keys = sorted(store.keys(), reverse=True)[: args.limit]
        memos = {key: store[key] for key in sorted_keys}

    return {"ok": True, "count": len(memos), "total": total, "storeFile": str(STORE_FILE), "memos": memos}


def clear_reminder(args: argparse.Namespace) -> dict[str, Any]:
    store = load_store()
    if args.id not in store:
        return {"ok": False, "error": f"memo not found: {args.id}"}

    memo = store[args.id]
    memo["reminder"] = {
        **memo.get("reminder", {}),
        "needed": False,
        "refId": "",
    }
    memo["updatedAt"] = now_iso()
    store[args.id] = memo
    atomic_write_store(store)
    return {"ok": True, "key": args.id, "reminder": memo["reminder"]}


def set_reminder(args: argparse.Namespace) -> dict[str, Any]:
    store = load_store()
    if args.id not in store:
        return {"ok": False, "error": f"memo not found: {args.id}"}

    memo = store[args.id]
    reminder = memo.get("reminder", {})
    if args.needed is not None:
        reminder["needed"] = args.needed == "true"
    if args.ref_id is not None:
        reminder["refId"] = args.ref_id
    if args.time_text is not None:
        reminder["timeText"] = args.time_text
    if args.suggestion is not None:
        reminder["suggestion"] = args.suggestion
    memo["reminder"] = reminder
    memo["updatedAt"] = now_iso()
    store[args.id] = memo
    atomic_write_store(store)
    return {"ok": True, "key": args.id, "reminder": reminder}


def copy_image(args: argparse.Namespace) -> dict[str, Any]:
    ensure_dirs()
    source = Path(args.path).expanduser()
    if not source.exists() or not source.is_file():
        return {
            "ok": False,
            "path": str(source),
            "copiedPath": None,
            "warning": "image path does not exist or is not a file; original path may be unstable",
        }

    suffix = source.suffix or ".image"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    target = IMAGE_DIR / f"{stamp}{suffix}"
    shutil.copy2(source, target)
    return {"ok": True, "path": str(source), "copiedPath": str(target), "warning": ""}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage the local ai-memo JSON store.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    save_parser = subparsers.add_parser("save", help="Save one memo")
    save_parser.add_argument("--query", default="", help="Original user request")
    save_parser.add_argument("--content", default="", help="Durable memo content")
    save_parser.add_argument("--type", default="text", choices=["text", "text_image"], help="Memo type")
    save_parser.add_argument("--image-path", action="append", help="Stable image path to store in the memo")
    save_parser.add_argument("--image-description", default="", help="Image description generated when saving")
    save_parser.add_argument("--tag", action="append", help="Memo tag; can be repeated")
    save_parser.add_argument("--reminder-needed", action="store_true", help="Whether the user has confirmed a reminder is needed")
    save_parser.add_argument("--reminder-time-text", default="", help="Original time expression for a time-sensitive memo")
    save_parser.add_argument("--reminder-suggestion", default="", help="Suggested reminder timing or follow-up question")
    save_parser.add_argument("--reminder-ref-id", default="", help="Task or alarm ID returned after creating the reminder")
    save_parser.add_argument("--notes", default="", help="Uncertainty or extra notes")
    save_parser.add_argument("--source", default="openclaw", help="Memo source")
    save_parser.add_argument("--created-at", default="", help="Optional ISO timestamp key base")
    save_parser.set_defaults(func=save_memo)

    list_parser = subparsers.add_parser("list", help="Read memos for upper-agent semantic inspection")
    list_parser.add_argument("--limit", type=positive_int, help="Return only the most recent N memos by timestamp key")
    list_parser.set_defaults(func=list_memos)

    set_reminder_parser = subparsers.add_parser("set-reminder", help="Update the reminder fields of an existing memo")
    set_reminder_parser.add_argument("--id", required=True, help="Memo ID (timestamp key) to update")
    set_reminder_parser.add_argument("--needed", choices=["true", "false"], default=None, help="Set reminder.needed (true/false)")
    set_reminder_parser.add_argument("--ref-id", default=None, help="Task or alarm ID to store in reminder.refId")
    set_reminder_parser.add_argument("--time-text", default=None, help="Update reminder.timeText")
    set_reminder_parser.add_argument("--suggestion", default=None, help="Update reminder.suggestion")
    set_reminder_parser.set_defaults(func=set_reminder)

    clear_reminder_parser = subparsers.add_parser("clear-reminder", help="Cancel the reminder for a memo (sets needed=false, clears refId)")
    clear_reminder_parser.add_argument("--id", required=True, help="Memo ID (timestamp key) to update")
    clear_reminder_parser.set_defaults(func=clear_reminder)

    copy_parser = subparsers.add_parser("copy-image", help="Copy an image into the fixed ai-memo image directory")
    copy_parser.add_argument("path", help="Local image path to copy")
    copy_parser.set_defaults(func=copy_image)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = args.func(args)
    except StoreError as exc:
        result = {"ok": False, "error": str(exc)}
        print(json.dumps(result, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
