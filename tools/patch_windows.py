# -*- coding: utf-8 -*-
"""CI: 'flutter create' sonrası Windows proje adlarını düzeltir."""
import pathlib
for name, pairs in {
    'windows/runner/main.cpp': [('L"quetzalov"', 'L"Quetzalov"')],
    'windows/runner/Runner.rc': [('"quetzalov"', '"Quetzalov"'), ('"quetzalov.exe"', '"Quetzalov.exe"')],
}.items():
    p = pathlib.Path(name)
    if p.exists():
        s = p.read_text(encoding='utf-8', errors='ignore')
        for a, b in pairs:
            s = s.replace(a, b)
        p.write_text(s, encoding='utf-8')
        print('düzeltildi:', name)
