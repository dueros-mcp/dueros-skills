import json
import os
import sys
import argparse
import tempfile
import uuid
from datetime import datetime


def _data_dir():
    return os.environ.get(
        'MED_DATA_DIR',
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     '..', '..', '..', 'memory', 'med-assistant')
    )


def _data_file():
    return os.path.join(_data_dir(), 'medications.json')


DEFAULT_DATA = {
    "medications": {},
    "monitoring": {
        "blood_pressure": {
            "enabled": False, "times": [],
            "reminder_text": "别忘了量血压", "alarm_refs": []
        },
        "blood_sugar": {
            "enabled": False, "times": [],
            "reminder_text": "别忘了量血糖", "alarm_refs": []
        }
    },
    "settings": {
        "patient_name": "爸爸",
        "timezone": "Asia/Shanghai",
        "broadcast_prefix": "该吃药啦",
        "device_name": ""
    }
}


def load():
    path = _data_file()
    if not os.path.exists(path):
        return json.loads(json.dumps(DEFAULT_DATA))
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    # 确保顶层 key 存在（兼容手动编辑或旧数据）
    for key in ('medications', 'monitoring', 'settings'):
        data.setdefault(key, json.loads(json.dumps(DEFAULT_DATA[key])))
    return data


def save(data):
    dir_ = _data_dir()
    os.makedirs(dir_, exist_ok=True)
    path = _data_file()
    fd, tmp = tempfile.mkstemp(dir=dir_, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _generate_id():
    return 'med_' + uuid.uuid4().hex[:12]


def add_medication(med):
    data = load()
    med_id = med.get('id') or _generate_id()
    now = datetime.now().astimezone().isoformat()
    entry = dict(med)
    entry['id'] = med_id
    entry.setdefault('alarm_refs', [])
    entry.setdefault('cron_refs', [])
    entry.setdefault('active', True)
    entry.setdefault('created_at', now)
    entry['updated_at'] = now
    data['medications'][med_id] = entry
    save(data)
    return med_id


def update_medication(med_id, updates):
    data = load()
    if med_id not in data['medications']:
        raise KeyError(f'Medication {med_id} not found')
    data['medications'][med_id].update(updates)
    data['medications'][med_id]['updated_at'] = datetime.now().astimezone().isoformat()
    save(data)


def deactivate_medication(med_id):
    data = load()
    if med_id not in data['medications']:
        raise KeyError(f'Medication {med_id} not found')
    med = data['medications'][med_id]
    result = {
        'old_alarm_refs': list(med.get('alarm_refs', [])),
        'old_cron_refs': list(med.get('cron_refs', []))
    }
    med['active'] = False
    med['alarm_refs'] = []
    med['cron_refs'] = []
    med['updated_at'] = datetime.now().astimezone().isoformat()
    save(data)
    return result


def list_active():
    data = load()
    return [m for m in data['medications'].values() if m.get('active', True)]


def list_all():
    data = load()
    return list(data['medications'].values())


def get_medication(med_id):
    data = load()
    return data['medications'].get(med_id)


def update_alarm_refs(med_id, refs):
    update_medication(med_id, {'alarm_refs': refs})


def update_cron_refs(med_id, refs):
    update_medication(med_id, {'cron_refs': refs})


def update_settings(updates):
    data = load()
    data['settings'].update(updates)
    save(data)


def update_monitoring(key, updates):
    data = load()
    if key not in data['monitoring']:
        data['monitoring'][key] = {
            'enabled': False, 'times': [], 'reminder_text': '', 'alarm_refs': []
        }
    data['monitoring'][key].update(updates)
    save(data)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='cmd')

    p_add = sub.add_parser('add')
    p_add.add_argument('--data', required=True)

    p_upd = sub.add_parser('update')
    p_upd.add_argument('--id', required=True)
    p_upd.add_argument('--data', required=True)

    p_deact = sub.add_parser('deactivate')
    p_deact.add_argument('--id', required=True)

    p_ualarm = sub.add_parser('update-alarm-refs')
    p_ualarm.add_argument('--id', required=True)
    p_ualarm.add_argument('--refs', required=True)

    p_ucron = sub.add_parser('update-cron-refs')
    p_ucron.add_argument('--id', required=True)
    p_ucron.add_argument('--refs', required=True)

    p_list = sub.add_parser('list')
    p_list.add_argument('--active', action='store_true')

    p_set = sub.add_parser('update-settings')
    p_set.add_argument('--data', required=True)

    p_mon = sub.add_parser('update-monitoring')
    p_mon.add_argument('--key', required=True)
    p_mon.add_argument('--data', required=True)

    args = parser.parse_args()

    if args.cmd == 'add':
        try:
            print(add_medication(json.loads(args.data)))
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'update':
        try:
            update_medication(args.id, json.loads(args.data))
            print('ok')
        except KeyError as e:
            print(f'error: medication not found: {e}', file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'deactivate':
        try:
            print(json.dumps(deactivate_medication(args.id), ensure_ascii=False))
        except KeyError as e:
            print(f'error: medication not found: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'update-alarm-refs':
        try:
            update_alarm_refs(args.id, json.loads(args.refs))
            print('ok')
        except KeyError as e:
            print(f'error: medication not found: {e}', file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'update-cron-refs':
        try:
            update_cron_refs(args.id, json.loads(args.refs))
            print('ok')
        except KeyError as e:
            print(f'error: medication not found: {e}', file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'list':
        meds = list_active() if args.active else list_all()
        print(json.dumps(meds, ensure_ascii=False, indent=2))
    elif args.cmd == 'update-settings':
        try:
            update_settings(json.loads(args.data))
            print('ok')
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    elif args.cmd == 'update-monitoring':
        try:
            update_monitoring(args.key, json.loads(args.data))
            print('ok')
        except json.JSONDecodeError as e:
            print(f'error: invalid JSON: {e}', file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
