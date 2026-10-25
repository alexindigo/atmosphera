"""Install the shared test-only fresh-file oracle in a disposable shell copy."""
from pathlib import Path


def install_file_oracle(source: Path, shell: Path) -> None:
    """Copy the fixture component, adapting only its source-relative import.

    Production and archived source are read-only. Copied root-level probes use
    the same component/OwnedProcess owner as the original fixture directory.
    """
    text = (source / 'Scripts/dev/fixtures/ThemingFileOracle.qml').read_text()
    old = '"../../../Helpers/OwnedProcess.js"'
    assert text.count(old) == 1
    (shell / 'ThemingFileOracle.qml').write_text(text.replace(old, '"Helpers/OwnedProcess.js"'))
