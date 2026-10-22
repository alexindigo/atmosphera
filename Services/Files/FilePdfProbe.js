.pragma library

// Share compilation, not a document or a picker owner. Keeping the optional
// import in its own file also lets FilePreview load without QtPdf installed.
var component = null;

function create(parent) {
    if (component === null)
        component = Qt.createComponent(Qt.resolvedUrl("OptionalPdfProbe.qml"));
    var error = component.errorString();
    if (error)
        throw new Error(error);
    var document = component.createObject(parent);
    if (!document)
        throw new Error("Could not create optional PDF probe");
    return document;
}
