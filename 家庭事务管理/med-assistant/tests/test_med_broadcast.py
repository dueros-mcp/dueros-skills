import os
import sys
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

BASE_MED = {
    'dose': '一片', 'broadcast_note': '', 'warnings': '', 'notes': '',
    'schedule': {
        'type': 'daily', 'times': ['07:30'],
        'interval_days': None, 'course_days': None,
        'start_date': '2026-04-28', 'end_date': None
    }
}


def reload_all(tmp_path, monkeypatch):
    monkeypatch.setenv('MED_DATA_DIR', str(tmp_path))
    import med_store
    import med_broadcast
    import importlib
    importlib.reload(med_store)
    importlib.reload(med_broadcast)
    return med_store, med_broadcast


def test_single_no_note(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.update_settings({'patient_name': '爸爸', 'broadcast_prefix': '该吃药啦'})
    store.add_medication({**BASE_MED, 'name': '阿司匹林'})
    assert bc.generate_tts('07:30') == '爸爸，该吃药啦。阿司匹林一片。'


def test_single_with_note(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.update_settings({'patient_name': '爸爸', 'broadcast_prefix': '该吃药啦'})
    store.add_medication({**BASE_MED, 'name': '降压药', 'dose': '半片', 'broadcast_note': '饭后服用'})
    assert bc.generate_tts('07:30') == '爸爸，该吃药啦。降压药半片，饭后服用。'


def test_multiple_same_time(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.update_settings({'patient_name': '爸爸', 'broadcast_prefix': '该吃药啦'})
    store.add_medication({**BASE_MED, 'name': '降压药', 'dose': '半片', 'broadcast_note': '饭后服用'})
    store.add_medication({**BASE_MED, 'name': '阿司匹林'})
    result = bc.generate_tts('07:30')
    assert result.startswith('爸爸，该吃药啦。')
    assert '降压药半片，饭后服用' in result
    assert '阿司匹林一片' in result
    assert result.endswith('。')


def test_with_monitoring(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.update_settings({'patient_name': '爸爸', 'broadcast_prefix': '该吃药啦'})
    store.add_medication({**BASE_MED, 'name': '降压药', 'dose': '半片'})
    store.update_monitoring('blood_pressure', {
        'enabled': True, 'times': ['07:30'], 'reminder_text': '别忘了量血压'
    })
    result = bc.generate_tts('07:30')
    assert '降压药半片' in result
    assert '别忘了量血压' in result


def test_no_meds_at_time(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.add_medication({**BASE_MED, 'name': '降压药', 'dose': '半片'})
    assert bc.generate_tts('12:00') == ''


def test_by_explicit_ids(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    store.update_settings({'patient_name': '爸爸', 'broadcast_prefix': '该吃药啦'})
    med_id = store.add_medication({
        **BASE_MED, 'name': '二甲双胍', 'dose': '两片',
        'broadcast_note': '饭后服用',
        'schedule': {**BASE_MED['schedule'], 'type': 'every_n_days',
                     'times': ['20:00'], 'interval_days': 2}
    })
    result = bc.generate_tts('20:00', med_ids=[med_id])
    assert result == '爸爸，该吃药啦。二甲双胍两片，饭后服用。'


def test_inactive_excluded(tmp_path, monkeypatch):
    store, bc = reload_all(tmp_path, monkeypatch)
    med_id = store.add_medication({**BASE_MED, 'name': '药X'})
    store.deactivate_medication(med_id)
    assert '药X' not in bc.generate_tts('07:30')
