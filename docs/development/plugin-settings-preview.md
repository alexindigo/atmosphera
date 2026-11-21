# Selected plugin preview

Runtime `pluginApi.settingsView` is the effective read view for preview-aware
consumers; runtime `pluginSettings` remains their preference/write boundary.
Generic pages instead receive isolated reads and explicit field capabilities.
Their injected `previewSettings(patch)` admits declared configuration leaves
through those same field setters before updating the selected preview. The page
cannot use preview as a content writer or bypass native Apply. No disk
publication occurs until Apply. Shared and placement APIs have independent sessions.
An inherited placement reads the shared preview, then its stored overrides, then
its own preview patch, in that order. A placement preview never changes shared
or sibling settings.

The popup captures preview revisions at Apply. Current success acknowledges only
those field revisions; newer preview input remains pending. Failed/stale results
retain the preview and local work. Discard/destruction releases only that session,
revealing current underlying values without restoring an opening snapshot. An old
session cannot clear a replacement session; callbacks after owner destruction are
inert.

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
