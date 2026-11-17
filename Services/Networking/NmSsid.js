.pragma library
.import DBus 1.0 as DBusQML

// dbusqml delivers ay (including values inside a{sv}) as an ArrayBuffer.
// An empty native QByteArray can have a null backing store: Qt rejects making
// the Uint8Array view used by textFromBytes. Handle emptiness before decoding,
// without converting arbitrary SSID bytes to a string or treating them as UTF-16.
function decode(bytes) {
  if (bytes === undefined || bytes === null || bytes.byteLength === 0 || bytes.length === 0)
    return "";
  return DBusQML.DBusUtils.textFromBytes(bytes);
}
