# Selected plugin preview

Runtime `pluginApi.settingsView` is the effective read view for preview-aware
consumers; runtime `pluginSettings` remains their preference/write boundary.
Generic pages instead receive isolated reads and explicit field capabilities.
Their injected `previewSettings(patch)` first acquires the selected preview.
Its admitted update writes declared configuration leaves once through the same
field setters before recording preview revisions. A foreign preview refusal
does not change the page's existing draft or field intent. The page
cannot use preview as a content writer or bypass native Apply. No disk
publication occurs until Apply. Shared and placement APIs have independent sessions.
An inherited placement reads the shared preview, then its stored overrides, then
its own preview patch, in that order. A placement preview never changes shared
or sibling settings.

The popup captures preview revisions at Apply. Current success acknowledges only
those field revisions; newer preview input remains pending. Failed/stale writer results
retain the preview and local work. Discard/destruction releases only that session,
revealing current underlying values without restoring an opening snapshot. An old
session cannot clear a replacement session; callbacks after owner destruction are
inert.

After saved/current native Apply, the selected session leaves its preview when
all captured revisions have been acknowledged. Those values are now committed,
not unsaved input. It keeps the same editor/page/input and waits for ConfigQml's
causal observation on the actual runtime reader before delivering completion.
Newer pending preview revisions and every failed/stale-write preview remain
untouched; no unsaved input is discarded. A saved-but-unobserved failure retains
the write receipt for observation-only Retry, without another Apply or page
staging. Another session's inherited preview is not closed by this handoff.

## Historical pre-cutover owner

The old instance owner uses a conservative list-structure fence (excluding
instanceSettings). Ambiguous replacement/reorder stops runtime projection onto a
different row while retaining local work for discard. Foreign instance preference
edits keep the same binding. The existing old-owner equal/suppressed-ABA limits
remain. I5 replaces these structural stamps with native normalized owner identity
and supplies draft values for the active read view, store values otherwise.

`settings-retained-preview-regression.py` requires an explicit verified guest
profile and fresh work/output roots. It runs `plugin-settings-preview.qml`
against an owned install copy, observing bound text consumers across shared and
all four placement routes, foreign edits, reorder refusal, held/current/equal/
no-op/stale receipts, real IO failure, explicit discard, owner destruction and
a separate cold restart. Independent reads check saved values, the failed
linked destination's inode/bytes and the quarantined directory's sentinel.
Its disposable `field-capture` and `preview-revision` negative controls must
fail at their exact consumer assertions; they are not production coverage.

Busy page preview actions refuse without losing newer local input. Once the
held receipt completes, that input can update the selected preview. Captured
preview revisions independently prevent an older acknowledgment from clearing
newer fields. The native session regression consolidates the historical popup
fixture's actual native-hide/held-result, directory-quarantine and untracked
local-buffer Close cases, alongside Apply/Reset, callback ordering and cold
consumers. No legacy snapshot page API is restored by those tests.

`popup-close-regression.py` also requires the verified guest profile. Its nine
generic dirty/busy Close and replacement routes use an actual selected native
editor and hold real completion delivery. Stale/reentrant adoption and the same
QObject's later-opening restoration are checked without assigning private popup
state. Independent final-file and separate cold consumers cover the generic
publication. Its three distinct live-field dialogs retain controlled submission
receipts for Close, native hide and failed-input confirmation; those rows do not
claim native live-field persistence or change their immediate-edit contract.
