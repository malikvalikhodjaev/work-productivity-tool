"""Read a frozen Focus To-Do Chromium IndexedDB snapshot into local JSONL files.

This reads only the copied LevelDB directory passed on the command line. The
source application and its database are not modified.
"""

from __future__ import annotations

import collections
import datetime as dt
import json
import pathlib
import sys

from ccl_chromium_reader import ccl_chromium_indexeddb


def json_value(value):
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    if isinstance(value, bytes):
        return {"_bytes_hex": value.hex()}
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)


def main():
    snapshot = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    wrapper = ccl_chromium_indexeddb.WrappedIndexDB(snapshot)
    summary = {}
    for database_id in wrapper.database_ids:
        db = wrapper[database_id.dbid_no]
        db_summary = {}
        for store in db:
            if store.name is None:
                continue
            fields = collections.Counter()
            errors = [0]
            newest = {}

            def on_error(_key, _raw):
                errors[0] += 1

            path = output / f"db{db.db_number}_{store.name}.jsonl"
            for record in store.iterate_records(bad_deserializer_data_handler=on_error):
                old = newest.get(record.key.raw_key)
                if old is None or record.ldb_seq_no > old.ldb_seq_no:
                    newest[record.key.raw_key] = record
            current = [
                record
                for record in newest.values()
                if record.is_live and record.value is not None
            ]
            current.sort(key=lambda item: str(item.key.value))
            with path.open("w", encoding="utf-8") as handle:
                for record in current:
                    val = json_value(record.value)
                    if isinstance(val, dict):
                        fields.update(val.keys())
                    line = {
                        "_key": json_value(record.key.value),
                        "_sequence": record.ldb_seq_no,
                        "_value": val,
                    }
                    handle.write(json.dumps(line, ensure_ascii=False) + "\n")
            db_summary[store.name] = {
                "count": len(current),
                "errors": errors[0],
                "history_versions": len(newest),
                "fields": fields.most_common(60),
                "bytes": path.stat().st_size,
            }
        summary[str(db.db_number)] = db_summary
    (output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
