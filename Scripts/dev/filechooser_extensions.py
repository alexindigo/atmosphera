"""Extension/name policy through the actual chooser controls."""


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    folder = runtime / "Extensions"
    folder.mkdir()
    protected = folder / "protected.png"
    protected.write_text("ORIGINAL extension bytes\n")
    filters = [["PNG", [[0, "*.png"]]], ["PDF", [[0, "*.pdf"]]], ["All files", [[0, "*"]]]]

    def save(name):
        open_request("save", "dev.filechooser.extensions", str(folder), current_name=name, filters=filters)

    save("plain")
    check("extensions-toggle-default-on", lambda s: s["autoExtension"] and s["preferredSuffix"] == "png")
    focus("Automatically add extension"); key(57)
    check("extensions-toggle-off", lambda s: not s["autoExtension"])
    focus("Save"); key(28); wait(lambda s: s["settled"])
    check("extensions-toggle-off-result", lambda s: s["replies"][0]["results"]["uris"] == [(folder / "plain").as_uri()])
    save("report.png")
    check("extensions-toggle-persisted", lambda s: not s["autoExtension"])
    focus("Automatically add extension"); key(57)
    focus("File type"); key(57); key(108); key(28)
    wait(lambda s: s["filter"] == "PDF" and s["saveName"] == "report.pdf")
    check("extensions-type-change-updates-field", lambda s: s["preferredSuffix"] == "pdf")
    command(["grim", evidence / "extension-type-change.png"])
    ipc("panelWidth", "1"); ipc("panelHeight", "1")
    wait(lambda s: abs(s["layoutGeometry"]["width"] - s["layoutGeometry"]["minimumWidth"]) < 1)
    check("extensions-minimum-footer-contained", lambda s: all(c["x"] >= -.5 and c["x"] + c["width"] <= s["layoutGeometry"]["width"] + .5
          for c in s["layoutGeometry"]["footer"]))
    command(["grim", evidence / "extension-minimum.png"])
    ipc("panelWidth", "1100"); ipc("panelHeight", "740")
    focus("Save"); key(28); wait(lambda s: s["settled"])
    check("extensions-displayed-final-target-returned", lambda s: s["replies"][0]["results"]["uris"] == [(folder / s["saveName"]).as_uri()])
    save("protected")
    key(28)
    wait(lambda s: s["replace"] == str(protected))
    check("extensions-final-name-confirmed", lambda s: s["saveName"] == "protected.png" and s["focusedControl"] == "Change name"
          and not s["replies"] and protected.read_text() == "ORIGINAL extension bytes\n")
    command(["grim", evidence / "extension-final-target-confirmation.png"])
    key(28); wait(lambda s: not s["replace"] and s["focus"] == "name")
    check("extensions-refusal-keeps-final-name", lambda s: s["nameSelection"] == [0, 9] and s["saveName"] == "protected.png")
    key(30, 29); command(["ydotool", "type", "README."])
    key(28); wait(lambda s: s["settled"])
    check("extensions-trailing-dot-suppresses", lambda s: s["saveName"] == "README"
          and s["replies"][0]["results"]["uris"] == [(folder / "README").as_uri()])
    ipc("open", "open")
    wait(lambda s: s["ready"] and s["focus"] == "listing")
