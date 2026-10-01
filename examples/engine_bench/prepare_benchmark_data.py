#!/usr/bin/env python3
"""Materialize private benchmark inputs for a local EngineBench build."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--asr-manifest', type=Path, required=True)
p.add_argument('--scion-directory', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parent
asr = json.loads(a.asr_manifest.read_text())
languages = {
    'English', 'Chinese', 'French', 'German', 'Italian',
    'Hindi', 'Portuguese', 'Spanish', 'Japanese', 'Korean',
}
asr = [row for row in asr if row['language'] in languages]
assert len(asr) == 50 and {row['language'] for row in asr} == languages
assert all(sum(row['language'] == language for row in asr) == 5
           for language in languages)
fixtures = root / 'BenchmarkData/asr_fixtures'
fixtures.mkdir(parents=True, exist_ok=True)
for row in asr:
    source = Path(row.pop('path'))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == row['sha256']
    row['file'] = source.name
    shutil.copy2(source, fixtures / source.name)
selected_files = {row['file'] for row in asr}
for stale in fixtures.glob('*.wav'):
    if stale.name not in selected_files and stale.name != 'bench_asr.wav':
        stale.unlink()
asr.sort(key=lambda x: (x['language'], x['file']))
data = root / 'BenchmarkData'
(data / 'asr_multilingual70.json').unlink(missing_ok=True)
(data / 'asr_multilingual50.json').write_text(json.dumps(asr, ensure_ascii=False, indent=2))
(data / 'scion').mkdir(exist_ok=True)
for name, expected in [('prompt_tokens_k1256', 100), ('prompt_tokens_ext_20260901', 320), ('prompt_tokens_agentic_20260901', 96)]:
    source = a.scion_directory / (name + '.json')
    rows = json.loads(source.read_text())['rows']
    assert len(rows) == expected and len({x['id'] for x in rows}) == expected
    assert all(x['prompt_tokens'] == len(x['input_ids']) > 0 for x in rows)
    shutil.copy2(source, data / 'scion' / source.name)
print('Prepared ASR50 (10 languages) and Scion100/320/96; private token sets and WAVs remain ignored.')
