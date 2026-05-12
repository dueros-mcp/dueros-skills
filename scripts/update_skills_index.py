#!/usr/bin/env python3
"""Generate SKILLS.md from category directories.

This is a maintainer tool. Contributors only need to add their skill folder
under the right category; maintainers run this script before publishing.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SKILLS.md"

CATEGORY_ORDER = [
    "智能家居控制",
    "家庭事务管理",
    "专属生活助手",
    "出行规划",
    "知识问答",
    "学习教育",
    "内容创作",
    "办公效率",
    "开发者工具",
    "系统工具",
]

EMPTY_CATEGORY_NOTE = "当前还没有 Skill，保留用于后续共建。"


def extract_frontmatter(text: str) -> dict[str, str]:
    match = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not match:
        return {}

    data: dict[str, str] = {}
    current_key = None
    current_value: list[str] = []

    for line in match.group(1).splitlines():
        if re.match(r"^[A-Za-z0-9_-]+:", line):
            if current_key:
                data[current_key] = " ".join(current_value).strip()
            key, value = line.split(":", 1)
            current_key = key.strip()
            current_value = [value.strip()]
        elif current_key and line.strip():
            current_value.append(line.strip())

    if current_key:
        data[current_key] = " ".join(current_value).strip()

    return data


def short_description(description: str) -> str:
    description = " ".join(description.split())
    for marker in ["。", "；", ";"]:
        if marker in description:
            first = description.split(marker, 1)[0].strip()
            if first:
                return first + "。"
    return description[:120] + ("..." if len(description) > 120 else "")


def skill_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for category in CATEGORY_ORDER:
        category_dir = ROOT / category
        if not category_dir.is_dir():
            continue
        for skill_file in sorted(category_dir.glob("*/SKILL.md")):
            text = skill_file.read_text(encoding="utf-8")
            fm = extract_frontmatter(text)
            skill_dir = skill_file.parent
            name = fm.get("name") or skill_dir.name
            description = fm.get("description") or ""
            rows.append(
                {
                    "category": category,
                    "dir": skill_dir.name,
                    "name": name,
                    "description": description,
                    "summary": short_description(description),
                    "link": skill_file.relative_to(ROOT).as_posix(),
                }
            )
    return rows


def render(rows: list[dict[str, str]]) -> str:
    by_category: dict[str, list[dict[str, str]]] = {category: [] for category in CATEGORY_ORDER}
    for row in rows:
        by_category.setdefault(row["category"], []).append(row)

    lines: list[str] = [
        "# Skill 列表",
        "",
        "这个文件用于快速查看当前仓库已有 Skill，避免逐层目录点开查找。",
        "",
        f"当前共 {len(rows)} 个 Skill。",
        "",
        "> 维护说明：贡献者不需要手动修改本文件。新增或调整 Skill 后，由仓库维护者运行 `python3 scripts/update_skills_index.py` 统一更新。",
        "",
        "## 快速总览",
        "",
        "| 分类 | Skill | 用途 |",
        "|---|---|---|",
    ]

    for category in CATEGORY_ORDER:
        for row in by_category.get(category, []):
            lines.append(
                f"| {category} | [{row['name']}]({row['link']}) | {row['summary']} |"
            )

    lines.extend(["", "## 按分类查看", ""])

    for category in CATEGORY_ORDER:
        lines.append(f"### {category}")
        lines.append("")
        skills = by_category.get(category, [])
        if not skills:
            lines.append(EMPTY_CATEGORY_NOTE)
            lines.append("")
            continue

        for row in skills:
            lines.append(f"#### [{row['name']}]({row['link']})")
            lines.append("")
            lines.append(f"- 目录：`{category}/{row['dir']}/`")
            if row["description"]:
                lines.append(f"- 用途：{row['description']}")
            else:
                lines.append("- 用途：暂无描述。")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    OUT.write_text(render(skill_rows()), encoding="utf-8")
    print(f"updated {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
