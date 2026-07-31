# Fragment: cockpit-roadmap-redesign Task 4 — shell wiring for web/index.html

Task 4 (branch `build/roadmap-t4`) ships the Inbox view (`web/inbox.js`) as
a self-mounting module — UNLIKE `requests.js`/`roadmap.js`, it does NOT
insert its own wrapper subtree: task 3 already shipped static markup for
this tab (`#inboxSection`/`#inboxBody`/`[data-age-for="inbox"]`/
`#inboxMissBanner` in `index.html`, ~line 111) that nothing else writes to
anymore (app.js's interim Inbox renderer was REMOVED, not just overridden,
in this same task's `build/roadmap-t4` commit — see that commit for why:
the interim renderer independently drove `#inboxTabCount` on its own timer,
which would otherwise race inbox.js's own count update and violate "the two
counts can never disagree", A10). So this fragment is the ONE new
script-tag line, same discipline as `roadmap-t3-server-fragment.md`/
`roadmap-t5-shell-fragment.md`'s own precedent — PLUS a corrective fix for
a pre-existing defect discovered adjacent to this line (§2 below).

## 1. web/index.html — the ONE new script-tag line

Add, immediately after the existing (correctly-placed) script tags at the
bottom of the file, right before `</body>`:

```html
  <script src="/asks.js"></script>
  <script src="/todo.js"></script>
  <script src="/backlog.js"></script>
  <script src="/app.js"></script>
  <script src="/roadmap.js"></script>
  <!-- inbox.js loads AFTER app.js/roadmap.js for the same reason
       requests.js does: it registers 'inbox' into window.WorkstreamsShell,
       and is now the ONLY registerView('inbox', ...) call in the app
       (app.js's interim one was REMOVED, not overridden — see the
       build/roadmap-t4 commit). Served by server/inbox-routes.js (the
       one-line server.js mount — see roadmap-t4-server-fragment.md). -->
  <script src="/inbox.js"></script>
</body>
</html>
```

Without this line, the Inbox tab degrades to a permanent loading/error
state (inbox.js never loads, so nothing ever writes `#inboxBody` or
`#inboxTabCount`) — a loud, honest interim state, never a silent partial
merge.

## 2. Corrective fix: the task-5 `requests.js` script tag landed inside an HTML comment (pre-existing defect, discovered here, bundled since this fragment already edits the same file)

`roadmap-t5-shell-fragment.md` §1 specified inserting
`<script src="/requests.js"></script>` "immediately after the existing
`roadmap.js` script tag" at the BOTTOM of the file. The splice that actually
applied it (commit `40414d0`, message: "server.js mount + index.html script
tag") instead landed that exact line INSIDE the multi-line HTML comment
block documenting "TAB 1 — Roadmap" near the TOP of the file (between that
comment's opening `<!--` and closing `-->`, around what is currently line
43 of `web/index.html`). A commented-out `<script>` tag never executes:
`requests.js` — the ENTIRE Requests ledger view's client module — is not
loaded by the live page at all today, despite `requests-routes.selftest.js`
and `cockpit.selftest.js`'s T5 suite both being green (neither exercises the
actually-served `index.html`'s script tags at the DOM/browser level, so
nothing caught this).

**Current (broken) shape** — the misplaced line sits inside the comment:

```html
  <!-- ============================================================
       TAB 1 — Roadmap (the landing tab). Rendered by web/roadmap.js from
  <script src="/requests.js"></script>
       GET /api/roadmap (server/roadmap-routes.js). The toolbar controls
       live HERE (static DOM) so filter text + toggle state trivially
       survive the view's state-preserving re-renders (C7).
       ============================================================ -->
```

**Corrective diff** — remove the misplaced line from inside the comment
(restoring that comment to its original, presumably-intended prose), and
add the SAME line in its originally-specified location at the bottom of the
file (right before `app.js`'s already-correct `roadmap.js` tag — order
relative to `inbox.js` above doesn't matter, but keeping the established
`asks → todo → backlog → app → roadmap → requests` load order matches
task 5's own stated intent):

```html
  <!-- ============================================================
       TAB 1 — Roadmap (the landing tab). Rendered by web/roadmap.js from
       GET /api/roadmap (server/roadmap-routes.js). The toolbar controls
       live HERE (static DOM) so filter text + toggle state trivially
       survive the view's state-preserving re-renders (C7).
       ============================================================ -->
```

```html
  <script src="/asks.js"></script>
  <script src="/todo.js"></script>
  <script src="/backlog.js"></script>
  <script src="/app.js"></script>
  <script src="/roadmap.js"></script>
  <script src="/requests.js"></script>
  <script src="/inbox.js"></script>
</body>
</html>
```

This is bundled into THIS fragment (rather than filed as a separate,
undirected "please fix index.html later" note) because whoever applies
task 4's own shell fragment is already editing this exact file in this
exact region — fixing both in one pass avoids a second round-trip. An
`nl-issue.sh` note has also been filed for the harness-level gap (a splice
landed content in the wrong location with no gate catching it) —
independent of this specific fix, since the general problem ("a fragment
application step has no verification that the result actually executes")
can recur for any future fragment, not just this one.

## Integration points to re-verify at merge

- Browser: the Inbox tab shows "Awaiting your answer (N)" / the win state /
  the quarantine section per the live ledger; `#inbox/<id>` lands (switch +
  expand + scroll + highlight + focus + "← back"); a gone id renders the
  miss banner.
- Browser (regression check, since this fragment also fixes task 5's
  defect): the Requests tab's ledger section (title/timeline/filter/
  age-groups) now actually renders — it did NOT before this fix landed.
- `node neural-lace/workstreams-ui/web/cockpit.selftest.js` → rc 0 (T4-* block).
