'use strict';
/* md-render.js -- self-contained markdown -> HTML renderer.
 * (cockpit-roadmap-redesign, Round 16 deliverable 2 -- operator: "The plans
 * are now displaying in a popup but it's still not rendering the
 * formatting.") No CDN (CSP blocks external requests); vanilla JS, dual-mode
 * (loads as a browser global AND as a plain Node `require()` -- no vm
 * sandbox needed for the selftest, unlike the extracted-source-region
 * convention used elsewhere in this codebase, because this file has no DOM
 * dependency at all).
 *
 * SHARED by BOTH callers per the plan's binding spec: roadmap.js's
 * openPlanDocModal (the plan-doc popup) and app.js's openDoc (the Docs
 * button panel) -- ONE renderer, no second implementation, both writing
 * into the SAME #docBody element (they already share that element; see
 * each file's own header comment).
 *
 * SECURITY (this is the load-bearing property -- read before editing):
 * escapeHtml() runs on every LEAF text segment before any markdown
 * substitution ever wraps it in a tag. Block-level structure (headings,
 * blockquotes, lists, tables, fences) is detected from the RAW, unescaped
 * line text -- never emitted directly -- so a doc's own literal "<" or ">"
 * characters are inert as SOON as they reach any output string. There is no
 * path from raw input to raw output: every branch below either (a) strips a
 * markdown-syntax prefix/wrapper and escapes what remains before use, or
 * (b) is fenced/inline code, escaped identically and never given inline
 * formatting. A caller could feed this a file containing a literal
 * "<script>alert(1)</script>" and it renders as the visible, inert text
 * "<script>alert(1)</script>" inside a <p> -- never a live tag (fixture-
 * proven in cockpit.selftest.js's MD-RENDER block).
 *
 * Links: only http(s) URLs become real <a href> (target=_blank,
 * rel=noopener noreferrer -- never leak a window.opener handle). A
 * repo-relative path (no URL scheme at all) renders as a plain, inert
 * "doc-link" span -- a visual cue that it's a reference, never a clickable
 * href (this repo doesn't have cross-doc navigation wired here; rendering
 * it as fake-clickable would be worse than plain text). Every OTHER scheme
 * (javascript:, data:, vbscript:, mailto:, etc.) is dropped down to plain
 * text -- the link syntax disappears, the label stays, no href is ever
 * emitted for it.
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

  function isHttpUrl(u) {
    return /^https?:\/\//i.test(String(u || '').trim());
  }
  // repo-relative == carries NO url scheme at all (rules out javascript:,
  // data:, mailto:, vbscript:, tel:, etc. -- anything "word:" -- and
  // protocol-relative "//host/path").
  function isRepoRelativePath(u) {
    var s = String(u || '').trim();
    if (!s) return false;
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(s)) return false;
    if (/^\/\//.test(s)) return false;
    return true;
  }

  var CODE_TOKEN_PREFIX = 'MDCODETOKEN';

  // ---- inline formatting: operates on an ALREADY-ESCAPED string. Code
  // spans are protected first via placeholder tokens (their content must
  // never receive bold/italic/link substitution), restored last. The token
  // is a plain-ASCII marker astronomically unlikely to appear in real
  // document text; even a collision is a cosmetic rendering miss, never a
  // security issue -- escaping already happened before this function runs.
  function renderInline(escaped) {
    var codeStash = [];
    var withCodeStashed = escaped.replace(/`([^`\n]+)`/g, function (_, code) {
      codeStash.push(code);
      return CODE_TOKEN_PREFIX + (codeStash.length - 1) + 'X';
    });

    var withLinks = withCodeStashed.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g, function (whole, text, url) {
      var rawUrl = url.split('&amp;').join('&'); // undo entity-escaping just to classify the scheme
      if (isHttpUrl(rawUrl)) {
        return '<a href="' + escapeHtml(rawUrl) + '" target="_blank" rel="noopener noreferrer">' + text + '</a>';
      }
      if (isRepoRelativePath(rawUrl)) {
        return '<span class="md-doc-link" title="' + escapeHtml(rawUrl) + '">' + text + '</span>';
      }
      return text; // unsafe/unsupported scheme -- text only, never an href
    });

    var withBold = withLinks
      .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
      .replace(/__([^_\n]+)__/g, '<strong>$1</strong>');
    var withItalic = withBold
      .replace(/\*([^*\n]+)\*/g, '<em>$1</em>')
      .replace(/(^|[^\w])_([^_\n]+)_(?!\w)/g, '$1<em>$2</em>');

    var tokenRe = new RegExp(CODE_TOKEN_PREFIX + '(\\d+)X', 'g');
    return withItalic.replace(tokenRe, function (_, idx) {
      return '<code>' + codeStash[Number(idx)] + '</code>';
    });
  }

  function renderInlineRaw(raw) {
    return renderInline(escapeHtml(raw));
  }

  function parseTableRow(raw) {
    var trimmed = raw.trim().replace(/^\|/, '').replace(/\|$/, '');
    return trimmed.split('|').map(function (c) { return c.trim(); });
  }
  function isTableSeparatorRow(raw) {
    if (!/\|/.test(raw)) return false;
    var cells = parseTableRow(raw);
    return cells.length > 0 && cells.every(function (c) { return /^:?-+:?$/.test(c); });
  }

  // renderMarkdown(raw) -> HTML string. Escaping-first (per file header);
  // never returns raw markdown syntax un-transformed AND never returns raw
  // HTML from the input untouched.
  function renderMarkdown(raw) {
    var lines = String(raw == null ? '' : raw).replace(/\r\n?/g, '\n').split('\n');
    var out = [];
    var i = 0;
    var n = lines.length;
    var para = [];

    function flushParagraph() {
      if (!para.length) return;
      out.push('<p>' + renderInlineRaw(para.join(' ')) + '</p>');
      para = [];
    }

    while (i < n) {
      var line = lines[i];

      // fenced code block -- content escaped, never inline-formatted.
      var fenceMatch = /^\s*```(\w*)\s*$/.exec(line);
      if (fenceMatch) {
        flushParagraph();
        var codeLines = [];
        i++;
        while (i < n && !/^\s*```\s*$/.test(lines[i])) { codeLines.push(lines[i]); i++; }
        if (i < n) i++; // skip the closing fence; EOF-without-close degrades gracefully
        var langClass = fenceMatch[1] ? ' class="language-' + escapeHtml(fenceMatch[1]) + '"' : '';
        out.push('<pre class="md-code"><code' + langClass + '>' +
          codeLines.map(escapeHtml).join('\n') + '</code></pre>');
        continue;
      }

      // blank line -- paragraph separator
      if (/^\s*$/.test(line)) { flushParagraph(); i++; continue; }

      // ATX heading
      var headingMatch = /^(#{1,6})\s+(.*)$/.exec(line);
      if (headingMatch) {
        flushParagraph();
        var level = headingMatch[1].length;
        out.push('<h' + level + '>' + renderInlineRaw(headingMatch[2].trim()) + '</h' + level + '>');
        i++; continue;
      }

      // blockquote -- consecutive '>' lines, recursively rendered (the '>'
      // prefix is stripped from RAW text before ever reaching escapeHtml,
      // so a literal '>' inside the quoted prose is unaffected).
      if (/^\s*>\s?/.test(line)) {
        flushParagraph();
        var quoteLines = [];
        while (i < n && /^\s*>\s?/.test(lines[i])) {
          quoteLines.push(lines[i].replace(/^\s*>\s?/, ''));
          i++;
        }
        out.push('<blockquote>' + renderMarkdown(quoteLines.join('\n')) + '</blockquote>');
        continue;
      }

      // table: a "|"-row immediately followed by a ---|--- separator row
      if (/\|/.test(line) && i + 1 < n && isTableSeparatorRow(lines[i + 1])) {
        flushParagraph();
        var headerCells = parseTableRow(line);
        i += 2;
        var bodyRows = [];
        while (i < n && /\|/.test(lines[i]) && !/^\s*$/.test(lines[i])) {
          bodyRows.push(parseTableRow(lines[i]));
          i++;
        }
        var thead = '<thead><tr>' + headerCells.map(function (c) {
          return '<th>' + renderInlineRaw(c) + '</th>';
        }).join('') + '</tr></thead>';
        var tbody = '<tbody>' + bodyRows.map(function (r) {
          return '<tr>' + r.map(function (c) { return '<td>' + renderInlineRaw(c) + '</td>'; }).join('') + '</tr>';
        }).join('') + '</tbody>';
        out.push('<table class="md-table">' + thead + tbody + '</table>');
        continue;
      }

      // lists -- unordered (-/*) or ordered (1.), incl. "- [ ]"/"- [x]" tasks
      var listItemMatch = /^\s*([-*]|\d+\.)\s+(.*)$/.exec(line);
      if (listItemMatch) {
        flushParagraph();
        var ordered = /\d+\./.test(listItemMatch[1]);
        var items = [];
        while (i < n) {
          var m = /^\s*([-*]|\d+\.)\s+(.*)$/.exec(lines[i]);
          if (!m) break;
          items.push(m[2]);
          i++;
        }
        var tag = ordered ? 'ol' : 'ul';
        var liHtml = items.map(function (item) {
          var cb = /^\[( |x|X)\]\s+(.*)$/.exec(item);
          if (cb) {
            var checked = cb[1].toLowerCase() === 'x';
            var glyph = checked ? '&#9745;' : '&#9744;';
            return '<li class="md-task' + (checked ? ' md-task-done' : '') + '">' +
              '<span class="md-cb" aria-hidden="true">' + glyph + '</span> ' +
              renderInlineRaw(cb[2]) + '</li>';
          }
          return '<li>' + renderInlineRaw(item) + '</li>';
        }).join('');
        out.push('<' + tag + '>' + liHtml + '</' + tag + '>');
        continue;
      }

      // plain prose line -- accumulates into the current paragraph
      para.push(line.trim());
      i++;
    }
    flushParagraph();
    return out.join('\n');
  }

  var api = {
    renderMarkdown: renderMarkdown,
    renderInline: renderInline,
    escapeHtml: escapeHtml,
    isHttpUrl: isHttpUrl,
    isRepoRelativePath: isRepoRelativePath,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.MdRender = api;
})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));
