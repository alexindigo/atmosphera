"""The outer fixture invocation owns publication of its verdict receipts.

Fixtures stage verdict data in memory. Logs, native disk witnesses and progress
are not final receipts; they can still be collected during a run. An in-process
child can hand its staged data to its caller without publishing to disk.
"""
from contextvars import ContextVar
from copy import deepcopy
from functools import wraps
import json
from pathlib import Path
from tempfile import NamedTemporaryFile


_receipts = ContextVar('fixture_receipts', default=None)
_nonpassing = frozenset({'FAIL', 'BLOCKED', 'SKIP', 'SKIPPED'})


def stage_receipt(path, value):
    pending = _receipts.get()
    if pending is None:
        raise RuntimeError('fixture verdict requires a receipt_run scope')
    pending[Path(path).absolute()] = deepcopy(value)


def staged_receipt(path):
    """Read an in-process child's data, not a prematurely published verdict."""
    pending = _receipts.get()
    if pending is None:
        raise RuntimeError('reading a staged verdict requires a receipt_run scope')
    return deepcopy(pending[Path(path).absolute()])


def _publish(path, value):
    text = json.dumps(value, indent=2) + '\n'
    with NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as output:
        scratch = Path(output.name)
        try:
            output.write(text)
            output.close()
            scratch.replace(path)
        finally:
            scratch.unlink(missing_ok=True)


def receipt_run(body):
    """Publish after the body returns or unwinds, including its finalizers."""
    @wraps(body)
    def run(*args, **kwargs):
        parent = _receipts.get()
        pending = {}
        token = _receipts.set(pending)

        def finish(failure=None):
            if failure is not None:
                for path, value in pending.items():
                    if value.get('status') not in _nonpassing:
                        pending[path] = dict(value, status='FAIL', receiptFailure=failure)
            if parent is not None:
                parent.update(pending)
            else:
                for path, value in pending.items():
                    _publish(path, value)

        try:
            try:
                result = body(*args, **kwargs)
            except BaseException as error:
                failure = None if isinstance(error, SystemExit) and error.code in (None, 0) else repr(error)
                try:
                    finish(failure)
                except Exception as publish_error:
                    error.add_note(f'could not publish fixture verdict: {publish_error!r}')
                raise
            failure = f'exit status {result}' if type(result) is int and result != 0 else None
            finish(failure)
            return result
        finally:
            _receipts.reset(token)

    return run
