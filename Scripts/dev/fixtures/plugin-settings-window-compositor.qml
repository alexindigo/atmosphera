pragma Singleton
import QtQml

QtObject {
  property var calls: []
  function record(action) {
    calls = calls.concat([action]);
    console.log("WINDOW_ACTION " + action);
  }
  function lock() {
    record("lock");
  }
  function logout() {
    record("logout");
  }
  function suspend() {
    record("suspend");
  }
  function lockAndSuspend() {
    record("lockAndSuspend");
  }
  function hibernate() {
    record("hibernate");
  }
  function reboot() {
    record("reboot");
  }
  function shutdown() {
    record("shutdown");
  }
}
