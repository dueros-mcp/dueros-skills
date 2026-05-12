import json
import os
import sys
import argparse


def _load():
    data_dir = os.environ.get(
        'MED_DATA_DIR',
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     '..', '..', '..', 'memory', 'med-assistant')
    )
    path = os.path.join(data_dir, 'medications.json')
    if not os.path.exists(path):
        return None
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def generate_tts(time_str, med_ids=None):
    """生成指定时间点的 TTS 播报文本。

    Args:
        time_str: 时间，格式 HH:MM
        med_ids: 指定药物 ID 列表（cron 触发时使用，跳过时间匹配）。
                 None 表示按时间自动匹配所有活跃药物。

    Returns:
        完整 TTS 文本字符串，无内容时返回空字符串。
    """
    data = _load()
    if not data:
        return ''

    settings = data.get('settings', {})
    patient_name = settings.get('patient_name', '')
    broadcast_prefix = settings.get('broadcast_prefix', '该吃药啦')

    items = []
    medications = data.get('medications', {})

    if med_ids is not None:
        meds_to_check = [medications[mid] for mid in med_ids if mid in medications]
    else:
        meds_to_check = [
            m for m in medications.values()
            if m.get('active', True) and time_str in m.get('schedule', {}).get('times', [])
        ]

    for med in meds_to_check:
        text = f"{med['name']}{med['dose']}"
        note = med.get('broadcast_note', '')
        if note:
            text += f"，{note}"
        items.append(text)

    if med_ids is None:
        for mon in data.get('monitoring', {}).values():
            if mon.get('enabled') and time_str in mon.get('times', []):
                reminder = mon.get('reminder_text', '')
                if reminder:
                    items.append(reminder)

    if not items:
        return ''

    prefix = f"{patient_name}，{broadcast_prefix}。" if patient_name else f"{broadcast_prefix}。"
    return prefix + '；'.join(items) + '。'


def main():
    parser = argparse.ArgumentParser(description='生成服药播报文本')
    parser.add_argument('--time', required=True, help='时间，格式 HH:MM')
    parser.add_argument('--ids', nargs='*', help='指定药物 ID（cron 触发时使用）')
    args = parser.parse_args()

    result = generate_tts(args.time, med_ids=args.ids if args.ids else None)
    if result:
        print(result)
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
