# Selected plugin preview

`pluginApi.settingsView` is the effective read view for preview-aware consumers;
`pluginSettings` remains the preference/write boundary. A settings page calls its
injected `previewSettings(patch)` with top-level setting leaves. This updates only
the selected owner's presentation patch and the page's local data, never its
persistent owner. Shared and placement API objects have independent sessions.
An inherited placement reads the shared preview, then its stored overrides, then
its own preview patch, in that order. A placement preview never changes shared
or sibling settings.

The popup captures preview revisions at Apply. Current success acknowledges only
those field revisions; newer preview input remains pending. Failed/stale results
retain the preview and local work. Discard/destruction releases only that session,
revealing current underlying values without restoring an opening snapshot. An old
session cannot clear a replacement session; callbacks after owner destruction are
inert.

The old instance owner uses a conservative list-structure fence (excluding
instanceSettings). Ambiguous replacement/reorder stops runtime projection onto a
different row while retaining local work for discard. Foreign instance preference
edits keep the same binding. The existing old-owner equal/suppressed-ABA limits
remain. I5 replaces these structural stamps with native normalized owner identity
and supplies draft values for the active read view, store values otherwise.

`plugin-settings-preview.qml` observes bound text consumers across shared and all
four placement routes, foreign edits, reorder refusal, held/current/no-op/stale
receipts, real IO failure, explicit discard, owner destruction and cold restart.
The callbacks gate also retains the actual popup's legacy-page close witness.
