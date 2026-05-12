import os
import sys
import json
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

BASE_MED = {
    'name': '降压药', 'dose': '半片', 'broadcast_note': '饭后服用',
    'warnings': '', 'notes': '',
    'schedule': {
        'type': 'daily', 'times': ['07:30'],
        'interval_days': None, 'course_days': None,
        'start_date': '2026-04-28', 'end_date': None
    }
}


@pytest.fixture(autouse=True)
def isolate(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    import med_store
    import importlib
    importlib.reload(med_store)


def get_store():
    import med_store
    import importlib
    importlib.reload(med_store)
    return med_store


def test_add_returns_id(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    med_id = store.add_medication(dict(BASE_MED))
    assert med_id.startswith('med_')


def test_add_persists_fields(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    med_id = store.add_medication(dict(BASE_MED))
    data = store.load()
    entry = data['medications'][med_id]
    assert entry['name'] == '降压药'
    assert entry['active'] is True
    assert entry['alarm_refs'] == []
    assert entry['cron_refs'] == []


def test_list_active_excludes_inactive(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    id1 = store.add_medication({**BASE_MED, 'name': '药A'})
    id2 = store.add_medication({**BASE_MED, 'name': '药B'})
    store.deactivate_medication(id2)
    names = [m['name'] for m in store.list_active()]
    assert '药A' in names
    assert '药B' not in names


def test_deactivate_clears_refs_and_returns_old(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    med_id = store.add_medication(dict(BASE_MED))
    store.update_alarm_refs(med_id, ['alarm_123'])
    store.update_cron_refs(med_id, ['cron_456'])
    result = store.deactivate_medication(med_id)
    assert result['old_alarm_refs'] == ['alarm_123']
    assert result['old_cron_refs'] == ['cron_456']
    data = store.load()
    entry = data['medications'][med_id]
    assert entry['active'] is False
    assert entry['alarm_refs'] == []
    assert entry['cron_refs'] == []


def test_update_medication(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    med_id = store.add_medication(dict(BASE_MED))
    store.update_medication(med_id, {'dose': '一片'})
    assert store.load()['medications'][med_id]['dose'] == '一片'


def test_update_alarm_refs(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    med_id = store.add_medication(dict(BASE_MED))
    store.update_alarm_refs(med_id, ['a1', 'a2'])
    assert store.load()['medications'][med_id]['alarm_refs'] == ['a1', 'a2']


def test_update_settings(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    store.update_settings({'patient_name': '妈妈'})
    assert store.load()['settings']['patient_name'] == '妈妈'


def test_update_monitoring(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    store = get_store()
    store.update_monitoring('blood_pressure', {'enabled': True, 'times': ['07:30']})
    mon = store.load()['monitoring']['blood_pressure']
    assert mon['enabled'] is True
    assert mon['times'] == ['07:30']
