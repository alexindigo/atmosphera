# QML probe ownership

Full-shell test probes use `qml_probe.inject_probe(source, payload)`. The helper
finds the unique object declaring `id: shellRoot`, wherever that session object
lives, and inserts the payload inside it. In an election-gated shell, the probe
shares the elected component's scope and lifetime instead of running in the
outer `ShellRoot` while the session is waiting.

The helper reuses `qml-identifiers.py`'s lexer for comments, strings, templates
and regular expressions. Missing/ambiguous IDs or unbalanced braces fail before
the caller writes a source copy. Non-session component observers specify their
own owner, for example `root_id="root"`. Imports and disposable-copy ownership
remain with the runner. Production QML has no test-only injection marker.

The recovery runner separately injects its queued-shell diagnostic in the
registration singleton. That owner exists before election, so the test can
still prove the queued session has not initialized and can close its own
contender. The real window and session observer remain election-gated.

Run the contract tests in the assigned Atmosphera VM, never on the host:

```sh
timeout 30 python3 -B Scripts/dev/qml-probe-selftest.py
```

Real panel, plugin and presentation runners retain their original consumer
assertions. `presentation-sequence-regression.py` also copies the helper and
lexer when running an older candidate tree, just as it copies the supervisor.
