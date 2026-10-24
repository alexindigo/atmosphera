import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Modules/Panels/Launcher/Helpers/ApplicationRanking.js" as Ranking
import "../../../Modules/Panels/Launcher/Helpers/LauncherResults.js" as Results
import "../../../Modules/Panels/Launcher/Providers"
import qs.Commons

ShellRoot {
  id: root
  property int failed: 0
  property int stage: 0
  property int ticks: 0
  property int refreshBefore: 0

  QtObject {
    id: consumer
    property bool isOpen: false
    property string query: ""
    property var results: []
    property int refreshes: 0
    function updateResults() {
      results = apps.getResults(query);
      refreshes++;
    }
  }
  ApplicationsProvider {
    id: apps
    launcher: consumer
  }
  Process {
    id: mutate
    command: ["python3", Quickshell.env("LAUNCHER_UNIT_MUTATOR")]
    onExited: (code, status) => {
      root.same("source.mutation", [code, status], [0, 0]);
      root.stage = 2;
    }
  }

  function same(name, actual, expected) {
    const passed = JSON.stringify(actual) === JSON.stringify(expected);
    if (!passed)
      failed++;
    Logger.i("LauncherRankingUnits", "LAUNCHER_RANKING|" + JSON.stringify({
                                                                            test: name,
                                                                            pass: passed,
                                                                            actual: actual,
                                                                            expected: expected
                                                                          }));
  }
  function entry(id, name, pinned, usage) {
    return {
      id: id,
      name: name || "",
      pinned: !!pinned,
      usage: usage || 0
    };
  }
  function rank(entries, query) {
    return Ranking.rank(entries, query, {
                          pinned: app => app.pinned,
                          usage: app => app.usage,
                          id: app => app.id
                        });
  }
  function ids(rows) {
    return rows.map(row => row.app.id);
  }
  function appIds(rows) {
    return rows.map(row => row.appId);
  }
  function units() {
    const fields = ["name", "executableName", "keywords", "comment", "genericName"];
    const values = ["cat", "catalog", "a catapult", "bobcat", "cobalt"];
    for (let field = 0; field < fields.length; field++) {
      const candidates = [];
      for (let quality = 0; quality < values.length; quality++) {
        const app = entry("f" + field + "q" + quality);
        app[fields[field]] = field === 2 ? ["irrelevant", values[quality]] : values[quality];
        const found = Ranking.match("cat", app);
        same("matrix." + field + "." + quality, found, {
               field: field,
               quality: quality
             });
        candidates.unshift(app);
      }
      same("quality-order." + field, ids(rank(candidates, "cat")), [0, 1, 2, 3, 4].map(q => "f" + field + "q" + q));
    }
    const priority = fields.map((field, i) => {
      const app = entry("field" + i, "", i > 0, i * 100000);
      app[field] = i === 2 ? ["cat"] : (i === 0 ? "cobalt" : "cat");
      return app;
    });
    same("field-before-quality-pin-usage", ids(rank(priority.reverse(), "cat")), ["field0", "field1", "field2", "field3", "field4"]);
    const ties = [entry("z", "Cat Z", false, 9999), entry("b", "Cat B", true, 1), entry("a", "Cat A", true, 1), entry("used", "Cat Used", true, 2)];
    same("query-ties", ids(rank(ties, "cat")), ["used", "a", "b", "z"]);
    same("empty-ties", ids(rank(ties, "")), ["used", "a", "b", "z"]);
    same("blank-ties", ids(rank(ties, "  \t ")), ["used", "a", "b", "z"]);
    same("identity-final-tie", ids(rank([entry("b", "Cat"), entry("a", "Cat")], "cat")), ["a", "b"]);
    same("pins-not-membership", ids(rank([entry("pin", "Unrelated", true, 999999), entry("match", "Cat")], "cat")), ["match"]);
    const many = [];
    for (let i = 0; i < 30; i++)
      many.push(entry("old" + i, "Cat"));
    many.push(entry("winner", "Cat", true, 999999));
    const ranked = rank(many, "cat");
    same("beyond-twenty", [ranked.length, ranked[0].app.id], [31, "winner"]);
    same("case-accents", Ranking.match("CAFE", {
                                         name: "Café"
                                       }), {
           field: 0,
           quality: 0
         });
    same("unicode-word-boundary", Ranking.match("cat", {
                                                  name: "écat"
                                                }), {
           field: 0,
           quality: 3
         });
    same("punctuation-word-boundary", Ranking.match("cat", {
                                                      name: "my-cat"
                                                    }), {
           field: 0,
           quality: 2
         });
    same("keyword-only", ids(rank([
                                    {
                                      id: "web",
                                      name: "Vela",
                                      keywords: ["browser", "www"]
                                    }
                                  ], "browser")), ["web"]);
    same("keyword-string", Ranking.match("browser", {
                                           keywords: "www;Browser;web"
                                         }), {
           field: 2,
           quality: 0
         });
    same("no-match", Ranking.match("missing", {
                                     name: "Cat"
                                   }), null);
    same("multi-phrase", Ranking.match("red fox", {
                                         name: "Red Fox"
                                       }), {
           field: 0,
           quality: 0
         });
    same("multi-reordered", Ranking.match("fox red", {
                                            name: "Red Fox"
                                          }), {
           field: 0,
           quality: 2
         });
    same("multi-fields", Ranking.match("red browser", {
                                         name: "Red",
                                         keywords: ["browser"]
                                       }), {
           field: 2,
           quality: 2
         });
    same("multi-all-required", Ranking.match("red missing", {
                                               name: "Red",
                                               keywords: ["browser"]
                                             }), null);
    same("multi-weakest-quality", Ranking.match("red cat", {
                                                  name: "Red",
                                                  keywords: ["cobalt"]
                                                }), {
           field: 2,
           quality: 4
         });
    same("multi-weakest-field", ids(rank([
                                           {
                                             id: "description",
                                             name: "Red",
                                             comment: "fox"
                                           },
                                           {
                                             id: "keyword",
                                             name: "Red",
                                             keywords: ["fox"]
                                           }
                                         ], "red fox")), ["keyword", "description"]);
    const qualityBeatsPin = [entry("pinned", "Catalog", true, 999999), entry("exact", "Cat")];
    same("quality-before-pin-usage", ids(rank(qualityBeatsPin, "cat")), ["exact", "pinned"]);

    const stream = [
            {
              name: "pin",
              _score: 1,
              usageKey: "pin",
              provider: {
                trackUsage: true
              }
            },
            {
              name: "used",
              _score: 1,
              usageKey: "used",
              provider: {
                trackUsage: true
              }
            },
            {
              name: "loose",
              _score: 0.1
            }
          ];
    const others = [
            {
              name: "settings",
              _score: -1.2
            },
            {
              name: "session",
              _score: -0.2
            },
            {
              name: "calculator"
            },
            {
              name: "window",
              _score: 0.8
            }
          ];
    same("merge-providers", Results.merge(stream, others, () => 999999).map(r => r.name), ["pin", "used", "window", "loose", "calculator", "session", "settings"]);
    same("merge-usage-nonapp", Results.merge([], [
                                               {
                                                 name: "tracked",
                                                 _score: 0,
                                                 usageKey: "t",
                                                 provider: {
                                                   trackUsage: true
                                                 }
                                               },
                                               {
                                                 name: "plain",
                                                 _score: 0.1
                                               }
                                             ], () => 3).map(r => r.name), ["tracked", "plain"]);
    same("merge-stable-ties", Results.merge([], [
                                              {
                                                name: "first"
                                              },
                                              {
                                                name: "second"
                                              }
                                            ], null).map(r => r.name), ["first", "second"]);
  }

  Component.onCompleted: {
    units();
    Settings.data.appLauncher.pinnedApps = ["launcher-unit-alpha"];
    apps.init();
    apps.onOpened();
    consumer.isOpen = true;
    consumer.updateResults();
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      root.ticks++;
      if (root.ticks > 160) {
        root.same("source.timeout", root.stage, "complete");
        Qt.exit(2);
      }
      if (root.stage === 0 && consumer.results.length === 3) {
        root.same("source.opens-all", [apps.selectedCategory, consumer.results.length], ["all", 3]);
        root.same("source.empty-order", appIds(consumer.results), ["launcher-unit-alpha", "launcher-unit-beta", "launcher-unit-other"]);
        consumer.query = "browser";
        consumer.updateResults();
        root.same("source.keyword-only", appIds(consumer.results), ["launcher-unit-beta"]);
        apps.selectCategory("Pinned");
        root.same("source.category-with-query", appIds(consumer.results), []);
        apps.onOpened();
        consumer.query = "";
        consumer.updateResults();
        root.refreshBefore = consumer.refreshes;
        root.stage = 1;
        mutate.running = true;
      } else if (root.stage === 2 && consumer.refreshes > root.refreshBefore && consumer.results.some(r => r.name === "Source Zeta")) {
        root.same("source.disk-visible-name", consumer.results.map(r => r.name), ["Source Zeta", "Source Beta", "Source Other"]);
        consumer.query = "browser";
        consumer.updateResults();
        root.same("source.disk-keywords", appIds(consumer.results), ["launcher-unit-alpha"]);
        consumer.query = "newexec";
        consumer.updateResults();
        root.same("source.disk-executable", appIds(consumer.results), ["launcher-unit-alpha"]);
        consumer.query = "newdescription";
        consumer.updateResults();
        root.same("source.disk-comment", appIds(consumer.results), ["launcher-unit-alpha"]);
        consumer.query = "newgeneric";
        consumer.updateResults();
        root.same("source.disk-generic", appIds(consumer.results), ["launcher-unit-alpha"]);
        apps.selectCategory("Graphics");
        root.same("source.disk-category", appIds(consumer.results), ["launcher-unit-alpha"]);
        apps.onOpened();
        consumer.query = "";
        consumer.updateResults();
        Settings.data.appLauncher.pinnedApps = ["launcher-unit-beta"];
        root.same("source.pin-refresh-all", appIds(consumer.results), ["launcher-unit-beta", "launcher-unit-other", "launcher-unit-alpha"]);
        Logger.i("LauncherRankingUnits", "LAUNCHER_RANKING_DONE");
        Qt.exit(root.failed ? 1 : 0);
      }
    }
  }
}
