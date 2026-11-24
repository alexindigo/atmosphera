// All six actual child providers, same-source leases, held IO and last-owner retirement.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: root
  readonly property bool environmentPrecedence: Quickshell.env("PHA_PROVIDER_ENV_PRECEDENCE") === "1"
  FileView {
    id: input
    path: Quickshell.env("PHA_PROVIDER_CASE") + "/input.json"
    blockLoading: true
  }
  property var data
  property var main
  property var one
  property var two
  property var oldClaude
  property var oldOpenRouter
  property var oldZen
  property var oldCopilot
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  QtObject {
    id: first
    property bool alive: true
    property var settingsView: ({})
    function current() {
      return alive;
    }
  }
  QtObject {
    id: second
    property bool alive: true
    property var settingsView: ({})
    function current() {
      return alive;
    }
  }
  FileView {
    id: credentialsWriter
    path: root.data ? root.data.home + "/.claude/credentials-a.json" : ""
  }
  FileView {
    id: holdWriter
    path: root.data ? root.data.home + "/hold" : ""
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("MODEL_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function copy(value) {
    return JSON.parse(JSON.stringify(value));
  }
  function provider(client, id) {
    return client.providers.find(item => item.providerId === id);
  }
  function configure(context, mutate) {
    var options = copy(context.settingsView.providers);
    mutate(options);
    context.settingsView = {
      providers: options,
      barDisplayMode: "active",
      barCycleIntervalSec: 3.8,
      refreshIntervalSec: 300.8,
      barMetric: "prompts"
    };
  }
  function begin() {
    input.waitForJob();
    data = JSON.parse(input.text());
    first.settingsView = {
      providers: copy(data.options),
      refreshIntervalSec: 300
    };
    second.settingsView = {
      providers: copy(data.options),
      refreshIntervalSec: 300
    };
    var reordered = copy(second.settingsView.providers), claude = reordered.claude;
    reordered.claude = {
      credentialsPath: claude.credentialsPath,
      statsPath: claude.statsPath,
      enabled: claude.enabled
    };
    second.settingsView = {
      providers: reordered,
      refreshIntervalSec: 300
    };
    var component = Qt.createComponent("file://" + data.directory + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(root, {
                                    pluginApi: {
                                      settingsContext: first
                                    }
                                  });
    check(main, "actual Main constructs");
    one = main.settingsConsumerFor(first);
    two = main.settingsConsumerFor(second);
    phase = "providers";
  }
  function settled(client) {
    return client.providers.length === 6 && client.providers.every(item => item.ready) && provider(client, "claude").rateLimitPercent === 0.25 && provider(client, "codex").rateLimitPercent === 0.37 && provider(client, "gemini").todayTotalTokens === 19 && provider(client, "openrouter").todayPrompts === 3;
  }
  function drive() {
    if (phase === "providers" && Date.now() - since > 13000 && one.providers.length === 6 && one.providers.filter(p => p.providerId !== "codex").every(p => p.ready)) {
      var codex = provider(one, "codex");
      check(!(codex.ready && codex.rateLimitPercent === -1 && codex.todayTotalTokens === 0 && codex.sessionPathIndex === 0 && codex.sessionSearchInProgress), "Codex FileView fallback continuation did not deliver");
    }
    check(Date.now() - since < 14000, "finite provider deadline");
    if (phase === "providers" && settled(one) && settled(two)) {
      check(main._providerLeases.size === 6 && one.providers.every((item, index) => item === two.providers[index]), "equal sources share all six child observations");
      if (environmentPrecedence) {
        check(provider(one, "openrouter").apiKey === "controlled-env-router" && provider(one, "zen").apiKey === "controlled-env-zen" && provider(one, "zen").validatedApiKey === "controlled-env-zen", "actual provider environment precedence");
        configure(second, options => {
          options.openrouter.apiKey = "controlled-ignored";
          options.zen.apiKey = "controlled-ignored";
        });
        check(main._providerLeases.size === 6 && one.providers.every((item, index) => item === two.providers[index]), "masked configured credentials cannot duplicate an effective source lease");
        first.alive = false;
        second.alive = false;
        phase = "environment-retired";
        return;
      }
      check(provider(one, "claude").totalPrompts === 11 && provider(one, "claude").todayPrompts === 3, "Claude stats/history/credential probe reaches metrics");
      check(provider(one, "codex").todayPrompts === 2 && provider(one, "codex").todayTotalTokens === 10, "Codex latest-to-previous session fallback reaches rate/token metrics");
      check(provider(one, "copilot").rateLimitPercent === 0.4 && provider(one, "zen").validatedApiKey === "controlled-a", "Copilot token chain and Zen generation probe complete");
      oldClaude = provider(one, "claude");
      configure(second, options => options.claude.statsPath = data.home + "/.claude/stats-b.json");
      phase = "selected-local";
    } else if (phase === "selected-local" && provider(two, "claude").totalPrompts === 22) {
      check(oldClaude === provider(one, "claude") && oldClaude.totalPrompts === 11 && main._providerLeases.size === 7, "selected path lease cannot replace another source");
      check(two.barCycleIntervalSec === 3 && two.refreshIntervalSec === 300, "original int timer boundaries retained");
      credentialsWriter.setText(JSON.stringify({
                                                 claudeAiOauth: {
                                                   accessToken: "controlled-held",
                                                   expiresAt: Date.now() + 3600000
                                                 }
                                               }));
      phase = "credential-held";
    } else if (phase === "credential-held" && oldClaude.oauthAccessToken === "controlled-held" && oldClaude._requests.size > 0) {
      credentialsWriter.setText(JSON.stringify({
                                                 claudeAiOauth: {
                                                   accessToken: "controlled-fresh",
                                                   expiresAt: Date.now() + 3600000
                                                 }
                                               }));
      phase = "credential-fresh";
    } else if (phase === "credential-fresh" && oldClaude.oauthAccessToken === "controlled-fresh" && oldClaude.rateLimitPercent === 0.65) {
      configure(second, options => {
        options.openrouter.apiKey = "controlled-held";
        options.zen.apiKey = "controlled-held";
      });
      phase = "remote-held";
    } else if (phase === "remote-held" && provider(two, "openrouter")._requests.size >= 7 && provider(two, "zen")._requests.size >= 2) {
      oldOpenRouter = provider(two, "openrouter");
      oldZen = provider(two, "zen");
      configure(second, options => {
        options.openrouter.apiKey = "controlled-fresh";
        options.zen.apiKey = "controlled-fresh";
      });
      phase = "remote-fresh";
    } else if (phase === "remote-fresh" && provider(two, "openrouter").todayPrompts === 7 && provider(two, "zen").validatedApiKey === "controlled-fresh") {
      check(provider(one, "openrouter").todayPrompts === 3 && provider(one, "zen").validatedApiKey === "controlled-a", "OpenRouter fanout and Zen result stay source-local");
      phase = "late-remote";
    } else if (phase === "late-remote" && Date.now() - since > 1800) {
      check(oldClaude.rateLimitPercent === 0.65 && provider(two, "openrouter").todayPrompts === 7 && provider(two, "zen").validatedApiKey === "controlled-fresh", "held obsolete token/fanout/probe cannot publish after replacement");
      credentialsWriter.setText("{}");
      phase = "credential-invalid";
    } else if (phase === "credential-invalid" && oldClaude.oauthAccessToken === "" && oldClaude.rateLimitPercent === -1 && !oldClaude.hasAuthoritativeRateLimit) {
      holdWriter.setText("hold");
      phase = "hold-written";
    } else if (phase === "hold-written" && Date.now() - since > 180) {
      provider(one, "codex").scanSessions();
      provider(one, "gemini").scanSessions();
      provider(one, "copilot").refreshToken();
      oldCopilot = provider(one, "copilot");
      first.alive = false;
      phase = "first-retired";
    } else if (phase === "first-retired" && main._settingsConsumers.size === 1) {
      check(main._providerLeases.size === 6 && oldCopilot === provider(two, "copilot") && oldCopilot.enabled, "another context retains shared local workers");
      second.alive = false;
      phase = "last-retired";
    } else if ((phase === "last-retired" && Date.now() - since > 2300) || phase === "environment-retired") {
      check(main._settingsConsumers.size === 0 && main._providerLeases.size === 0, "last owner retires every provider watch/process/XHR lease");
      console.log("MODEL_LIFECYCLE: PASS");
      Qt.exit(0);
    }
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: {
    try {
      begin();
    } catch (error) {
      fail(error);
    }
  }
}
