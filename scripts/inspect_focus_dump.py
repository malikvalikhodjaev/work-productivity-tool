import collections
import json
import os
from pathlib import Path

source = Path(os.environ['TEMP']) / 'rhythm-focus-todo-parsed.jsonl'
counts = collections.Counter()
stores = collections.Counter()
shapes = {}
invalid = 0
key_types = collections.Counter()
object_ids = collections.Counter()
value_types = collections.Counter()
non_null_examples = {}

with source.open(encoding='utf-8') as stream:
    for line in stream:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            invalid += 1
            continue
        record_type = record.get('__type__', type(record).__name__)
        counts[record_type] += 1
        key = record.get('key')
        key_types[key.get('__type__') if isinstance(key, dict) else type(key).__name__] += 1
        object_ids[str(record.get('object_store_id'))] += 1
        value_types[type(record.get('value')).__name__] += 1
        store = record.get('object_store_name') or '?'
        stores[str(store)] += 1
        if str(store) not in shapes:
            value = record.get('value')
            shapes[str(store)] = {
                'record_keys': list(record),
                'key_keys': list(key) if isinstance(key, dict) else type(key).__name__,
                'value_type': type(value).__name__,
                'value_keys': list(value) if isinstance(value, dict) else None,
            }
        if record.get('object_store_id') is not None and str(record.get('object_store_id')) not in non_null_examples:
            value = record.get('value')
            non_null_examples[str(record.get('object_store_id'))] = {
                'key_type': key.get('__type__') if isinstance(key, dict) else None,
                'value_type': type(value).__name__,
                'value_keys': list(value) if isinstance(value, dict) else None,
                'key_keys': list(key) if isinstance(key, dict) else None,
            }

print('records', sum(counts.values()), 'invalid', invalid)
print('types', counts.most_common(12))
print('stores', stores.most_common(25))
print('key_types', key_types.most_common(15))
print('object_ids', object_ids.most_common(15))
print('value_types', value_types.most_common(15))
print('object_samples', json.dumps(non_null_examples, ensure_ascii=False, indent=2)[:5000])
print('shapes', json.dumps(shapes, ensure_ascii=False, indent=2)[:5000])
