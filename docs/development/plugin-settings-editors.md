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
callbacks. Failed/stale writes retain input/preview for another Apply or confirmed
discard; busy excludes competing input/actions. A second Open refuses replacement.
After a failed runtime observation, Apply still commits controls and stages the
current page input. **Check again**, in the failure message, only retries the
retained write's observation. It issues no save, refuses a changed native draft,
and does not reload the page or clear its input. Clean pages can receive the
retained write result; potentially dirty pages receive `status: observed` with
`write` and `runtimeRead`, not a new `saved` acknowledgment. This is the
orchestrator-approved split (overridable by the user), replacing the earlier
single Apply action for both operations.
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

ConfigQml >=0.5.3 is required for untouched-overlay preservation, native staged
draft Reset, selected publication and retained QML notification when an optional
leaf becomes absent. Package, Nix and devcontainer pins select the signed release;
0.5.2 introduced preservation and staged Reset but lacks the absence-notification
correction needed by retained selected clients.

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

AMD GPU and Battery Monitor keep source-qualified observation leases, not one
observer per view. All views of a captured context share its client; contexts
selecting the same device share readings/history. Replacing the selected source
releases its old lease. The last lease destroys its process owner. Battery's
sysfs helper and UPower fallbacks use the same selected device; an unavailable
explicit device cannot borrow another battery's readings.

NetBird selects polling, display, management URL and originating terminal policy
over one daemon/ping observer. Ping demand is aggregated across contexts and the
last demander retires the held process/queue. OpenVPN selects both polling tiers
and captures notification policy per admitted physical action. Multiple Panels
register independent visible/log demand for one shared stream. Tailscale captures
login-server and enabled/directory/mode before starting the one Taildrop receive
generation; retirement cancels all three stages and identity-fences completion.
Main/IPC stay explicitly plugin-level. Instance pages identify shared device,
daemon, profile, connection, account and file effects rather than promising
independent hardware or VPN sessions.

`plugin-settings-device-policy-check.py` parses all five members' declared fields,
factories, entries, lease/schedule/action mappings and shared-effect dictionaries,
with 20 rejecting controls. The NetBird native representative joins both page
scopes to actual Bar/Panel child Text, complete documents, staged Reset, Discard,
inheritance and separate nonpublishing cold readers. Individual observation,
private-UPower/sysfs and Taildrop drivers exercise unusual held-worker lifetimes,
same-device/view sharing and originating inert terminal/action outcomes. These
are finite controlled endpoints, not physical hardware, transfer/login, general
JavaScript proof or broad visual/final acceptance.

## Selected projections over retained shared state

Privacy Indicator retains one raw PipeWire/camera observation and one historical
document. Captured-context clients apply their own filters and notification
policy; simultaneous notification requests join one common admission and retired
requesters cannot emit later. Historical transitions and captured colors still
follow plugin-level policy. Instance Apply/Reset does not rewrite history.

KDE Connect retains one daemon/discovery/action owner. Main caches selected device
projections with the existing configured-device/reachability fallback behavior.
Bar, Control Center and Panel use that captured projection. Device selection uses
the originating runtime API, while a file chooser keeps the device captured at
Open rather than borrowing a later selection. Pairing/transfers affect the actual
shared device, not an independent per-widget daemon.

Calculator retains its one in-memory calculation. Selected clients project badge
visibility and precision; button, keyboard and percent actions pass the originating
precision to that shared calculation. They do not copy tokens, input or results.
Instance Settings explains the common calculation and physical/content effects.

`plugin-settings-projection-check.py` checks every declared field, factory, entry,
action and retirement mapping for this finite group, with rejecting controls.
The native regression joins real pages/native files to actual Bar/Panel children
in both scopes, independent full documents and nonpublishing cold readers. KDE's
runtime switch additionally publishes through its actual Panel/native owner.
Individual lifetime proofs exercise common notification admission/history bytes,
inert device discovery/actions and shared calculation/keyboard/percent behavior.
These controlled endpoints do not establish physical device or broad UI acceptance.

## Selected HTTP request and result ownership

News, ntfy Notifications and Habitica keep one Main-owned request/result client
per captured runtime context. Every Bar and Panel of that API shares it. Main/IPC
operations explicitly select the plugin-level client. News' Bars no longer own
duplicate producers or overwrite a common result array. Source replacement clears
old results and retires or fences the old XHR/process generation; changing a
nonempty credential is still a source change. Existing typed Timer boundaries and
country-to-language selection remain intact.

ntfy keeps its protected read-ID leaf and native writer in Main. Selected read
actions merge into that same owner without dropping another client's read IDs.
Selected request cursors and messages are separate; common desktop-notification
admission coalesces a server/message event across clients. Habitica keeps one
common score admission, with originating immutable account/auth/target inputs.
Replacing or retiring a serial request generation stops its next-stage timer and
process before it can continue, notify or publish a cache.

Habitica's existing plugin-level native cache owner remains singular. Only its
plugin-level client can save that leaf. Fresh cache results carry their nonsecret
user ID. Unqualified legacy cache bytes remain on disk but are not attributed to
a newly selected account; only an accepted fresh shared fetch replaces them.
Instance clients do not acquire a shared-cache writer or a new persistent store.
The instance pages describe the shared read-status, notification and remote-account
effects, rather than promising independent task state.

`plugin-settings-http-check.py` parses all 34 declared leaves, factories, runtime
entries, request/Timer/chain mappings and the two original operational writers.
Its finite controls complement the native regression's both-scope real controls,
complete independent documents, actual Bar/Panel children and unchanged-hash
edited/Reset/following cold readers. ntfy's actual Panel read action additionally
publishes through the original native owner. The separate lifetime driver covers
producer sharing/handoff, held responses, source/auth/empty selection, common
notifications, task filtering, literal inert scores/checklists and independent
complete-document shared-cache publication. These are controlled endpoints, not
remote account mutation, physical input, broad visual or final paired acceptance.

## Selected provider and request chains

GitHub Feed, Model Usage and Mawaqit resolve Main-owned clients by captured
runtime context. GitHub retires an immutable account/token/origin worker as a
whole, including pagination, parallel retries and queued remote read actions.
Its original Main remains the sole event-cache and avatar owner. Fresh events
carry nonsecret account/origin identity; legacy unqualified caches and login-only
avatars are not attributed to a new source. Common notifications are deduplicated.
An incomplete username/token has no request worker and presents the original
configuration guidance, rather than silently retaining an old account result.

Model Usage leases each configured provider observation across matching sources.
Disabled providers have no IO worker, and the last lease retires watches,
processes and XHRs. Provider options remain one atomic preference record; leases
are not stores. Claude credential replacement fences prior probes. Codex admits
the next fallback file after the current FileView callback, with its search
generation still current. The existing parsers, int timers and environment-key
precedence remain intact.

Mawaqit includes every tune integer in its prayer request identity. Old week,
fallback and retry work cannot populate a replacement source. Its Main retains
the eight original native cache leaves, month-only calendar helper and common
audio/notification owner. Only the current plugin-scope client writes the prayer
cache; fresh cache data records the full request tuple. Unqualified legacy bytes
remain stored but are not assigned a new tune identity. Explicit sound previews
remain immediate effects, not Apply/Discard operations.

The provider native regression joins actual GitHub controls, full native
documents, final Bar/Panel consumers and separate cold readers. Individual GitHub,
six-provider and prayer lifetime drivers use synthetic HOME, inert executables
and loopback HTTP only. They do not establish remote mutation, physical effects,
broad visual review or final paired acceptance.
The GitHub lifetime fixture also checks qualified cached/downloaded avatar paths
and PNG bytes across origins, including actual NImageRounded image loading, plus
held-download and retired-queue admission. Main converts its qualified filename
to a properly escaped file URL; filename percent escapes must not become URL
path separators. An
already admitted download retains its captured qualified target until completion;
its retired worker cannot publish availability or start the next queued item.

## Runtime authorization, not a Settings edit

Spotify Settings stages client ID/secret, callback port and player ID. It shows
the selected token status and directs the user to Apply first, then authorize in
the Spotify runtime Panel. It has no listener, browser, token exchange, device
discovery or page-to-owner action capability. Available token status describes
stored operational state, not a new server validation.

Main owns one Spotify IO client per captured runtime context. Actual runtime
actions pass their API and capture its applied credentials, token and player,
even when a different Settings preview is active. Main alone publishes generated
operational tokens through that runtime API. Authorization/refresh are distinct
from preference Apply/Discard; Discard does not undo an already authorized account.
Source replacement and retirement cancel listener/browser/request/process stages.
Playback's follow-up shuffle retains the admitted token/player, not later values.
Same-context views share one client; no independent accounts/devices are invented
for shared physical Spotify playback.

`plugin-settings-spotify-check.py` checks the finite eight-field contract and
rejects page-action, draft-input, shared-writer and lifetime controls. The native
regression joins actual Settings controls/native documents to Panel status,
runtime authorization, the real local callback listener with an inert browser,
loopback token/API responses, selected native writes and separate cold readers.
Its held continuations and wrong-state/writer controls are controlled endpoint
proof, not a real Spotify account, physical playback or broad visual acceptance.

## Selected calendar projections

Weekly Calendar retains one common CalendarService provider/cache owner. Main
owns one week/navigation/layout client per captured settingsContext; Bar and
Panel views of that API share it. Six selected display/range settings reach the
actual grid, hour labels and attachment behavior. Requested ranges are coalesced
across current clients instead of letting the last Panel narrow another's range.
Incoming common events update every active projection. Retirement fences queued
loads and releases the context client, not the calendar service or its data.
The instance page identifies common calendar observations. The existing Main-only
startup initializer remains separately known, not repaired by this projection.

The calendar regression joins real page controls/native Apply to actual Panel/Bar,
complete independent documents and nonpublishing edited/Reset/following/policy cold
readers in both scopes. Controlled common events exercise all-day/midnight/overlap
models, rendered children, navigation and range union; no real calendar provider
or external application is invoked. Finite parsed mappings and runtime wrong-client,
hour-child, range and retirement controls complement that proof. Broad visual and
final paired acceptance remain separate gates.

## Selected Bongo input and animation policy

SlowBongo retains one Main-owned Spectrum registration and one input observer per
demanded device string. Main caches one animation client per captured runtime
context, shared by all its Bars. Input dispatch filters against that client's
current source demand; geometry, colors, modes and typed idle/waiting timers use
its selected settings. Last-demand retirement fences input/check/retry work and
stops both processes. Client retirement stops pending animation timers.
The original common pause action remains common and is explained in instance
Settings. The legacy inputDevice leaf remains a Settings-only display fallback;
the runtime still selects inputDevices, without inventing a legacy consumer.

The Bongo native regression joins actual controls and complete native documents
to actual Bar child font/color, with nonpublishing cold readers. Its individual
lifetime proof covers common-source/view sharing, source replacement, real inert
input dispatch, audio/MPRIS projection, shared pause and pending retry/check
retirement. Audio, input enumeration and evtest are explicit inert collaborators,
not real device/player observation or broad visual/final acceptance.

## SSH helper lifetime, separate from selected session ownership

Hermes SSH's helper lifetime is independently owned: a thread-free same-script
child entry installs Linux PR_SET_PDEATHSIG before exec of the unchanged SSH argv,
then checks the expected parent to close the binding race. The helper handles
SIGTERM and controller-stdin EOF through its normal process-group stop/join path.
Abrupt helper death still terminates its direct SSH child. The helper regression
uses an inert SSH PTY child to prove original SIGTERM/SIGKILL reds, corrected
signal/EOF/disconnect outcomes, race refusal and three rejecting controls. This
does not by itself prove selected session/remembered-writer ownership, promise to
stop remote jobs, or establish a real SSH/account outcome.

## Selected SSH sessions

Hermes SSH Main owns one session per captured settingsContext. Bars and Panels
activate that context, and reopening a Panel retains its connection and terminal
buffer. Different contexts do not replace each other's target, status or output.
Connect validates the supplied originating runtime API before saving remembered
host/port/user; the generic Settings page never receives that writer. Passwords
remain transient. IPC and the single global shortcut remain plugin-level; instance
Settings explains this and does not offer a nonfunctional independent shortcut.
Stored shortcut overrides are retained, not reclassified or deleted.

Each connection owns a captured request and child Process generation. Replacement
fences its callbacks before stopping it. Context retirement and actual Main
destruction stop owned connections; helper-child lifetime uses the existing
qualified Linux binding. Auto-connect still waits for runtime-view activation,
captures target/size, and refuses after source/owner or manual-attempt replacement.
It does not silently retarget active connections. TerminalView receives its stream
source explicitly and replays the selected buffer on reopen/source handoff.

The Hermes native regression observes actual Settings intent, complete independent
documents, Bar/Panel consumers and nonpublishing cold readers in both scopes. Its
individual lifetime proof uses the real bridge with inert SSH/PTY output/input,
actual terminal TextEdit, originating native target writes, same-context reopen,
stream-source handoff, replacement and queued automatic attempts. Independent
PID/start identities are checked at replacement, native retirement and actual Main
destruction, not merely after test-engine exit. Finite parsed and runtime controls
complement this controlled proof; no real SSH account, network, physical shortcut,
broad visual or final paired acceptance is implied.

## Captured IPC sessions without placed entries

Dmenu is the reviewed no-instance IPC/session case: its manifest supplies only
Main, Panel and Settings, not a placed opener. Main captures applied menu defaults
and explicit request policy at IPC admission. API/generation identity fences file
loaders, delayed screen callbacks and the chain timer. Selection consumes the
captured prefix/toast/result/callback; later preferences cannot retarget it.
File-level configuration fills only absent request options. Panel chrome remains
live plugin-level presentation; Main alone admits close, including closeOnSelect.

The Dmenu regression drives actual IPC, real page controls/native documents and
actual Panel rows/results, plus a separate nonpublishing cold reader. Held real
file/screen completions and inert callbacks exercise replacement and retirement.
Generic page coverage includes both native editor scopes without claiming an
installed placed route. The finite checker covers all seven leaves; the catalog
inventory rejects newly added placed entry points for a no-instance review.
These are controlled endpoints, not physical input or broad visual acceptance.

## Captured Main windows

Wallcards and Somnus retain one Main-owned window each. Placed Bars capture their
API before window loading; another opener closes the existing presentation rather
than retargeting it. IPC explicitly supplies the plugin-level API. Retirement
unloads the captured window. Wallcards' runtime layout Save uses its captured
native writer. Somnus captures lock-on-suspend policy before Close admission.
Instance Settings identifies shared wallpaper, session and power effects.

`plugin-settings-window-check.py` parses both window/opener/field/writer/lifetime
mappings and rejects eight controls. `plugin-settings-window-regression.py` joins
actual controls, complete native documents and child card/button geometry in both
scopes, Discard/Apply/staged Reset/inheritance, separate cold windows and the actual
Wallcards runtime Save entry used by its keyboard handler. Somnus dispatches to
an inert compositor collaborator, never a real lock or power operation. Existing
Wallcards manifest-only filters, unused legacy leaves and its Qt5Compat dependency
remain separately identified, not claimed repaired by window ownership.

## Selected Todo presentation and export policy

Todo Panel/Desktop display policy follows the injected runtime API. Main retains
its existing common task/page owner. A Panel export supplies its captured read-only
context; Main/IPC without an origin explicitly use plugin scope. One admitted
request captures path, format, empty-section policy and common content before IO.
Another export visibly refuses while busy, without replacing that request. Normal
exit and failed process start settle the same request once. A retired origin cannot
start another action or receive late feedback; retirement does not roll back an
already admitted file publication. No content store, migration or deletion is added.

The Todo export regression joins actual generic controls/native documents to
filtered Panel task Text and actual JSON/Markdown files in both scopes, with
nonpublishing cold readers. Held requests, busy refusal, failed-start and failed
publication Retry, originating retirement and rejecting display/action controls
remain distinct from P001's renewed desktop-route/protected-content gate. These
controlled endpoints do not establish broad visual or final paired acceptance.

## Selected Tamagotchi games

Main owns one game per captured native runtime context. All renderers and their
Pet, Bed, Food, Ball, Debug, Stats and animation children use that same game.
The plugin-level background game remains active without a view. Retirement
stops the selected game and its timers; queued child actions cannot publish
through a retired origin. Game saves use the existing originating native API.
No content or operational field is migrated or reset by configuration editing.

The game regressions join actual controls, native documents and Bar/Panel Text
in both scopes, including separate nonpublishing cold readers. Individual
tests exercise real guest Wayland drag/drop, Food/Soap particles, Ball physics,
Debug/Bed actions, the original integer/random decay outcomes and an actual
30-second timer. Complete documents and wrong-game/child/writer/retirement
controls distinguish those outcomes from receipt or startup-only claims.
Audio checks observe selected volume, not physical playback. Existing integer
quantization is preserved, not certified as an ideal difficulty progression.
Broad visual and final paired acceptance remain separate.

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

## Selected Assistant requests over common conversation content

Assistant Main retains one conversation, draft input, translation result and cache.
Main owns one read-only policy client per captured runtime context. Runtime views
display that context's model and send/edit/regenerate/translate with its origin.
IPC stays explicitly plugin-level. Instance Settings identifies shared content and
the common clear/stop effects, without promising independent conversations.

Each admitted chat/translation owns one Process generation and immutable provider,
backend, endpoint, credentials, model, prompt, temperature and language inputs.
Parser choice follows that request, never a later view's settings. Source changes,
retirement and Main destruction stop/fence the owned worker. Failed process start
settles once. Content-save debounce retains its originating history limit without
truncating the live common conversation. Existing cache paths/format stay unchanged.
The legacy ai.model and ai.maxHistoryLength members retain their existing Settings
role; model resolution uses models[provider], and cache policy uses the top-level
maxHistoryLength. No new consumer or content migration is inferred for legacy keys.

The Assistant regressions join actual page intent/native complete documents to
actual model/response children and nonpublishing cold readers in both scopes.
Individual tests observe both providers, both translation parsers, environment-key
precedence, zero temperature, common admission, edit/regenerate/clear/stop, captured
cache policy, failed start and held source/native-origin/Main retirement. Endpoint
PID/start identities are checked before engine exit, not merely afterward. These
are inert curl collaborators and synthetic credentials, not external account,
network, physical input, broad visual or final paired acceptance.

## Selected profile folders over one shared effect owner

Profiles Main caches one listing/action client per captured runtime context.
Panel and rows use that same client; Bar icon/color remain selected direct reads.
Replacing a folder retires its old listing generation. Main retains one serial
raw-effect owner and captures directory, backup count, wallpaper choice, feedback
and originating native writer before IO. IPC stays explicitly plugin-level.
Instance Settings identifies the shared shell/colors/registry/wallpaper effects;
configuration Discard cannot roll back a profile action.

The active-profile indicator is acknowledged operation state, initialized from
the selected runtime owner and advanced only after accepted marker publication.
A failed native save retains its desired intent without falsely advancing that
indicator. Origin retirement refuses marker writeback and late feedback rather
than borrowing a replacement/shared writer; already-published raw files stay
applied. The raw helper format and existing rollback/publication policy stay intact.

Profiles regressions join actual controls/native complete documents to Panel row
Text/Bar icon and separate nonpublishing cold readers in both scopes. Actual raw
save/apply/rename/delete, held policy/common busy, native removal, failed start,
Main destruction and rejecting reader/child/writer/lifetime controls complement
the existing raw filesystem and full runtime failure/cold cases. These use
disposable files and inert effect collaborators, not the user's shell or physical
wallpapers, broad visual or final paired acceptance.

## Selected Claude policy over one ACP conversation

Claude Code Panel Main retains one conversation, draft, cache and serial ACP
process/session owner. Main-owned context clients select Panel/Bar policy. Every
queued prompt captures its originating context, atomic claude record and history
limit. A different origin or changed source replaces the process generation, not
the conversation. Source replacement, native retirement and Main destruction
fence old handshake/stream/permission continuations. Manual permission entries
retain exact process, session and RPC identity; no preference adds automatic
approval. Slash writers use the originating runtime API; IPC stays plugin-level.

The Claude native regression joins actual controls and complete native documents
to rendered cwd/reply and actual inert ACP cwd/prefix, both scopes, staged Reset,
Discard/inheritance and separate nonpublishing cold readers. Individual tests
observe serial originating queues, held handshake/stream retirement, manual
permission buttons and stale refusal, history debounce, native slash writes,
failed start and before-engine-exit process identities. Finite field/entry and
rejecting runtime controls complement these controlled endpoints. Existing
unused binary/model/tool/MCP/resume/permission options are not implemented or
certified; common conversation content is not migrated. No real CLI/account,
physical input, broad visual or final paired acceptance is implied.

## Selected Pomodoro timers

Main owns one transient timer per captured runtime context. All Bar/Panel views
of one API share it; other contexts do not replace its countdown or phase. IPC
and the legacy settings.json watcher keep the plugin-level native owner. Duration
and session policy retain the original QML int conversions. Current selected
policy governs subsequent phase/reset actions without resetting an already
admitted countdown. Retirement fences actions and queued auto-start, stops timers
and releases the alarm; Main destruction owns all child timers.

The Pomodoro native regression joins every actual configuration control, complete
independent documents and Bar time/Panel policy to edited/Reset/following cold
readers in both scopes. Individual tests observe phase/session policy, real1000ms
ticks, real5000ms alarm expiry, auto-start, source changes, native origin loss and
Main destruction. The existing P169 gate renews all four toggles with actual
Wayland pointer/keyboard and AT-SPI actions. Its pointer uses the compositor's
whole output layout and waits for the target's hover before clicking; its
accessibility probe uses the guest interpreter containing pyatspi. Inert sound
and notification collaborators prove call policy, not physical audio playback.
Common path-keyed audio/notice services are not per-instance devices. No timer
state store/migration or broad visual/final paired acceptance is implied.

## Existing worker-client matrices

Air Quality, Contributions and Arch Updater use the common worker matrix with
plugin-specific final Desktop children. Both scopes cover sparse publication,
Discard, failed IO/same-editor Retry, signal-before-callback, staged Reset,
base propagation, sibling independence and stale-editor retention. A separate
cold engine checks unchanged configuration hashes. Held old responses cross an
originating native runtime publication before release; an empty location/account
must remain empty, and a replacement update command must retain its new rows.
Actual native placement removal retires the exact client, not the shifted row.

The finite parsed contract covers all 41 declarations and every runtime entry.
Arch's `boldVer`/`desktopTip` are existing unused legacy declarations, and
`refreshTimer` currently controls page visibility, not worker timer policy (P006).
These are preserved, not newly claimed functional effects. Dedicated source-mode
legs also observe Air's EU scale, AQICN station, invalid/missing tokens and disabled
shared location; Contributions' GraphQL/error/public/compact/empty generations;
and Arch's system/AUR/inert Flatpak results and Flatpak removal. Existing keyboard
witnesses remain separate evidence. Every source-mode boundary compares complete
native documents, including native omit-equal removal, and retains other contexts.
Failed shared native IO keeps the unconfirmed shared value at the shared owner,
and inherited contexts equal it (unset inherits); overridden contexts and files
stay at persisted values. The witness waits for that consistent state; it is
never a successful receipt. No real network, account or package action is used.

## Catwalk existing-client matrix

Catwalk's broader matrix extends its original selected-instance witness. Both
page scopes exercise both real fields, Discard, native permission failure and
same-editor Retry, signal-before-callback, staged field Reset, base propagation,
overridden sibling/inherited placement independence and stale-editor retention.
Every boundary has complete independent shared/placement documents. Separate
cold engines preserve configuration hashes; actual native list removal retires
the exact client and both views without retargeting the shifted sibling.

The matrix observes actual Bar/Desktop Image sources, running/idle policy,
background choice and CPU Text with one controlled common CPU sample. The
two-field checker maps every entry and keeps Panel's shared physical statistics
separate from instance configuration. Wrong Bar/Desktop readers and a wrong
Image child must reject; parsed controls cover both intents and factory/lifetime
ownership. This is controlled binding/animation-policy proof, not physical CPU
sampling, screenshot/pixel fidelity or final paired acceptance.

## Selected Keybind parser generations

Keybind Cheatsheet Main caches one parser/result client per captured native
runtime context. Panel views share that client, not the plugin-level result.
Source replacement fences and destroys the complete nine-stage parser generation.
Colors, labels and column/split policy remain selected presentation bindings;
split-only and threshold-only changes rebuild the same category projection
without starting a new parser. Explicit Settings Refresh uses the applied runtime
context, not a draft path. IPC and the named BarService Settings route stay
plugin-level.

Only the plugin-level client publishes the existing state cache. Its exact source
tuple qualifies reuse; unqualified legacy cache bytes remain stored, not attributed
to a new source. Runtime description/hide actions use their originating native
API. That API returns a saveSelected publication receipt, not an editor receipt
with refreshState=current. A failed publication retains desired intent for Retry;
retirement refuses rather than adopting the shifted sibling's writer.

The Keybind regressions observe actual page controls, complete independent native
documents, Panel key/description/color/column children and nonpublishing cold
readers in both scopes. Separate proofs cover real state-file/cold cache reuse,
native runtime writers/failure/Retry/retirement, all nine held process stages,
failed exec/exit, empty/missing/malformed sources and controlled compositor
grammars. The finite checker covers all44 configuration leaves and both protected
operational leaves. The hidden keyLabelColor remains a fallback, not an invented
page control. Existing mode differences stay explicit: custom bind overrides are
hyprctl-only, and Mango does not gain sequential merging. These are inert parser
endpoints on the niri guest, not physical Hyprland/Mango or broad visual/final
paired acceptance.
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

## Admitted managed-resource policy

Agent Session Status keeps one server and in-memory session store. Applied
Settings or an originating Restart admits address, typed port and token before
the restart delay, waits for the old process and fences old HTTP responses.
Per-context pollers retain the original int-seconds/minimum-one policy; all views
observe the active service's common snapshot. Prune uses its admitted credentials.
Restart still clears sessions and is explicitly described as a shared effect.

Clamshell keeps one niri output observer and inhibitor. Applied Settings or
originating runtime toggles select enabled, connector, who and notification
policy; toggles retain their native API writer. A page completion never resaves
through Main. Replacement waits for old-inhibitor exit. Retirement stops the
admitted effect without retiring common observation or retargeting another API.
Both instance pages explain the common machine/resource effects; no content or
stored configuration is migrated.

The resource drivers separate finite every-field/caller/owner mappings, actual
scoped pages/native documents/nonpublishing cold engines and individual retained
restart/HTTP/inhibitor lifetimes. Controlled service and inhibitor endpoints are
not the host MCP, a real logind inhibitor or physical/broad visual acceptance.

## Backend ownership independent of renderers

Auto-cpufreq, Battery & Power Management and ThinkPad Fan have real Main entries.
Bars and popups resolve Main-owned clients by their own captured settings context;
a renderer never assigns itself as Main. Destroying or replacing one Bar cannot
remove another renderer's or an independently opened popup's backend.

CPU/fan observations and physical effects stay common. Auto-cpufreq clients retain
the original int Timer domain, including zero/fractional input, with initial
refresh. Its separate showGovernor/showTurbo feature gaps remain. Battery clients
select device-keyed physical observation/threshold owners; equal device paths
share one source and replacement retires the old subscription/processes. Power
profiles stay system-wide. Fan clients select palette/popup policy while actions
and delayed refresh retain their originating current context. No configuration
or content moves. Instance pages identify these shared effects.

The backend drivers join real page intent, complete native documents, Discard,
Apply, staged Reset/inheritance and separate nonpublishing cold readers to actual
Bar policy and popup child Text. The finite checker maps all fifteen fields and
every entry/physical owner, rejecting last-renderer/shared-popup/owner/lifetime
controls. Individual inert action/source/typed/zero cases verify retirement and
endpoint quiescence. These are not physical or broad visual/translation proofs.

## Selected clipboard projections

Clipboard keeps one full cliphist observation, shared pins, timestamps and image
cache in Main. API-keyed HistoryClient objects limit only their selected history
projection through literal `head -n` argv, preserving the existing Real domain,
including zero, negative and fractional inputs. Source/limit replacement and
retirement cancel the old projection; old results cannot publish into a new one.
Panel rows/counts, density and image presentation use the injected context.

The actual delegate passes its originating context to the shared decode queue.
Coalesced requests retain their admitted owners: one current requester can keep
the operation alive, while all-owner retirement cancels it and prevents queued
work or cache publication. Initial and recycled delegates use the same admission.
Content actions remain immediate and common, explicitly described in instance
Settings; no clipboard content or stored preferences move.

The clipboard drivers join actual SpinBox intent, complete native documents and
nonpublishing cold Panel Text/row consumers in both scopes. The finite checker
maps all three fields, callers and eight common process owners. Individual
typed projection, held replacement, coalesced decode and retirement cases use
inert clipboard/shell endpoints, intercepted before original temporary-file shell
redirections. These are not physical clipboard or broad visual/translation proofs.

## Selected OBS policy over shared output state

OBS Control keeps one Main-owned connection, credential reader, managed-launch
state and physical process/status domain. Main-owned context clients select its
seventeen presentation, polling and action fields. Bar, Control Center, its child
button and Panel resolve the same API-keyed client; opening a Panel carries the
originating runtime API. Main/IPC and the explicitly plugin-level Settings gear
remain shared. A client's retirement does not stop common status observation.

Action entry captures launch and resolved video/opener policy before probing.
The same operation identity/current-context fence covers WebSocket status/action,
four-output auto-close, termination, delayed confirmation and later Toast action.
Configuration replacement cannot retarget those stages. Managed-launch state
records the start's admitted choice, not a later view's preference. No new OBS
owner, preference store, credentials or content migration is introduced.

The OBS drivers join actual combo intent, complete native documents and separate
nonpublishing cold engines to actual Bar Text/CC visibility and child identities
in both scopes. Individual typed/poll/action/held-stage/Toast lifetimes use one
loopback protocol and inert executable endpoints. The finite parsed checker maps
every field, caller and physical owner with rejecting controls. These are not
physical OBS, broad visual/translation or final catalog proofs.

## Admitted Auto-Tile daemon policy

Auto-Tile retains one Main-owned daemon/config writer. Accepted Settings and
originating runtime actions select typed policy; Bar/Panel presentation and
native preference writes use their own captured API. Pending starts, serialized
config writes and USR1 continuations retain owner/generation. Every Python niri
query, action and stream uses a same-script parent-death-bound exec with a
post-binding parent check, so abrupt Main destruction cannot orphan that child.
The standalone omitted only-at-max flag still defaults true; explicit false
has a negative flag. Its unused legacy language leaf remains preserved.


The niri-policy native/lifetime drivers join real page intent, complete
native documents, separate nonpublishing cold readers and originating
native writes to actual inert Python argv/column-width consumers. Individual
typed/hot-reload/restart/retirement and direct-parent SIGKILL/race cases
supplement the eight-field parsed contract. Qualify this independent member
with plugin-settings-niri-group-check.py --plugin niri-auto-tile --selftest.
Screensaver has its separate policy qualification below, not covered by
Auto-Tile acceptance. No physical or broad visual/translation claim.

## Shared Sticky Notes synchronization

Sticky Notes keeps one Main-owned notes set, cache, expanded window, Gist ID and
sync status. Instance Settings identifies the shared effect and disables its
otherwise ineffective sync/token controls. Configure those in Settings > Plugins;
legacy overrides and content stay untouched. Sync now retains its accepted-Apply
completion gate and explicitly updates the same shared notes/Gist owner.

Each operation captures notes, token and target, retaining Main's native runtime
context. Credential, Gist or owner replacement cancels pending requests and fences
every HTTP continuation and native Gist-ID publication. The utility has no live
native writer; Main retains that responsibility. Automatic and explicit sync keep
their existing enabled/missing-token/busy policies. No notes/content migration.

The sticky native driver joins both actual page scopes and native configuration
files to real rendered common notes and loopback Gist requests. Separate cold
readers, field/whole configuration Reset and retained-request/source/destruction
cases supplement the finite four-field/caller/owner contract. Original ineffective
instance controls and late credential-replacement requests have independent reds.
All endpoints are inert, not GitHub-account, broad visual or final catalog proof.

## Selected Screensaver policy

Niri Screensaver retains one external config, idle entry and hook owner. Apply
selects the applied context; Bar/Settings launch and stop use originating applied
commands. Smart-toggle captures them before its status probe and refuses a
retired continuation. Config writes serialize and final policy wins. Hook
replacement/cleanup touches only the owner's exact command, never user-authored
hooks. Instance pages identify shared physical/session effects.

The niri-policy drivers separate finite every-field/caller/owner contracts, real
pages/native documents/nonpublishing cold readers, actual originating native
writes and individual config/probe/retirement lifetimes. Original shared-reader
and omitted-origin controls reject the wrong idle policy. Canonical runtime
Quit/Toggle and concurrent hook saves require the native completion correction
in ConfigQml acbb404; the intended released dependency floor is 0.5.4, not a
claim that it is already released. All compositor/screensaver/reload endpoints
are inert; these are not physical, broad visual/translation or final proofs.

## Hermes Agent finite CLI ownership prerequisite

The bridge's common command runner owns each oneshot and gateway start/stop CLI
through a fresh, thread-free same-script parent-death binding and post-binding
parent check before literal exec. Request timeouts still stop and join that CLI.
This does not grant ownership of independent gateway services or remote jobs.

`plugin-settings-hermes-child-regression.py` observes all three actual HTTP
dispatch paths with inert executable identities, normal completion and both
SIGTERM/SIGKILL parent death. Unbound controls reproduce survivors; timeout,
binding failure, retired-parent refusal and actual Main destruction have separate
outcomes. This helper prerequisite alone is not the full Hermes selected-context
proof; the original page/runtime lint and unfenced-XHR failures stay characterized
separately rather than being attributed to that helper correction.

Hermes Agent retains one applied connection/process/readers/token generation and
common chat. Context-keyed clients select presentation, polling and originating
model/pin actions. Apply keeps the active connection and chat; explicit session
replacement adopts pending connection inputs. Draft Test Connection is separately
input/lifetime-fenced. Local detection retains its plugin-level native writer;
retired callers cannot publish model or pin results. The native and lifetime
drivers observe real page intent, complete documents, nonpublishing cold readers,
rendered model/chat and inert HTTP/process boundaries. SSH and Agent native test
fixtures have distinct filenames; neither suite substitutes for the other.


## Verification boundaries

Hermes Agent retains one Main-owned chat/gateway and one applied connection
generation. That generation owns the local Process, state/token readers, retry
and HTTP requests. Connection changes stay pending through prompt completion;
only explicit New Session/session replacement adopts the originating current
context. Old readers and replies cannot publish into a replacement source.
Unauthenticated health/detection readiness is independent of local token loading;
credential changes fence authenticated requests. Local mode still uses localhost
and the manifest port, not the configured remote target.

Main-owned clients project selected polling/presentation; renderer construction
does not select a bridge or pinned owner. Runtime pin publication uses its
captured native API and raw saveSelected publication receipt, not an editor-only
refreshState field. Detection remains plugin-level local initialization and
cannot copy a remote/instance detection into shared preferences. Test Connection
remains a separate, generation-fenced draft probe. The Hermes native/lifetime
drivers separate complete native documents, cold model consumers, original and
omitted-origin controls, local file/token handoff and retained callbacks from
finite parsed field/caller contracts. Controlled endpoints are not actual Hermes
account, broad visual/translation or final catalog acceptance.

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

A failed shared Apply stays admitted in the native store so Retry can publish
it. Until then the plugin-level runtime, every inherited placement (unset
inherits, so it equals the shared value) and the page show the unconfirmed
value; overridden placements and files stay persisted, and the receipt is
failed/not-refreshed with the same page/editor retained. Retry publishes and
all readers agree on the saved value. Discard instead abandons exactly that
admitted Apply (ConfigQml `draft.abandonApply`, then the draft is dropped): every
reader returns to the saved value and no file is written. Losing the
presentation without an explicit Discard never abandons. The witness waits for
each consistent state and checks it at the plugin runtime, the inherited
placement, the page and the files, then fails again and Retries. No result
claims success from an unconfirmed value. These are actual route/native-owner witnesses
using the reviewed synthetic field page, not catalog Main/action or physical
input coverage.
