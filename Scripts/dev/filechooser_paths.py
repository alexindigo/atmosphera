"""Real typed paths, local completion and breadcrumb intents."""
from pathlib import Path
from urllib.parse import unquote, urlsplit


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    base = runtime / "Path entry"
    (base / "One/Child").mkdir(parents=True)
    (base / "Other").mkdir()
    (base / "Picture.txt").write_text("typed consumer bytes\n")
    (base / "Second.txt").write_text("second consumer bytes\n")

    def edit(label, text):
        focus(label); key(30, 29); command(["ydotool", "type", text])

    def click(control):
        g = state()["layoutGeometry"]
        x = (1280 - g["width"]) / 2 + control["x"] + control["width"] / 2
        y = (800 - g["height"]) / 2 + control["y"] + control["height"] / 2
        command(["ydotool", "click", int(x), int(y), 272, 0])
        command(["ydotool", "move", 5, 5])

    open_request("open", "dev.filechooser.paths", str(base))
    edit("File name", "Pic")
    wait(lambda s: s.get("pathEntry", {}).get("name", {}).get("completionOpen", False))
    check("open-name-prefix-completion", lambda s: [e["name"] for e in s["pathEntry"]["name"]["suggestions"]] == ["Picture.txt"])
    key(108); key(28)
    check("completion-Enter-selects-without-accepting", lambda s: s["pathEntry"]["name"]["text"] == "Picture.txt" and not s["settled"])
    key(28); wait(lambda s: s["settled"])
    check("typed-open-consumer-bytes", lambda s: s["replies"][0]["results"]["uris"] == [(base / "Picture.txt").as_uri()]
          and Path(unquote(urlsplit(s["replies"][0]["results"]["uris"][0]).path)).read_text() == "typed consumer bytes\n")

    open_request("open", "dev.filechooser.paths", str(base))
    edit("File name", "Pic")
    wait(lambda s: s["pathEntry"]["name"]["completionOpen"])
    key(108); key(28)
    ipc("focusListing"); key(107)
    check("completion-keeps-owner-binding", lambda s: s["selected"] == [str(base / "Second.txt")]
          and s["pathEntry"]["name"]["text"] == "Second.txt")
    focus("Open"); key(28); wait(lambda s: s["settled"])
    check("completion-followed-by-selection-consumer", lambda s: s["replies"][0]["results"]["uris"] == [(base / "Second.txt").as_uri()]
          and Path(unquote(urlsplit(s["replies"][0]["results"]["uris"][0]).path)).read_text() == "second consumer bytes\n")

    open_request("open", "dev.filechooser.paths", str(base))
    edit("File name", "Sec")
    wait(lambda s: s["pathEntry"]["name"]["completionOpen"] and s["pathEntry"]["name"]["completionRows"])
    row = state()["pathEntry"]["name"]["completionRows"][0]
    command(["ydotool", "click", int(row["x"] + row["width"] / 2), int(row["y"] + row["height"] / 2), 272, 0])
    check("completion-mouse-selects-without-accepting", lambda s: s["pathEntry"]["name"]["text"] == "Second.txt" and not s["settled"] and s["focusedControl"] == "File name")
    key(28); wait(lambda s: s["settled"])
    check("completed-mouse-name-returned", lambda s: s["replies"][0]["results"]["uris"] == [(base / "Second.txt").as_uri()])

    escaped = base / "URI names"
    escaped.mkdir()
    for name in ("report%20draft.txt", "report draft.txt", "report#draft.txt", "report?draft.txt", "report-résumé.txt"):
        (escaped / name).write_text("literal " + name + "\n")
    for stem, name in (("report%", "report%20draft.txt"), ("report#", "report#draft.txt"),
                       ("report?", "report?draft.txt"), ("report ", "report draft.txt"),
                       ("report-ré", "report-résumé.txt")):
        open_request("open", "dev.filechooser.paths", str(base))
        edit("File name", (escaped / stem).as_uri())
        wait(lambda s: s["pathEntry"]["name"]["completionOpen"])
        key(15)
        check("uri-completion-displays-" + name, lambda s: s["pathEntry"]["name"]["text"] == (escaped / name).as_uri())
        key(28); wait(lambda s: s["settled"])
        check("uri-completion-consumer-" + name, lambda s: s["replies"][0]["results"]["uris"] == [(escaped / name).as_uri()]
              and Path(unquote(urlsplit(s["replies"][0]["results"]["uris"][0]).path)).read_text() == "literal " + name + "\n")

    links = base / "Links"
    (links / "target/sub").mkdir(parents=True)
    (links / "link").symlink_to(links / "target/sub", target_is_directory=True)
    (links / "Report.txt").write_text("wrong lexical file\n")
    (links / "target/Report.txt").write_text("physical parent file\n")
    open_request("open", "dev.filechooser.paths", str(base))
    edit("File name", str(links / "link") + "/../Report.txt"); key(28)
    wait(lambda s: s["settled"])
    check("symlink-parent-consumer-bytes", lambda s: s["replies"][0]["results"]["uris"] == [(links / "target/Report.txt").as_uri()]
          and Path(unquote(urlsplit(s["replies"][0]["results"]["uris"][0]).path)).read_text() == "physical parent file\n")
    open_request("open", "dev.filechooser.paths", str(base))
    invalid = str(links / "target/Report.txt") + "/."
    edit("File name", invalid); key(28)
    wait(lambda s: bool(s["error"]))
    check("file-dot-refused-with-input-kept", lambda s: not s["settled"] and s["pathEntry"]["name"]["text"] == invalid)

    open_request("save", "dev.filechooser.paths", str(base), current_name="draft.txt")
    edit("File name", "report.txt")
    key(38, 29); command(["ydotool", "type", str(base / "Other")]); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "Other"))
    check("location-preserves-edited-save-name", lambda s: s["saveName"] == "report.txt")

    open_request("open", "dev.filechooser.paths", str(base))
    click(next(c for c in state()["layoutGeometry"]["header"] if c.get("name") == "Edit location"))
    check("empty-location-bar-click-enters-editing", lambda s: s["pathEditing"] and s["focusedControl"] == "Location")
    key(1)
    key(38, 29); command(["ydotool", "type", str(base) + "/On"])
    wait(lambda s: s["pathEntry"]["location"]["completionOpen"])
    check("location-local-directory-completion", lambda s: [e["text"] for e in s["pathEntry"]["location"]["suggestions"]] == [str(base / "One") + "/"])
    command(["grim", evidence / "path-completion.png"])
    key(15); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "One") and not s["pathEditing"])
    check("location-Tab-completes-and-Enter-navigates", lambda s: s["names"] == ["Child"] and not s["settled"])
    segment = next(c for c in state()["layoutGeometry"]["header"] if c.get("kind") == "segment" and c.get("path") == str(base / "One"))
    click(segment)
    check("breadcrumb-click-targets-real-folder", lambda s: s["path"] == str(base / "One") and not s["pathEditing"])
    children = next(c for c in state()["layoutGeometry"]["header"] if c.get("kind") == "children" and c.get("path") == str(base / "One"))
    click(children)
    wait(lambda s: s["pathEntry"]["location"]["menuOpen"] and len(s["pathEntry"]["location"]["menuEntries"]) == 1)
    check("breadcrumb-menu-current-row-contained", lambda s: s["pathEntry"]["location"]["menuGeometry"]["rowHeight"] > 0
          and s["pathEntry"]["location"]["menuGeometry"]["top"] >= -.5
          and s["pathEntry"]["location"]["menuGeometry"]["bottom"] <= s["pathEntry"]["location"]["menuGeometry"]["contentHeight"] + .5)
    command(["grim", evidence / "breadcrumb-subfolders.png"])
    key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "One/Child"))
    check("breadcrumb-keyboard-child-menu-navigates", lambda s: not s["settled"])
    # The overflow exposes every ancestor even when only the leaf fits.
    ancestor = next(c for c in state()["layoutGeometry"]["header"] if c.get("name") == "Ancestor folders")
    click(ancestor); wait(lambda s: s["pathEntry"]["location"]["menuOpen"])
    key(1)
    check("breadcrumb-menu-Escape-does-not-cancel", lambda s: not s["settled"] and not s["pathEntry"]["location"]["menuOpen"])
    click(ancestor); wait(lambda s: s["pathEntry"]["location"]["menuOpen"])
    key(107); key(103); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "One"))
    check("ancestor-menu-selects-exact-ancestor", lambda s: s["names"] == ["Child"] and not s["pathEditing"])

    open_request("open", "dev.filechooser.paths", str(base), multiple=True)
    edit("File name", '"Picture.txt" "Second.txt"'); key(28)
    wait(lambda s: s["settled"])
    check("open-quoted-multiple-names", lambda s: s["replies"][0]["results"]["uris"] == [(base / n).as_uri() for n in ("Picture.txt", "Second.txt")])

    open_request("save", "dev.filechooser.paths", str(base), current_name="keep.txt", filters=[["Text", [[0, "*.txt"]]]])
    key(38, 29); command(["ydotool", "type", str(base / "Other")]); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "Other"))
    check("location-keeps-save-name", lambda s: s["saveName"] == "keep.txt")
    edit("File name", "../One/"); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base / "One"))
    check("typed-save-directory-keeps-prior-leaf", lambda s: s["saveName"] == "keep.txt" and not s["settled"])
    edit("File name", "./New file"); key(28)
    wait(lambda s: s["settled"])
    check("save-relative-path-derived-final-target", lambda s: s["saveName"] == "New file.txt"
          and s["replies"][0]["results"]["uris"] == [(base / "One/New file.txt").as_uri()]
          and not (base / "One/New file.txt").exists())

    open_request("open", "dev.filechooser.paths", str(base))
    key(38, 29); command(["ydotool", "type", "missing/folder"]); key(28)
    wait(lambda s: bool(s["error"]))
    check("invalid-location-keeps-editor-and-listing", lambda s: s["pathEditing"] and s["path"] == str(base) and "Picture.txt" in s["names"] and not s["settled"])
    key(30, 29); command(["ydotool", "type", str(base) + "/On"])
    wait(lambda s: s["pathEntry"]["location"]["completionOpen"])
    key(1)
    check("Escape-dismisses-completion-first", lambda s: s["pathEditing"] and not s["pathEntry"]["location"]["completionOpen"] and not s["settled"])
    key(1)
    check("Escape-leaves-path-editing-second", lambda s: not s["pathEditing"] and not s["settled"])
    ipc("open", "open"); wait(lambda s: s["ready"] and s["focus"] == "listing")
    ipc("panelWidth", "0")
    wait(lambda s: s["layoutGeometry"]["width"] == s["layoutGeometry"]["minimumWidth"])
    check("minimum-path-leaf-legible", lambda s: s["breadcrumbText"][-1] == "Fieldwork" and len(s["breadcrumbGaps"]) > 0
          and all(not gap["clipped"] for gap in s["breadcrumbGaps"]))
    command(["grim", evidence / "path-minimum.png"])
    ipc("panelWidth", "1100")
