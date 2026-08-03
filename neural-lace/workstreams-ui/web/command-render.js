'use strict';
/* command-render.js -- shared command-aware text renderer.
 * (Cockpit Round 17 deliverable 2, audit F1 -- the operator's own top
 * complaint: "it's not clear where the command begins and ends.") Every
 * surface that shows server-authored prose which CAN carry a runnable
 * command (Inbox context/option-outcomes/my-pick/reply-with, the Health
 * "What needs me" cards, My-items rows, interrupt-strip chips) rendered
 * that prose as one plain proportional-font run -- indistinguishable from
 * narrative text, no copy affordance, a wrong hand-selection running a
 * broken command. Meanwhile ONE surface (the quarantine lane's "open
 * source session" row) already had the right pattern: a readonly
 * monospace input + a "Copy" button. This module generalizes THAT pattern
 * into one shared renderer, reused everywhere instead of re-solved per
 * caller (Nielsen #4 consistency -- the app already owned the right
 * answer).
 *
 * Dual-mode (browser global AND plain Node `require()`), same convention
 * as md-render.js -- no CDN, no build step, no DOM dependency in the pure
 * renderCommandAwareText()/isCommandLine() half (so the selftest can real-
 * execute it with zero jsdom/headless-browser dependency); the tiny DOM-
 * touching half (wireCommandCopyButtons) is guarded and only registers
 * when `document` actually exists.
 *
 * SECURITY (escaping-first, same discipline as md-render.js): every leaf
 * segment is escapeHtml()'d BEFORE it is ever placed inside a tag or a
 * `data-copy-text` attribute. A backtick span or a recognized command line
 * containing "<script>" renders as inert escaped text, never a live tag.
 *
 * WHAT COUNTS AS A COMMAND (deliberately narrow, matching the audit's own
 * enumeration -- a broad heuristic risks false-positiving ordinary prose
 * that happens to start with a capitalized product name):
 *   - an inline `backtick span` anywhere in a line (the universal fence
 *     marker -- needs-you.sh's own producer-side lint is expected to use
 *     it, per the audit's "Required generalization"), and
 *   - a WHOLE LINE that starts (case-SENSITIVE, lowercase -- real CLI
 *     invocations in this codebase are always literal lowercase, so a
 *     capitalized "Claude Fable will now..." prose sentence never
 *     false-positives) with one of: "$ ", "powershell ", "claude ",
 *     "nl ", "git ", "bash ".
 */
(function (root) {
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .split('&').join('&amp;')
      .split('<').join('&lt;')
      .split('>').join('&gt;')
      .split('"').join('&quot;')
      .split("'").join('&#39;');
  }

  var COMMAND_LINE_RE = /^\s*(\$\s|powershell\s|claude\s|nl\s|git\s|bash\s)/;
  function isCommandLine(line) {
    return COMMAND_LINE_RE.test(String(line == null ? '' : line));
  }

  // fencedChipHtml(cmdText) -- the one place a "cmd-fence" chip is built:
  // a monospace <code> + a copy button carrying the RAW (escaped-for-
  // attribute) text in data-copy-text, read by wireCommandCopyButtons at
  // click time (never re-parsed from the visible, possibly-truncated
  // textContent).
  function fencedChipHtml(cmdText) {
    var esc = escapeHtml(cmdText);
    return '<span class="cmd-fence">' +
      '<code class="cmd-fence-code">' + esc + '</code>' +
      '<button type="button" class="cmd-copy-btn" data-copy-text="' + esc + '">Copy</button>' +
      '</span>';
  }

  // renderInlineLine(line) -- a line with NO recognized command shape of
  // its own still gets its `backtick spans` promoted to fenced chips;
  // everything else is escaped plain text (never re-escaped twice: the
  // split keeps delimiters, so each piece is escaped exactly once).
  function renderInlineLine(line) {
    var parts = String(line == null ? '' : line).split(/(`[^`]+`)/);
    return parts.map(function (part) {
      if (part.length > 1 && part.charAt(0) === '`' && part.charAt(part.length - 1) === '`') {
        return fencedChipHtml(part.slice(1, -1));
      }
      return escapeHtml(part);
    }).join('');
  }

  // A producer-authored command almost never arrives bare: needs-you.sh
  // writes numbered steps ("STEP 3: powershell -File ...", "2. git pull"),
  // and the label defeated the whole-line test above -- MEASURED on the
  // operator's own live Inbox item NY-1785425479-0d4d, where `git pull`
  // alone is recognized but `STEP 2: git pull` renders as flat prose with
  // no fence and no Copy button. That is the operator's complaint
  // ("commands ... should stand out and make it easy for me to copy")
  // surviving Round 17 because the producer and the detector disagreed
  // about the shape of a command line.
  //
  // Deliberately as narrow as the whole-line list: only an explicit step
  // label is peeled, and the REMAINDER must still satisfy the same
  // COMMAND_LINE_RE. The label stays prose; only the runnable half is
  // fenced, so a copy never picks up "STEP 3: ".
  var STEP_LABEL_RE = /^(\s*(?:step\s+\d+|\d+)\s*[.:)]\s+)/i;
  function splitStepLabel(line) {
    var s = String(line == null ? '' : line);
    var m = s.match(STEP_LABEL_RE);
    if (!m) return null;
    var rest = s.slice(m[1].length);
    return isCommandLine(rest) ? { label: m[1], command: rest } : null;
  }

  function renderLine(line) {
    var s = String(line == null ? '' : line);
    if (isCommandLine(s)) return fencedChipHtml(s.trim());
    var split = splitStepLabel(s);
    if (split) return escapeHtml(split.label) + fencedChipHtml(split.command.trim());
    return renderInlineLine(s);
  }

  // isActionLine(line) -- "does this line ask the operator to RUN
  // something". The Inbox uses it to hoist the actual ask above the
  // explanation; it is the union of the two shapes renderLine fences.
  function isActionLine(line) {
    return isCommandLine(line) || !!splitStepLabel(line);
  }

  // renderCommandAwareText(text) -> HTML string. A single-line input (the
  // common case: an option outcome, my-pick, reply-with, a to-do item's
  // text) renders INLINE -- no wrapping block element -- so it still sits
  // naturally inside a caller's own "label: " prefix text node. A genuinely
  // multi-line input (a raw §3-format block, a multi-line context field)
  // gets one <div class="cat-line"> PER line (never a bare <br> join -- a
  // real element per line matches this codebase's own per-line convention,
  // e.g. inbox.js's ib-context-line divs, and gives a stable per-line hook
  // for spacing).
  function renderCommandAwareText(text) {
    var raw = String(text == null ? '' : text);
    if (raw === '') return '';
    var lines = raw.split('\n');
    if (lines.length === 1) return renderLine(lines[0]);
    return lines.map(function (line) {
      return '<div class="cat-line">' + renderLine(line) + '</div>';
    }).join('');
  }

  // wireCommandCopyButtons(container) -- ONE event-delegated click listener
  // per persistent container (idempotent: a re-render that wipes and
  // rebuilds the container's CHILDREN, e.g. innerHTML='', never needs a
  // second wire-up as long as `container` itself is the same node every
  // render — the delegation catches newly-added buttons for free). No-op
  // in a DOM-free context (the selftest requires this file with no
  // `document` at all).
  function wireCommandCopyButtons(container) {
    if (typeof document === 'undefined' || !container || container.__cmdCopyWired) return;
    container.__cmdCopyWired = true;
    container.addEventListener('click', function (e) {
      var btn = e.target && e.target.closest && e.target.closest('.cmd-copy-btn');
      if (!btn) return;
      e.stopPropagation();
      var text = btn.getAttribute('data-copy-text') || '';
      if (root && root.navigator && root.navigator.clipboard && root.navigator.clipboard.writeText) {
        root.navigator.clipboard.writeText(text).catch(function () {});
      }
      var orig = btn.textContent;
      btn.textContent = 'copied';
      setTimeout(function () { btn.textContent = orig; }, 1200);
    });
  }

  var api = {
    renderCommandAwareText: renderCommandAwareText,
    isCommandLine: isCommandLine,
    isActionLine: isActionLine,
    splitStepLabel: splitStepLabel,
    wireCommandCopyButtons: wireCommandCopyButtons,
    escapeHtml: escapeHtml,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.CommandRender = api;
})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));
