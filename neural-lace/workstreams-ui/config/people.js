'use strict';
/* config/people.js — hostname→person map for the peer view's PERSON
 * grouping (cockpit-roadmap-redesign Task 7, round 5 operator intent:
 * "Both Jaime and I may be using multiple computers ... I need the ability
 * to have this same sync between my own computers" — peers group by PERSON,
 * e.g. "Misha: desktop + laptop").
 *
 * Two-layer config, IDENTICAL convention to config/projects.js:
 *   - SHIPPED, generic: config/people.example.json (placeholders only —
 *     real hostnames / personal names never ship in the kit).
 *   - PER-MACHINE, gitignored: config/people.json (the real map).
 *   - COCKPIT_PEOPLE_FILE env override (tests + non-default location).
 *
 * NAMED FAILURE RENDERINGS (the task-1 named-absence generalization —
 * every derivation names its failure rendering):
 *   - file ABSENT           -> NOT an error: { map: {}, error: '' }. Every
 *     hostname then resolves to no person and the reader renders it under
 *     the literal "unassigned" group — a named state, never a guess.
 *   - file present but UNREADABLE or MALFORMED -> { map: {}, error:
 *     '<what failed>' }. The reader (peer-view.js -> web peers pane)
 *     surfaces the error naming the failing component (this config file)
 *     and renders every machine under "unassigned" meanwhile — degraded
 *     AND labeled, never silently flat.
 *
 * Node stdlib only — NO runtime deps (module-wide invariant).
 */
const fs = require('fs');
const path = require('path');

function peopleFilePath() {
  return process.env.COCKPIT_PEOPLE_FILE || path.join(__dirname, 'people.json');
}

// loadPeople() -> { map: { <hostname-lowercased>: <person> }, error: '' }
// Hostname keys are lowercased at load; lookups lowercase the probe — the
// match is case-insensitive (Windows hostnames surface in inconsistent
// case across APIs). Never throws.
function loadPeople() {
  const file = peopleFilePath();
  let raw;
  try {
    if (!fs.existsSync(file)) return { map: {}, error: '' }; // absent = unconfigured, not broken
    raw = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return { map: {}, error: 'person map unreadable (' + path.basename(file) + '): ' + String(e && e.message || e) };
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    return { map: {}, error: 'person map parse failed (' + path.basename(file) + '): ' + String(e && e.message || e) };
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { map: {}, error: 'person map malformed (' + path.basename(file) + '): expected an object of {"hostname": "person"}' };
  }
  const map = {};
  Object.keys(parsed).forEach(function (k) {
    if (k === '_comment') return;
    if (typeof parsed[k] === 'string' && parsed[k]) map[k.toLowerCase()] = parsed[k];
  });
  return { map: map, error: '' };
}

// personForHost(host, people) -> person string, or null when unmapped (the
// caller renders null as the named "unassigned" group — never a guess).
function personForHost(host, people) {
  if (!host || !people || !people.map) return null;
  return people.map[String(host).toLowerCase()] || null;
}

module.exports = { loadPeople, personForHost, peopleFilePath };
