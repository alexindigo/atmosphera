# Plugin settings editors

## One selected native owner

The generic `settings` page is an editor, not a live runtime plugin. Settings ->
Plugins selects plugin scope. Global/monitor Bar, Control Center, Desktop
Widgets list gear and runtime desktop generic Settings select their captured
placement. Explicit plugin-level IPC/BarService entry points remain plugin-level.
Core and `desktopWidgetSettings` pages keep their separate live-field contract.

`PluginSettingsSession` owns the existing ConfigQml draft/overlay, field capture,
page capability, Apply/Reset, receipts and release. `NPluginSettingsPopup` renders
that session and supplies input commit/capture/acknowledgment callbacks. There
is no second settings engine or page snapshot writer. `PluginLoader` requires
the editor role before constructing a generic page through either creation path.

The runtime desktop fallback captures the placement before asynchronous loading
and opens the same session as the list gear. Generic Close never invokes the
removed live-dialog Save-on-Close path. The field-only API supersedes the earlier
P001 safety unit's mutable namespace and reviewed session Reset dispatch.

## Page intent

See [field capabilities](plugin-settings-field-capabilities.md) for the complete
page surface. `pluginSettings`/`initialSettings` are isolated read projections;
only `field(key).set(value)` and `field(key).reset()` submit configuration intent.
The control's user event or committed input owns that call, not initialization,
translation, range projection or an effective-value comparison. Atomic lists,
records and maps remain one declared preference leaf.

`NPluginSettingsField` takes the injected handle and presents inherited/stored
override state, pending intent and Reset. Undisplayed configuration overrides
appear in the host summary without their values. Native equal-to-base omission
removes an explicitly edited equal override. Untouched known/opaque overrides
are retained. Plugin-level changes propagate only through inherited fields.

Pages may keep local input buffers. Their synchronous `saveSettings()` commits
only those buffered field intents. `settingsDirty` is a read-only local-input
predicate, never a Save. `pluginApi.saveSettings(callback)` only registers a
completion observer; it neither ingests a snapshot nor publishes. The session
calls one native Apply with the selected editor's own `values` identity.

Legacy shared content remains in place. `contentField(key)` exists only in
plugin scope for explicit content commands. Instance configuration cannot obtain
it; operational leaves have no generic Settings setter. Todo instance pages
explain why shared page/task management is unavailable. Configuration Apply and
Reset never collect tasks/pages/current-page/counters or opaque content.

## Reset, results and lifetime

Field Reset is staged: native `unset([key])` for an instance, native
`stageReset([[key]], callback)` for a plugin draft. A finite multi-field control
uses `resetFields(keys)`. Native lower-level presentation replaces the removed
choice; a manifest-default assignment is not Reset. Discard does not publish it.
Whole instance Reset removes declared configuration overrides only, followed by
one Apply. It never calls the native all-data `resetOverrides` on mixed content.

Only `saved` or `nothing_to_save` with `refreshState: current` acknowledge work.
Accepted-current field recapture precedes observers. `settingsCompleted` precedes
callbacks. Failed/stale results retain input/preview for Retry or confirmed
discard; busy excludes competing input/actions. A second Open refuses replacement.
Ordinary Close uses dirty confirmation. Genuine presentation loss uses native
deferred `release()` and fences late callbacks, not a forced busy discard.

Both presentation settlement and actual session destruction use the same
selection-resource release. The session closes its provided-editor preview
before disappearing, and the native editor still retires only after becoming
idle. Otherwise the runtime owner could retain a dead preview admission and
refuse the next editor even after native persistence had settled.

Settings hosts inject `registerPresentation` into the generic popup. From native
editor selection through release, its host registers only a request-Close
callback with SettingsPanelService. Tab/sidebar/search/subtab, native window
Close, service Close and panel replacement consult that admission before hiding
or replacing content. A refusal keeps the same page/input and confirmation;
neither a retained editor alone nor a post-destruction discard is sufficient.
After explicit Apply or Discard, retry the requested navigation. No old request
automatically navigates a later session. Ordinary panels without an injected
Close admission retain their existing behavior.

An unexpected native hide or direct `Popup.close()` also cannot unload a dirty
or busy selected page. The popup asks the same session, keeps that exact loaded
page on refusal and restores its presentation. PanelService propagates the
runtime popup host's Close refusal before claiming a replacement panel, rather
than covering a retained dialog with another keyboard owner.

Discard of unapplied input is nonpublishing. It does not undo an already
requested Apply: ConfigQml retains admitted requested persistence through
detach, including a failed publication. The main Settings owner's autosave may
later publish that admitted placement intent; the manual plugin owner does not
autosave it. Failed receipts still cannot acknowledge input or a refresh.
`plugin-settings-navigation-regression.py` separates those two cases and records
independent final files, instead of promising rollback of requested native work.

The native editor captures base and owning-leaf generations. A changed capture,
same-ID replacement, reorder, base change or owner loss cannot retarget it to a
new placement. A closed/conflicted editor cannot recapture an index to recover.

ConfigQml >=0.5.2 is required for untouched-overlay preservation and native
staged draft Reset as well as selected publication. Package, Nix and devcontainer
pins select the signed release; stock 0.5.1 lacks those first two contracts.

## Selected runtime consumers

Runtime APIs retain their live preference contract, distinct from page APIs.
Each API owns a stable read-only `settingsContext`. Configuration-dependent
Main-owned clients use that captured context, not the shared Main configuration
for every instance. One API shared across views keeps one client. Retired query
generations cannot publish into replacement accounts, repositories or locations.

`plugin-settings-git-matrix-regression.py` adds seven real Git Settings/Main/Panel
scenarios: IO failure with same-editor Retry, changed shared base, external source
replacement, inherited propagation with staged field Reset, held old response,
GitLab group/platform/interval selection and empty GitLab scope. Each scenario
compares complete native documents independently and starts a separate cold
Panel consumer without changing configuration hashes. These controls invoke the
page's own committed-input/selection signals; the original selected-Git witness
separately drives genuine keyboard input and Discard. Inert gh/glab endpoints
record literal query argv, not external account or physical-device behavior.
The same seven scenarios also instantiate the real Bar and Desktop pieces for
shared, selected, overridden sibling and inherited APIs. Distinct inert result
counts reach the desktop's actual Text and the Bar pill's tooltip/icon, both
warm and cold. Every piece must use the exact Main-owned selected client, not
merely display an equal count. Separate Bar/Desktop shared-client mutations fail
at that identity assertion. The fixture injects the actual English dictionary.
An independent rendered-text mutation also must fail: the Desktop root's data
property alone is not a rendered Text consumer.

With `--baseline-plugins` pointing to the pinned original catalog, a separate
nonediting engine characterizes inherited widget diagnostics before each case.
Only exact diagnostics from those original Bar/desktop-context sources may
remain; a new page/Main/session error still fails. Results retain both original
and candidate diagnostics and explicitly mark the runtime unclean. Git's existing
undeclared Bar orientation binding and the desktop base's late-context null
reads are not fixed or certified by this scoped-data proof. Initial color-owner
file creation is recorded separately; every seeded configuration file remains
unchanged during characterization. The separate `selectedRepo` heading alias
P066, physical tooltip interaction, full visual presentation, full catalog and
final whole-plan acceptance remain outside this focused proof.

Music Search's folder and limit buttons remain explicit Main/helper actions,
outside the preference draft. Its Main-owned result records pending, saved,
failed or rejected admission and the actual applied value. Settings renders
that result without treating a newer local buffer as applied. Helper errors or
mismatched result values cannot acknowledge success, including the helper's
old-output/zero-exit failure case. Busy/failure keeps local input for Retry;
preference Discard does not roll back an already completed helper action.
`plugin-settings-music-action-regression.py` uses both scopes, the actual helper,
a real flock barrier, permission refusal, independent intermediate files and
separate cold Main/Settings readers. It does not restore deletion or redesign
the separate provider/sort queue.

Battery Threshold keeps one Main-owned configuration client per captured runtime
context and one observation/write owner per physical battery. Settings, Panel
and Bar use the selected client; Main/IPC remain explicitly plugin-level. Each
client restores its saved policy once on activation or accepted Settings Apply,
not on each rendering or physical observation. Two configurations selecting the
same battery observe one physical value and can change it in activation/action
order. The instance UI identifies this shared hardware effect. Only a successful
explicit physical action may save through its captured runtime API; a retired
context cannot publish a delayed result. Pages never receive that writer.

`plugin-settings-battery-regression.py` uses the real Main, service, Settings,
Panel and Bar in both scopes with disk-backed synthetic batteries. Actual chooser
intent and native Apply, shared IPC, slider actions, permission refusal/Retry,
staged Reset and held-write retirement have independent complete native-document
and device-byte checks. Separate cold engines activate differing saved policies
in sequence, observing each restore and the shared rendered threshold without
changing configuration files. Exact shared-client and shared-writer mutations
must reject. These are controlled hardware endpoints, not physical sysfs proof
or final catalog/UI acceptance.

`plugin-settings-hello-regression.py` checks the simple direct-consumer case:
Hello World's Main keeps its explicitly shared IPC, while actual Panel Text and
Bar foreground consume their injected runtime API. Both generic page scopes
exercise both declared fields, Discard, native Apply, staged Reset and later
shared propagation with an overridden sibling. Independent complete documents
and separate edited/Reset/following cold engines distinguish saved configuration
from rendered results. Shared-reader, shared-Bar and child-Text mutations must
fail at those actual consumers. No desktop-specific live-field contract is
changed. The Panel preserves an explicit
empty message instead of substituting its manifest reference value.

Currency Exchange keeps one Main-owned rates/cache/process/timer client per
captured runtime context. Panel, Bar and LauncherProvider bind that same client;
existing Main properties, methods and IPC remain explicitly plugin-level. A
selected interval updates its actual Timer without forcing a refresh or changing
the existing five-minute cache and failed-attempt retry policy. Retired contexts
stop their process and timer and cannot publish a late response.

`plugin-settings-currency-regression.py` drives all four actual Settings combos
in both scopes, with Discard, native permission failure/same-editor Retry, staged
Reset and later inheritance. It observes actual conversion Text, Bar Text/display
mode, Launcher results, client identities and Timer intervals against literal-argv
curl substitutes, complete independent native documents and separate nonpublishing
edited/Reset/following cold engines. Real failed/forced/expired-cache requests and
a held-process retirement are separate checks. Its original-code red saves a
30-minute instance interval while the actual old shared Timer remains 15 minutes;
four disposable consumer mutations must also reject. This is controlled endpoint
proof, not external network, clipboard, physical input or final catalog/UI proof.

World Clock is another direct reader: Main has no configuration worker, while
each Bar consumes its injected runtime API. The source-qualified
`plugin-settings-world-clock-regression.py` exercises its existing seconds
SpinBox and format combo in both scopes, Discard/Apply/staged Reset/inheritance,
actual rotation Timer and city/time Text, independent documents and three cold
boundaries per scope. Finite date substitutes record the actual timezone/format
argv; both selected and overridden sibling clocks must really rotate. Timezone
lists, hidden `showDate` and opaque data remain unchanged. Shared-reader and
child-time mutations must fail. Known P023/P088/P107/P128 findings remain recorded
separately: this witness does not claim an unused feature, list-shrink repair,
shell-execution repair or unknown-timezone UI repair.

Not Just Text uses the same Main-owned context identity for its file/fortune
clients. Actual Bar views of one context share one client; a changed source
replaces its captured worker generation. Main's existing methods/properties stay
explicitly plugin-level. Wallpaper changes retain their 300 ms per-context
debounce, and fortune retains its initial request plus ten retries.

`plugin-settings-not-just-text-regression.py` drives all nine real Settings
controls in both scopes and observes actual child Bar Text from one-line disk
files and finite literal-argv fortune endpoints. Complete native documents,
Discard, permission failure/same-editor Retry, staged Reset/inheritance and
separate nonpublishing cold readers are checked independently. Held endpoint
PIDs/start identities must disappear on source replacement and retirement;
observing a signal handler alone is not process quiescence. Shared-client and
rendered-child mutations must reject. This is controlled source/consumer proof,
not physical input, broad visual review or full catalog acceptance.

Coin Flip has no Main worker. `plugin-settings-coin-regression.py` checks its
actual delay slider and native owner in both scopes, with an untouched hidden
icon-color field, Discard/Apply/staged Reset/inheritance, actual animation Timer
and Bar foreground, complete documents and separate nonpublishing cold readers.
It also lets four actual Panels complete their animations sequentially, observing
the child result Text/Image and each native runtime result write. The existing
operational `lastResult` stays outside configuration intents; an equal-to-base
runtime result follows native override omission. Independent documents protect
the other contexts even when their random results coincide. Wrong Panel/Bar
readers, a shared result writer and a wrong rendered child must all reject.
This is direct-consumer/operational-owner proof, not physical input or broad
visual/whole-catalog acceptance.

## Shared observations with selected polling

Cloudflare WARP, Monique, IP Monitor and wireless batteries keep one existing
physical/network observation owner each. Main caches one `PluginSettingsPoller`
per captured runtime context; every Bar/Panel of that API activates the same
client. The selected interval drives that client's actual Timer. Main's existing
background schedule remains plugin-level. No extra physical owner, preference
store or action writer is created. Client retirement stops its schedule without
stopping another client's schedule or the common observation process.

The domain factories preserve milliseconds for WARP/Monique, seconds for IP and
wireless batteries, existing fallback/disable policies, installed and busy guards,
and startup/manual refresh. Interval changes do not add an immediate refresh.
The poller first admits the domain's source interval through the same QML `int`
property as the old Main, then scales seconds to milliseconds. Only IP requires
a positive interval to run; imposing that policy on the other domains would
change admitted zero/subsecond values. `plugin-settings-polling-domain-regression.py`
checks ten actual Main/Timer cases, including fractional inputs and each zero
policy, against explicit test contexts. It is typed-domain proof, separate from
the native instance/control proof.
Observations remain common: one instance's scheduled refresh can update all
views; physical connection/profile actions affect the whole system. Instance
Settings explicitly says so while retaining independent polling/display choices.

`plugin-settings-polling-check.py` parses the finite reviewed factory, timer,
field and manifest-entry mappings for all four members and rejects shared-reader,
missing-view, interval-unit and retirement controls. It is not a general JS proof.
`plugin-settings-polling-regression.py` runs the WARP and wireless representatives
in both scopes with actual pages, native files, real timers, common Main processes
and final rendered results from inert endpoints. Separate cold readers observe
edited, Reset and inherited boundaries without publishing. This is controlled
observation proof, not physical device/VPN actions or broad visual acceptance.

## Selected query and action inputs

Latency Monitor, Ramadan Iftar, HASS, Syncthing Status and Kubectl Context use
Main-owned context-keyed query clients. Host/process/socket generations capture
typed source inputs. Replacement fences the old generation before constructing
the settled replacement. Latency keeps the existing seconds-to-milliseconds int
boundary; HASS keeps its 300 ms debounce. HASS Browser owns a request identity
for its local cache and pending state, invalidates both at source/owner loss,
and fetches again only after the selected source authenticates. A previous request
cannot repopulate a replacement browser.

MPRIS Lyric selects an actual shared MPRIS player per context; its lyric cache,
timer and playback targets follow that selection. SSH Sessions selects polling,
host filtering and terminal arguments over one SSH config/session observer.
Lyrics Fetch selects paused/empty projection over one player/lyric observer.
Keep Awake keeps one inhibitor/status/action owner while selecting menu and
display policy. Update Count keeps one updater-detection/system-action owner,
with selected count queries and captured update/terminal arguments. Shared
effects are explicit in the relevant instance Settings descriptions and their
existing dictionaries. None of these changes moves content or operational data.

`plugin-settings-query-group-check.py` parses the finite reviewed field/factory/
entry/lifetime mappings for all ten members and rejects 36 source controls.
`plugin-settings-query-regression.py` joins real generic controls, native complete
documents and actual Bar/Panel children for Latency, Ramadan and SSH in both
scopes. Independent edited/Reset/following cold engines do not publish. Original
shared-Main reds and selected-client/child-Text/retirement mutations must reject.
SSH terminal collaborators are inert; no SSH connection is made.

`plugin-settings-query-lifecycle-regression.py` additionally tests held ping
retirement, a loopback HASS WebSocket, Browser rows/cache/loading, URL/token
replacement and captured service targets, plus actual MPRIS peers on a private
disk-backed guest bus. Old-player metadata, replacement/missing players, lyric
Text and real Bar action dispatch have recorded endpoints. These explicit-context
cases are source/lifetime proof, not additional native placement acceptance.
`plugin-settings-query-actions-regression.py` uses native runtime APIs to test
Syncthing folder publication and foreign-writer refusal, and inert Kubernetes
captured kubeconfig/context/namespace/terminal targets with a held retired action.
Complete documents and process identities are checked independently; shared-writer
and retirement controls must reject. No device, inhibitor, cluster or package
mutation is used as a witness. Broad visual review and whole-catalog acceptance
remain separate gates.

## Selected observation and action policy

Port Monitor publishes one unfiltered host observation; Main-owned clients select
polling and port filtering for each captured runtime context. Mullvad clients
select polling, display, favorites, expiry and action policy over one daemon and
account owner. All views of one API share its client. Retired clients stop their
schedule and cannot dispatch new actions. Main/IPC remain explicitly plugin-level.
Instance Settings explains that observations and physical process/VPN effects
are shared; it does not promise independent system connections or processes.

`plugin-settings-observation-group-check.py` parses the finite two-member field,
entry, factory, lifetime, schedule and action mappings, including Mullvad's
independent account timer. `plugin-settings-observation-native-regression.py`
joins real pages/native files to Bar/Panel child Text in both scopes, with
Discard, Apply, staged Reset, later inheritance and separate nonpublishing cold
readers. Actual Panel row/confirmation and VPN controls reach inert executable
endpoints with independently checked literal targets. No kill, terminal shell,
VPN or remote action is executed. Wrong selected readers, rendered children and
relay action policy must reject. This is not broad visual or final acceptance,
nor repair of Mullvad's unrelated unused-option/confirmation findings.

## Runtime placement save and retirement Retry

DS4 Colors and NVibrant keep one Main-owned physical action boundary, not one
hardware owner per placement. DS4 captures RGB and controller paths for its
serial direct/elevation operation; mutable display state cannot retarget a later
controller or fallback. Explicit runtime actions retain their originating native
writer and retirement fences late publication. Settings completion supplies its
acknowledged color field with the read-only context, without resaving the page
through Main. Automatic reconnect restoration remains plugin-level. NVibrant's
Bar passes its runtime API to Main; the selected port/intensity use the original
QML int admission and enabled writes go to that API. Both instance pages explain
that physical changes are visible to every instance using the same device.

The G2 action regression adds both-scope actual controls/native documents and
separate nonpublishing cold readers for these members. Its individual controlled
hardware cases hold direct writes, mutate later state, traverse two controllers
and inert elevation, and independently check LED bytes and native writer scope.
Held retirement and fractional NVibrant values have rejecting controls. These
are inert endpoints, not physical controller/display proof or broad UI acceptance.

Placement `saveSettings` requests selected publication of its owning atomic key,
not a whole-store save. Failed receipts retain unconfirmed coverage. Explicit
Retry publishes the current values of those same keys through native
`saveSelected`; later success on covered keys supersedes earlier failures.
Unrequested keys and shared plugin settings are not included. This is current-
intent Retry, not an exact original-value capture or per-row transaction.
Retirement retains the ready native owner until requested work settles, then
waits for placement API destruction before releasing that owner.

## Originating capture policy

Screen Recorder, ScreenShot/Record and Screen Toolkit retain one existing
physical capture owner. A placed action supplies its captured runtime context;
Main/IPC defaults remain explicitly plugin-level. Admission owns a read-only
effective-value projection before portal checks, Panel destruction, selector
creation or launch timers. Recording and replay retain separate policies and
completed paths, including delayed Toast callbacks. Toolkit's retained overlays
own their policies independently; a Measure screenshot also owns its timer's
policy even when another Measure view opens. Existing results, history and
capability writers keep their shared operational owner, not the selected API.
Instance Settings explains these shared effects.

`plugin-settings-capture-group-check.py` checks the finite declared-field,
entry/caller, child-injection, delayed-stage and physical-owner mappings for all
three members. Its controls are source contracts, not a general JS effect proof.
The capture-native driver joins actual folder controls, complete native documents
and originating Bar/Panel actions in both scopes. Separate cold engines observe
the edited, Reset and inherited boundaries without publication. The focused
runtime driver covers Recorder replay/completion/Toast lifetimes, supported
Shot/Record selectors and retirement, and Toolkit annotation/share/save, Mirror,
Measure and recording/conversion/save boundaries. All physical capture, portal,
compositor, upload, recorder-signal and clipboard endpoints are inert; no physical
or broad visual/translation acceptance follows from these tests.

## Selected wallpaper policy and staged tools

LWE, MPVpaper and Video Wallpaper retain one physical playback owner per
existing output domain. Accepted Settings completion selects a read-only runtime
context; runtime Bar/Panel actions supply their own existing API. Main/IPC stays
explicitly plugin-level. No runtime writer or immediate owner dispatcher enters
the Settings page. Registration of a runtime view does not itself select policy.

Settings Random/Clear are scoped field edits: MPV's `currentWallpaper` or Video's
atomic `monitors`. They update the draft preview, publish on Apply and revert on
confirmed Discard/Close. Their shared ToolRow takes injected actions; the runtime
consumer injects immediate Main actions instead. Random owns a fresh folder model
per request, pairs it by QObject identity, and rejects replaced source results.
Runtime browse retains its admitted writer, folder and output targets too.

LWE keeps source-dependent catalogs per captured context and one engine with its
admitted options/layout/property inputs. Stability/recovery and screenshot/property
content stay at their original shared owner; retired policies cannot publish.
Its startup switch remains explicitly plugin-level and disabled in instance
Settings. MPV cache/baseline writers stay shared; backend construction no longer
authors `isPlaying`. Video's delayed baseline commands retain their originating
runtime writer and screen across later selection changes. A read-only page
completion never manufactures that writer.

The `plugin-settings-wallpaper-*` drivers separate finite mappings, actual scoped
pages/native documents/cold engines, staged tools, runtime browse and individual
engine/source/color/backend/automation/delayed-writer lifetimes. Inert endpoints
prove selected command inputs and native publication, not physical playback,
general MPV option correctness or broad visual/translation acceptance.

## Selected output parsing and layout actions

Display Settings keeps one Main-owned config query client per captured context.
Its selected path owns a fresh existing KDL parser. Source replacement or context
retirement cancels both read/glob processes and queued stages before destroying
that generation. Panels render that client's actual parsed cards; the live niri/
wlr providers, modifications and udev monitor remain single physical owners.

Monitor Layout keeps its common live/draft/selection model. Each originating
fetch, grid edit, apply and config-script request captures its runtime context
and effective policy. A fetch parses using its admitted backend, not a later
mutable choice; apply's completion refresh retains its original command/backend.
Retired requests cannot publish a layout or start follow-up work. Main/IPC stays
plugin-level. Instance Settings explicitly identifies shared output/layout effects.

The output group checker covers every declared field, caller and physical owner.
Its native driver joins real page control intent, complete independent documents,
Discard/Apply/staged Reset/inheritance and separate nonpublishing cold readers to
actual Panel cards and grid coordinates. Original runtime and omitted-origin
native controls must reject at those consumers. Held parser, backend and apply
cases independently check old-process quiescence and retirement. All compositor
modification endpoints are inert. These are not physical output/broad visual
proofs, nor a repair of Monitor Layout's unrelated scale-status `t` reference.

## Selected presentation and shared content/helper effects

Clipper keeps its clipboard, pin, note and Todo content owners. Placed views
read their selected presentation. Main captures originating paste delay and Todo
enable policy before selection IO, selector display or delayed paste. A later
view, setting change or retired context cannot retarget a pending action.
Content commands remain immediate shared actions, not preference drafts.

Music Search's Panel, Launcher and preview read their injected effective
presentation. Main captures the originating auto-download choice and scalar
track for playback; queue, saved-autoplay and batch continuations retain that
policy. Retired contexts cannot start a download or another playback stage.
The helper still owns shared playback, queue, library, provider, folder, limit
and YouTube-client settings. Its legacy native `ytPlayerClient` preference is
preserved but is not helper authority. Runtime preview-width publication keeps
its originating API. No content is migrated and deletion is not restored.

The content group checker maps every declared field, caller, effect owner and
retained stage. Native representatives exercise actual pages, complete documents
and separate nonpublishing cold readers. Individual held selection, selector,
paste, playback, queue and batch cases use inert endpoints; actual helper
folder/limit acknowledgment is checked separately. These are not physical
clipboard/media, broad visual/translation or whole-catalog acceptance.

## Admitted automatic-session policy

2-in-1-tools retains one tablet/sensor/output owner. Applied Settings completion
and originating Bar/CC actions select a read-only effective context. Pending
queries, apply/touch continuations and session exit restore retain their admitted
policy. Automatic startup stays plugin-level until an origin is admitted. Bar/dock
restore state is operational and remains with its existing shared native writer,
not a selected page or placement writer. State-file replacement retires the old
watcher/read generation. Retired contexts cannot start follow-up effects.

OSK retains exactly one physical backend Loader. Main-owned context clients probe
availability and project the active backend's live state; they never construct a
keyboard. Applied backend/binary changes wait for retiring processes to quiesce.
Backends receive injected policy/binary rather than Main's shared API. Delayed
show and monitor restart handlers respect retirement. Settings Recheck uses only
the applied runtime context. Both instance pages explain the common physical effect.

The automatic group checker maps every configuration/protected field, caller,
retained stage and physical owner. Native representatives join actual page intent
to complete independent documents, Discard/Apply/staged Reset/inheritance and
separate nonpublishing cold readers. Individual lifetime and writer drivers cover
sensor/apply/touch, bar/dock restore/native publication, state-file handoff,
keyboard binary/delayed-show and real private-bus monitor retirement. Compositor,
keyboard, preemption, gsettings and dconf endpoints are inert. These are not
physical, broad visual/translation or whole-catalog proofs.

## Selected device request and completion policy

USB Drive Manager keeps one udev/lsblk/df observation and mount/unmount/eject
owner. Panel/card, Bar and Control Center actions carry their originating browser,
terminal and notification policy. Completion and debounce retain that admission,
not a later caller's preferences. Accepted Settings completion selects automatic
policy; merely constructing a view does not. Automatic startup stays plugin-level.
Retiring automatic policy fences mounts without stopping pure device observation.
The existing pre-enumeration auto-mount timing is unchanged.

Supergfxctl keeps one CLI/state/mode owner and one NotificationServer. Context-keyed
clients select polling through the original QML bool/int boundary. Queries and
mode commands capture patch/debug policy for parsing, completion and follow-up;
retired contexts cannot publish responses or start later requests. An ephemeral
manual-request record is distinct from daemon-reported pending state. The disabled
rogcc notification preference remains stored and disabled, not implemented here.
Both instance pages explain that physical effects and observations are shared.

The device drivers separate finite every-field/caller/owner mappings, actual
Settings/native documents and nonpublishing cold readers, omitted-origin controls,
held action/parser/mode stages, typed schedules and real private-bus notifications.
udev, devices, mounts, terminals, browsers and GPU CLI endpoints are inert. These
are selected consumer/lifetime proofs, not physical, broad visual/translation or
whole-catalog acceptance.

## Admitted Steam overlay geometry

Steam Overlay's two Bar actions supply their captured runtime context. Main owns
one physical overlay and one admitted operation's typed geometry, output size and
classic/Lua dispatch syntax. Actual query completion, movement, show/focus and
continuing new-window stages retain that policy. Later configuration cannot
retarget a running operation; retirement stops its processes and queued stages.
Requests admitted before startup probes settle retain their configuration while
waiting. Shared dimensions and syntax settle once before the first query/effect;
retirement during that wait cannot dispatch a continuation.
Main/IPC remains explicitly plugin-level. The optional Panel guide already reads
its injected pixel-width preferences separately from the percentage geometry.
Instance Settings explains the shared effect. Stored auto-launch and chat-
notification fields retain their independent feature gaps; deprecated compositor
support is not restored by this settings correction.

The Steam drivers join actual gap-control intent, complete independent native
documents, Discard/Apply/staged Reset/inheritance and separate nonpublishing cold
engines to originating Bar compositor argv. Individual held-stage cases verify
classic/Lua/custom geometry, continuing-window policy and retirement. All Steam,
pidof and hyprctl endpoints are inert. Finite parsed field/caller/owner controls
supplement, not replace, those consumer observations. No physical, broad visual/
translation or whole-catalog acceptance follows.

## Verification boundaries

The P001 safety regression command now runs field-only real desktop routes,
keyboard input, permission failure/Retry, protected configuration Reset,
independent files, explicit shared content commands and separate cold consumers.
The session suite separately covers held/current/no-op/stale receipts, busy and
dirty-close behavior. Four-family native fields and shared-field gates cover
sparse metadata and staged Reset. Catalog page tests cover both scopes and
their loaded children, but do not construct every Main or claim unrelated
runtime defects fixed. Focused selected-client and P169 three-input tests carry
their own consumer claims. The final integration matrices remain separate gates.

The named-guest `plugin-settings-lifetime-regression.py` adds selected-session
base-change/equal/ABA, source-content/inode replacement, actual plugin unload,
held receipt, busy/delayed destruction and released-selection callback cases.
It observes bound runtime text, readable retained fields, independent files and
a separate cold engine. The preview-chain case observes shared preview below
stored overrides below the selected preview across all four placement families.
Closing either preview reveals current underlying values, never an opening
snapshot. A replacement preview must acquire the released owner's admission.
These synthetic session-contract cases do not certify catalog Main/actions.

An equal-byte new-inode shared source is intentionally distinct from a frozen
overlay source: native drafts fence selected path content and intent; overlays
also retain source provenance. The suite checks the shared admitted-current
outcome and the overlay refusal separately, plus changed-content replacement
refusal for both. No shell inode fence changes the native contract.

Historical old-owner preparations and mutable page examples remain in Git
history; they are not current extension instructions.

`plugin-settings-entry-routes-regression.py` constructs actual BarTab,
MonitorWidgetsConfig and ControlCenterTab owners and invokes their section
editor's public gear handler. Five cases cover global, monitor-specific and
monitor-inherited Bar lists plus both shortcut sections. Production signals
must capture the expected instance before page creation. Discard, Apply,
field/whole configuration Reset, real IO failure/Retry and same-ID replacement
have exact independent owning-file checks. Separate cold readers observe the
edited, whole-Reset, retried and final replacement boundaries without publishing.
Disposable wrong-list/section controls must fail at the selected-context assertion.
This is entry-route proof with a reviewed synthetic field page, not additional
catalog Main/action or physical input coverage. The seed explicitly stores the
existing Bar margin values, so it does not certify unrelated appearance controls
as nonpublishing when their choices are absent.

`plugin-settings-shared-routes-regression.py` separately activates the actual
InstalledSubTab Settings gear, the public BarService operation with the real
PopupMenuWindow, and an external `qs ipc` call to `plugin.openSettings` through
the real IPCService/CurrentScreenDetector. Same-ID placements must not change
these explicitly plugin-level routes into instance editors. The actual selected
page/session exercises Discard, Apply, staged native field Reset, real IO refusal
and same-editor Retry. Complete seeded documents are independently checked at
seven boundaries per route; a separate cold engine observes shared/inherited
Text consumers and unchanged overridden content without publishing. A disposable
implicit-placement mutation must fail at the exact shared-context assertion.

Failed native publication does not roll back the shared owner's requested
desired values. The witness records that unconfirmed value separately from the
unchanged files and inherited placement, and requires a failed/not-refreshed
receipt with retained input/editor before Retry. No result claims rollback or
success from that desired value. These are actual route/native-owner witnesses
using the reviewed synthetic field page, not catalog Main/action or physical
input coverage.
