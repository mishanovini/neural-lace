#!/bin/bash
# if-statement-check.sh — the anti-restatement checker for Intended-Functionality statements.
#
# WHAT THIS IS
#   Stage 0 of docs/designs/end-to-end-process.md requires every plan to carry an
#   Intended-Functionality (IF) statement. The operator's governing rule:
#
#     "An IF statement that names only artifacts ('the script exists', 'the gate is
#      wired', 'the field renders') is REJECTED. The test: could this sentence be true
#      while the operator's situation is unchanged?"
#
#   This script decides as much of that as can HONESTLY be decided mechanically, and
#   routes the rest to the operator instead of guessing. It is deliberately a
#   THREE-verdict checker, not a binary one.
#
# VERDICTS / EXIT CODES
#   0  ACCEPT       — positive evidence of functionality; no restatement signal.
#   1  REJECT       — a hard restatement signal fired, or a required field is
#                     missing/unpopulated, or a human dependency is marked DEFECT.
#   2  UNDECIDABLE  — no hard reject signal, but not enough positive evidence to
#                     ACCEPT. THIS IS NOT A PASS. It means: a human must clarify.
#                     The caller must route it to the operator, never resolve it by
#                     assumption (end-to-end-process.md stage 0 escalation rule).
#   3  usage error
#
# MODES
#   if-statement-check.sh <plan-file>          full section extraction + all checks
#   if-statement-check.sh --outcome "<text>"   anti-restatement core on one sentence
#   if-statement-check.sh --corpus <dir>...    measurement mode (see --help)
#   if-statement-check.sh --self-test
#
# HONEST SCOPE — what this checker CANNOT decide (do not overclaim it):
#   It matches vocabulary and word order. It does not parse grammar and it does not
#   know your domain. It catches the SHAPE the operator named — an artifact noun in
#   subject position carrying an existence/wiring predicate, with no state change
#   anywhere in the sentence — but that coverage is bounded by its vocabularies: a
#   restatement built from nouns or verbs not in these lists is NOT caught. It cannot tell
#   whether a well-formed sentence is TRUE, whether the named surface really exists,
#   or whether a fluent sentence is secretly a component description dressed in
#   outcome vocabulary. Those are exactly the cases that return UNDECIDABLE or that a
#   human reviewer must catch. See `doctrine/intended-functionality.md`.
#
# Portability floor: /bin/bash 3.2.57 (no associative arrays, no mapfile, no ${v,,}).

set -u

SELF_NAME="if-statement-check.sh"

# ---------------------------------------------------------------------------
# Vocabularies. Space-delimited, lowercase, padded by the matcher.
# ---------------------------------------------------------------------------

# Nouns that name a thing a builder produces. An IF statement whose SUBJECT is one
# of these is describing a component, not an outcome.
IF_ARTIFACT_NOUNS="script scripts gate gates hook hooks field fields file files
function functions endpoint endpoints test tests suite suites flag flags column
columns component components button buttons agent agents check checks checker
validator validators section sections table tables config schema schemas migration
migrations module modules class method methods variable variables parameter
parameters handler handlers route routes page pages form forms modal helper wrapper
library package service services worker workers job jobs queue cron marker markers
entry entries record records line lines block blocks header headers rule rules doc
docs documentation template templates api sdk cli ui code codebase branch commit
commits repo repository directory folder path env var vars setting settings toggle
toggles chip chips row rows cell cells card cards panel panels tab tabs menu list
array object json yaml regex pattern selector query index cache store db database
binary daemon watcher listener middleware wrapper shim stub mock fixture harness
pipeline workflow step steps stage stages command commands chip chips banner
badge badges label labels tooltip icon icons modal dialog dropdown checkbox
selftest self-test suite runner parser linter formatter"

# Predicates that assert a thing was BUILT or is PRESENT. These are the verbs that
# make a sentence true the moment the code lands, regardless of whether anything
# changed for the operator.
# NOTE — the bare forms `work`, `run`, `pass`, `fire` are DELIBERATELY ABSENT. Each is
# far more often a NOUN in real plan prose ("harness-dev work", "in-flight work",
# "a test run", "fire-and-forget") than a predicate, and including them drove 9 of 34
# rejections in the 2026-07-30 corpus measurement — every one a false positive. The
# inflected forms carry the real predicate sense with no such ambiguity.
IF_EXISTENCE_PREDICATES="exists exist existed present runs ran running
wired added creates created implemented defined registers
registered configured renders render rendered compiles compiled passes
passed exported installed enabled hooked invoked integrated connected built written
landed shipped merged committed documented tested covered validated fires fired
triggered deployed available setup"

# Referents to a person whose situation could change.
IF_HUMAN_REFERENTS="i me my mine we us our ours operator operators user users human
humans maintainer maintainers anyone someone somebody nobody person people team
teams you your customer customers client clients reader readers session-owner
misha"

# Verbs describing an observable change of state from the outside.
IF_CHANGE_VERBS="becomes become resumes resume continues continue stops stop
appears appear disappears disappear updates update changes change reflects reflect
shows show displays display receives receive gets get
recovers recover retries retry arrives arrive lands land completes complete finishes
finish alerts alert notifies notify warns warn surfaces surface reaches reach
reopens reopen closes close starts start restarts restart drops drop rises rise
reduces reduce increases increase decreases decrease prevents prevent blocks block
unblocks unblock refuses refuse allows allow proceeds proceed advances advance moves
move persists persist survives survive produces produce yields yield emits emit
sends send delivers deliver saves save applies apply keeps keep loses lose gains
gain regains regain wakes wake picks pick goes go went turns turn turned
progresses progress moving breaks broke resumes"

# Perception is NOT a state change. "I see the script exists" reports an observation
# about an artifact; the operator's situation is identical before and after. Keeping
# see/notice in the change vocabulary is what let the golden scenario be defeated by
# the prefix "I see " (harness-reviewer C1, 2026-07-30).
IF_PERCEPTION_VERBS="see sees seeing saw seen notice notices noticing noticed
observe observes observed tell tells telling told watch watches check checks"

# Connectors that, on their own, signal a change in the operator's situation.
IF_CHANGE_CONNECTORS="without no-longer instead automatically unattended
by-itself on-its-own untouched hands-off"

# Verbs that, heading a sentence, mark it as a work instruction rather than an
# outcome. Deliberately excludes make/keep/close/fix/give/prevent/stop/ensure —
# those head genuine outcome statements too often to treat as a reject signal.
# The same noun-dominance sweep applied to IF_EXISTENCE_PREDICATES applies here, and
# was initially missed: `ship`, `file`, `land`, `write`, `produce`, `port` and `update`
# are all common sentence-INITIAL nouns in plan prose ("Ship dates stop slipping",
# "File sizes drop"), and R4 matches on the literal first word — so each produced a
# false REJECT on a legitimate outcome (harness-reviewer M7, PROVEN). Removed.
IF_DELIVERY_IMPERATIVES="build add create implement apply seed author
expand rebuild install wire register catalog reshape
encode triage migrate introduce"

# Tokens that make a pass/fail rule decidable without judgement. Deliberately TIGHT:
# an earlier, looser list scored "…enough to count as working" as deterministic
# because it contained the word "count" (self-test D5). Ordinary prose words are out;
# a real threshold almost always carries a digit anyway.
IF_COMPARATORS="within exactly zero at-least at-most no-more-than no-fewer-than
non-empty empty exit-code equals identical matches"

# Judgement vocabulary. If the pass/fail rule contains any of these it is NOT a rule
# with "no judgement call", however many numbers it also carries.
IF_JUDGEMENT_WORDS="judgement judgment subjective opinion looks looked seems seem
seemed reasonable reasonably healthy appropriate adequate sufficient enough properly
correctly good acceptable roughly approximately generally mostly probably likely
feels feel sensible sane nicely cleanly satisfactory fine ok okay"

# ---------------------------------------------------------------------------
# Core matcher. Emits: R1=<0|1> R2=<0|1> R3=<0|1> plus the evidence tokens.
# All offset arithmetic is done in awk so the result is bash-version independent.
# ---------------------------------------------------------------------------

# BSD awk rejects a literal newline inside an `-v` assignment, so every value
# crossing that boundary is flattened to one line first. (Found by self-test on
# /bin/bash 3.2 + BSD awk: "awk: newline in string ... at source line 1".)
if_oneline() { printf '%s' "$1" | tr '\n\r\t' '   '; }

if_anti_restatement() {
  # $1 = sentence text
  awk -v sentence="$(if_oneline "$1")" \
      -v artifacts="$(if_oneline "$IF_ARTIFACT_NOUNS")" \
      -v predicates="$(if_oneline "$IF_EXISTENCE_PREDICATES")" \
      -v humans="$(if_oneline "$IF_HUMAN_REFERENTS")" \
      -v changes="$(if_oneline "$IF_CHANGE_VERBS")" \
      -v connectors="$(if_oneline "$IF_CHANGE_CONNECTORS")" \
      -v imperatives="$(if_oneline "$IF_DELIVERY_IMPERATIVES")" '
  # Two normalizations, deliberately:
  #   phrase-mode keeps hyphens so multiword connectors ("no-longer") stay lookupable;
  #   word-mode splits hyphens so a compound artifact noun matches on its head
  #   ("self-test" -> "self test" matches the artifact noun "test").
  # Found by self-test A4: "The self-test passes" escaped R1 under phrase-mode alone.
  function norm(s, keep_hyphen,   t) {
    t = tolower(s)
    gsub(/no longer/, "no-longer", t)
    gsub(/on its own/, "on-its-own", t)
    gsub(/by itself/, "by-itself", t)
    if (keep_hyphen) gsub(/[^a-z0-9-]+/, " ", t)
    else             gsub(/[^a-z0-9]+/, " ", t)
    gsub(/^ +| +$/, "", t)
    gsub(/  +/, " ", t)
    return " " t " "
  }
  # Lowest character offset at which any token from list appears as a whole word.
  # Returns 0 when no token matches.
  function first_hit(hay, list, hitname,   n, i, arr, p, best) {
    best = 0
    n = split(list, arr, /[ \t\n]+/)
    for (i = 1; i <= n; i++) {
      if (arr[i] == "") continue
      p = index(hay, " " arr[i] " ")
      if (p > 0 && (best == 0 || p < best)) { best = p; hitname = arr[i] }
    }
    HIT = hitname
    return best
  }
  # Same, but only considering matches strictly after min_off. Needed because the
  # globally-first predicate is not necessarily the main verb: in "The running chip
  # renders green", "running" is an ADJECTIVE sitting before the subject noun, so
  # comparing global firsts made R1 miss a textbook restatement. What matters is
  # whether a predicate follows the artifact subject.
  function first_hit_after(hay, list, min_off, hitname,   n, i, arr, p, best, start) {
    best = 0
    n = split(list, arr, /[ \t\n]+/)
    for (i = 1; i <= n; i++) {
      if (arr[i] == "") continue
      start = min_off
      while ((p = index(substr(hay, start + 1), " " arr[i] " ")) > 0) {
        p = p + start
        if (p > min_off) break
        start = p
      }
      if (p > min_off && (best == 0 || p < best)) { best = p; hitname = arr[i] }
    }
    HIT = hitname
    return best
  }
  # 1-based word index of the token starting at character offset off.
  function word_index(hay, off,   head, n, tmp) {
    if (off <= 0) return 0
    head = substr(hay, 1, off)
    n = gsub(/ /, " ", head)   # gsub returns the substitution count
    return n
  }
  BEGIN {
    SUBJECT_WINDOW = 8
    sw = norm(sentence, 0)   # word-mode: hyphens split
    sp = norm(sentence, 1)   # phrase-mode: hyphens kept

    # Asymmetric on purpose:
    #   artifacts/predicates use WORD-mode so a compound matches on its head
    #     ("self-test" is a test);
    #   humans use PHRASE-mode so a compound ADJECTIVE is not mistaken for a
    #     reference to a person ("user-facing documentation" names no user;
    #     "end-user", "customer-facing", "Misha-directed" likewise). Splitting
    #     these produced FALSE ACCEPTS in the 2026-07-30 corpus run — the
    #     dangerous direction, since a false ACCEPT lets a restatement through.
    a_off = first_hit(sw, artifacts);  a_tok = HIT
    p_off = first_hit(sw, predicates); p_tok = HIT
    h_off = first_hit(sp, humans);     h_tok = HIT
    c_off = first_hit(sw, changes);    c_tok = HIT
    k_off = first_hit(sp, connectors); k_tok = HIT

    # R4 — DELIVERY IMPERATIVE. A sentence that opens by commanding a build
    # ("Build v1 of the UI", "Add the sub-agent", "Seed the templates") is a work
    # instruction, not a statement of what becomes true for the operator. Only
    # unambiguous delivery verbs are listed: "make", "keep", "close", "fix",
    # "give", "prevent", "stop" are excluded because they routinely head genuine
    # outcome statements ("Keep my work moving without me poking it").
    r4 = 0
    first_word = sw; sub(/^ /, "", first_word); sub(/ .*$/, "", first_word)
    n = split(imperatives, iarr, /[ \t\n]+/)
    for (i = 1; i <= n; i++)
      if (iarr[i] != "" && first_word == iarr[i]) { r4 = 1; i_tok = first_word }

    # R1 — RESTATEMENT. An artifact noun stands in SUBJECT position and carries an
    # existence/wiring predicate, with no person named before that predicate.
    # This is the operator counter-example shape: "the watchdog script exists and runs".
    #
    # "Subject position" is bounded to the opening SUBJECT_WINDOW words, not merely
    # "somewhere before the predicate": in a 40-word sentence some artifact noun and
    # some predicate token co-occur in that order by chance, which is precisely how
    # the first corpus run manufactured false positives. A real restatement puts the
    # artifact up front.
    a_widx = word_index(sw, a_off)
    # The predicate that matters is the first one occurring AFTER the artifact
    # subject, not the globally-first one.
    pa_off = 0; pa_tok = "-"
    if (a_off > 0) { pa_off = first_hit_after(sw, predicates, a_off); pa_tok = HIT }

    # The veto on R1 is the absence of CHANGE, not the absence of a person.
    # Vetoing on a human referent was defeated by a three-word framing clause: "I see
    # the watchdog script exists and runs" named a person, so the veto fired, so the
    # gate ACCEPTed its own golden counter-example — and the UNDECIDABLE message
    # printed the missing token, teaching the evasion (harness-reviewer C1, PROVEN).
    # Naming a person does not make a sentence an outcome; only a state change does.
    # Perception verbs are excluded from `changes` for exactly this reason: observing
    # that an artifact exists leaves the operator situation identical.
    # R2 — OBSERVABLE STATE CHANGE present? (computed before R1, which vetoes on it)
    r2 = (c_off > 0 || k_off > 0) ? 1 : 0

    # R3 — HUMAN REFERENT present?
    r3 = (h_off > 0) ? 1 : 0

    r1 = 0
    if (pa_off > 0 && a_off > 0 && a_widx <= SUBJECT_WINDOW && r2 == 0) {
      r1 = 1; p_off = pa_off; p_tok = pa_tok
    }

    printf "R1=%d R2=%d R3=%d R4=%d ARTIFACT=%s PREDICATE=%s HUMAN=%s CHANGE=%s CONNECTOR=%s IMPERATIVE=%s\n", \
      r1, r2, r3, r4, (a_off?a_tok:"-"), (p_off?p_tok:"-"), (h_off?h_tok:"-"), \
      (c_off?c_tok:"-"), (k_off?k_tok:"-"), (r4?i_tok:"-")
  }'
}

# Decidability of a pass/fail rule: needs a digit or an explicit comparator token.
if_has_decision_rule() {
  awk -v sentence="$(if_oneline "$1")" \
      -v comparators="$(if_oneline "$IF_COMPARATORS")" \
      -v judgement="$(if_oneline "$IF_JUDGEMENT_WORDS")" '
  function norm(s,   t) {
    t = tolower(s)
    gsub(/at least/, "at-least", t); gsub(/at most/, "at-most", t)
    gsub(/no more than/, "no-more-than", t); gsub(/no fewer than/, "no-fewer-than", t)
    gsub(/exit code/, "exit-code", t); gsub(/non empty/, "non-empty", t)
    gsub(/[^a-z0-9-]+/, " ", t)
    gsub(/^ +| +$/, "", t); gsub(/  +/, " ", t)
    return " " t " "
  }
  function hit(hay, list,   n, i, arr) {
    n = split(list, arr, /[ \t\n]+/)
    for (i = 1; i <= n; i++) {
      if (arr[i] == "") continue
      if (index(hay, " " arr[i] " ") > 0) return arr[i]
    }
    return ""
  }
  BEGIN {
    s = norm(sentence)
    # Direct negation flips the sense: "with no judgement call", "not subjective",
    # "without opinion" are DECLARATIONS OF DETERMINISM, not judgement vocabulary.
    # Unconditional substring matching rejected the plan templates own instructional
    # phrasing ("the rule with no judgement call") — the gate failing the field it was
    # teaching the author to write. (harness-reviewer M8.)
    gsub(/(with |having )?(no|zero|without|not any) (judgement|judgment|opinion|subjectivity)( call| calls)?/, " deterministic-declaration ", s)
    gsub(/not (subjective|judgemental|judgmental)/, " deterministic-declaration ", s)
    # Judgement vocabulary vetoes the rule regardless of any threshold present.
    j = hit(s, judgement)
    if (j != "") { print "0 judgement-word:" j; exit }
    if (s ~ /[0-9]/) { print "1 digit"; exit }
    c = hit(s, comparators)
    if (c != "") { print "1 comparator:" c; exit }
    print "0 no-threshold-or-comparator"
  }'
}

# ---------------------------------------------------------------------------
# Verdict for a bare outcome sentence.
# Prints "ACCEPT|REJECT|UNDECIDABLE <reason>"; returns the matching exit code.
# ---------------------------------------------------------------------------
if_check_outcome() {
  local text="$1"
  local sig r1 r2 r3 r4 art pred imp

  if [[ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]]; then
    echo "REJECT outcome-empty"
    return 1
  fi

  sig="$(if_anti_restatement "$text")"
  r1="$(printf '%s\n' "$sig" | sed -n 's/.*R1=\([01]\).*/\1/p')"
  r2="$(printf '%s\n' "$sig" | sed -n 's/.*R2=\([01]\).*/\1/p')"
  r3="$(printf '%s\n' "$sig" | sed -n 's/.*R3=\([01]\).*/\1/p')"
  r4="$(printf '%s\n' "$sig" | sed -n 's/.*R4=\([01]\).*/\1/p')"
  art="$(printf '%s\n' "$sig" | sed -n 's/.*ARTIFACT=\([^ ]*\).*/\1/p')"
  pred="$(printf '%s\n' "$sig" | sed -n 's/.*PREDICATE=\([^ ]*\).*/\1/p')"
  imp="$(printf '%s\n' "$sig" | sed -n 's/.*IMPERATIVE=\([^ ]*\).*/\1/p')"

  if [[ "$r1" == "1" ]]; then
    echo "REJECT restatement:artifact-subject='$art'+existence-predicate='$pred'"
    return 1
  fi
  if [[ "$r4" == "1" ]]; then
    echo "REJECT work-instruction-not-outcome:leading-delivery-verb='$imp'"
    return 1
  fi
  if [[ "$r2" == "1" && "$r3" == "1" ]]; then
    echo "ACCEPT state-change+human-referent"
    return 0
  fi
  # No hard reject signal, but not enough positive evidence. A human decides.
  echo "UNDECIDABLE missing:$([[ "$r2" == "0" ]] && printf 'observable-state-change ')$([[ "$r3" == "0" ]] && printf 'human-referent')"
  return 2
}

# ---------------------------------------------------------------------------
# Section + field extraction from a plan file.
# ---------------------------------------------------------------------------
if_extract_section() {
  # $1 = plan file. Prints the body of "## Intended Functionality" (may be empty).
  awk '
    /^##[ \t]+Intended[ \t]+Functionality[ \t]*$/ { inside = 1; next }
    inside && /^##[ \t]/ { inside = 0 }
    inside { print }
  ' "$1" 2>/dev/null
}

if_extract_field() {
  # $1 = section body (stdin-safe via var), $2 = label regex
  printf '%s\n' "$1" | awk -v label="$2" '
    BEGIN { pat = "^[-*[:space:]]*\\*\\*" label }
    $0 ~ pat {
      inside = 1
      line = $0
      sub(pat "[^*]*\\*\\*[:[:space:]]*", "", line)
      sub(/^[-*[:space:]]*\*\*[^*]*\*\*[:[:space:]]*/, "", line)
      if (line != "") print line
      next
    }
    inside && /^[-*[:space:]]*\*\*[A-Za-z]/ { inside = 0 }
    inside && /^##[ \t]/ { inside = 0 }
    inside { print }
  '
}

if_nonspace_len() {
  printf '%s' "$1" | tr -d '[:space:]' | wc -c | tr -d ' '
}

# Strip the template's own instructional placeholder text so an unfilled template
# never counts as a populated field.
if_is_placeholder() {
  # A field whose first non-blank line opens with a bracketed token is still the
  # template's own instructional text ("[dependency] — INTENDED | DEFECT",
  # "[What we're building]"). Without this the DEFECT check fires on the template's
  # instruction line and reports a misleading reason for an otherwise correct reject.
  printf '%s' "$1" | grep -qiE '\[(populate|todo|fill|your|describe|e\.g\.|example)|^[[:space:]]*(todo|tbd|n/a|\.\.\.)[[:space:]]*$|<[a-z-]+>' && return 0
  printf '%s\n' "$1" | grep -vE '^[[:space:]]*$' | head -1 | grep -qE '^[[:space:]]*[-*]?[[:space:]]*\[[A-Za-z]'
}

# ---------------------------------------------------------------------------
# Full plan-file check.
# ---------------------------------------------------------------------------
if_check_plan() {
  local plan="$1"
  local section outcome observation rule notincl humandeps
  local rc=0 worst=0
  local findings=""

  if [[ ! -f "$plan" ]]; then
    echo "REJECT plan-file-not-found: $plan"
    return 1
  fi

  section="$(if_extract_section "$plan")"
  if [[ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]]; then
    echo "REJECT missing-section '## Intended Functionality'"
    return 1
  fi

  outcome="$(if_extract_field "$section" 'Outcome')"
  observation="$(if_extract_field "$section" 'Observation')"
  rule="$(if_extract_field "$section" 'Deterministic pass/fail')"
  notincl="$(if_extract_field "$section" 'Explicitly NOT included')"
  humandeps="$(if_extract_field "$section" 'Human dependencies')"

  # S2 — every required field present and populated.
  local f name val
  for f in "Outcome:$outcome" "Observation:$observation" \
           "Deterministic pass/fail:$rule" "Explicitly NOT included:$notincl" \
           "Human dependencies:$humandeps"; do
    name="${f%%:*}"; val="${f#*:}"
    if [[ "$(if_nonspace_len "$val")" -lt 20 ]] || if_is_placeholder "$val"; then
      findings="${findings}field-missing-or-unpopulated:'$name' "
      worst=1
    fi
  done
  if [[ "$worst" == "1" ]]; then
    echo "REJECT $findings"
    return 1
  fi

  # S3 — every human dependency tagged; any DEFECT fails stage 0 outright.
  # (end-to-end-process.md: the watchdog's "operator must arm the marker" was marked
  #  DEFECT and "fails immediately at stage 0".)
  local dep_lines untagged
  dep_lines="$(printf '%s\n' "$humandeps" | grep -cE '[^[:space:]]' || true)"
  if printf '%s\n' "$humandeps" | grep -qE '\bDEFECT\b'; then
    echo "REJECT human-dependency-marked-DEFECT (an unintended human step means the outcome is not delivered)"
    return 1
  fi
  # Only LIST-ITEM lines are dependencies. A wrapped continuation or a parenthetical
  # note under a bullet is part of the preceding dependency, not a new untagged one —
  # counting those made a correctly-tagged section fail (caught by dogfooding this
  # check against this feature's own plan).
  untagged="$(printf '%s\n' "$humandeps" | grep -E '^[[:space:]]*[-*][[:space:]]+[^[:space:]]' | grep -cvE '\b(INTENDED|DEFECT|none|NONE|None)\b' || true)"
  if [[ "${untagged:-0}" -gt 0 ]]; then
    echo "REJECT human-dependency-untagged ($untagged line(s) carry neither INTENDED nor DEFECT)"
    return 1
  fi

  # S4 — the pass/fail rule must be decidable without judgement.
  # Two different epistemic situations, deliberately given different verdicts:
  #   judgement vocabulary present  -> positive EVIDENCE of non-determinism -> REJECT
  #   no threshold/comparator found -> ABSENCE of evidence, not evidence of absence.
  #     A digit-free binary predicate ("the commit is refused and the plan file is left
  #     unchanged") is perfectly deterministic, so rejecting it was a false positive.
  #     Downgraded to UNDECIDABLE: a human decides. (harness-reviewer M8.)
  local ruleverdict rulereason; ruleverdict="$(if_has_decision_rule "$rule")"
  rulereason="${ruleverdict#* }"
  if [[ "${ruleverdict%% *}" != "1" ]]; then
    case "$rulereason" in
      judgement-word:*)
        echo "REJECT pass-fail-rule-not-deterministic ($rulereason)"
        return 1
        ;;
      *)
        echo "UNDECIDABLE pass-fail-rule-has-no-threshold-or-comparator (a binary predicate may still be deterministic; a human decides)"
        return 2
        ;;
    esac
  fi

  # R — the anti-restatement core, applied to the Outcome field.
  local verdict
  verdict="$(if_check_outcome "$outcome")"; rc=$?
  echo "$verdict"
  return $rc
}

# ---------------------------------------------------------------------------
# Corpus measurement mode.
# ---------------------------------------------------------------------------
if_corpus() {
  # Runs the anti-restatement core over the outcome-shaped sentence of every plan
  # in the given directories: the first sentence of the plan's `## Goal` section.
  # This is the only real corpus of human-written outcome statements that exists.
  local acc=0 rej=0 und=0 skipped=0 total=0
  local d f goal sentence verdict rc
  local detail="${IF_CORPUS_DETAIL:-0}"

  for d in "$@"; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*.md; do
      [[ -f "$f" ]] || continue
      case "$f" in *-evidence*.md|*completion-report*) continue ;; esac
      total=$((total+1))
      goal="$(awk '
        /^##[ \t]+Goal[ \t]*$/ { inside=1; next }
        inside && /^##[ \t]/ { inside=0 }
        inside && /[^[:space:]]/ { print; }
      ' "$f" 2>/dev/null | grep -vE '^[[:space:]]*[-*>|]' | head -3 | tr '\n' ' ')"
      sentence="$(printf '%s' "$goal" | sed 's/\([.!?]\)[[:space:]].*/\1/' )"
      if [[ "$(if_nonspace_len "$sentence")" -lt 15 ]]; then
        skipped=$((skipped+1)); continue
      fi
      verdict="$(if_check_outcome "$sentence")"; rc=$?
      case $rc in
        0) acc=$((acc+1)); [[ "$detail" == "1" ]] && printf 'ACCEPT\t%s\t%s\n' "$(basename "$f")" "$sentence" ;;
        1) rej=$((rej+1)); [[ "$detail" == "1" ]] && printf 'REJECT\t%s\t%s\t%s\n' "$(basename "$f")" "$sentence" "$verdict" ;;
        2) und=$((und+1)); [[ "$detail" == "1" ]] && printf 'UNDECIDABLE\t%s\t%s\t%s\n' "$(basename "$f")" "$sentence" "$verdict" ;;
      esac
    done
  done
  printf 'corpus: total=%d measured=%d skipped-no-goal=%d ACCEPT=%d REJECT=%d UNDECIDABLE=%d\n' \
    "$total" "$((acc+rej+und))" "$skipped" "$acc" "$rej" "$und"
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
if_self_test() {
  local passed=0 failed=0
  # Deliberately NOT `local` — the EXIT trap runs after this function's frame is
  # gone, and `set -u` would abort on an unbound local.
  IF_SELFTEST_TMP="$(mktemp -d 2>/dev/null || echo "/tmp/ifcheck.$$")"
  local tmp="$IF_SELFTEST_TMP"
  mkdir -p "$tmp"
  trap 'rm -rf "$IF_SELFTEST_TMP"' EXIT

  _expect_outcome() { # name, expected-code, text
    local name="$1" want="$2" text="$3" out rc
    out="$(if_check_outcome "$text")"; rc=$?
    if [[ "$rc" == "$want" ]]; then
      echo "self-test ($name): PASS" >&2; passed=$((passed+1))
    else
      echo "self-test ($name): FAIL (want exit $want, got $rc — $out)" >&2; failed=$((failed+1))
    fi
  }
  _expect_plan() {
    local name="$1" want="$2" file="$3" out rc
    out="$(if_check_plan "$file")"; rc=$?
    if [[ "$rc" == "$want" ]]; then
      echo "self-test ($name): PASS" >&2; passed=$((passed+1))
    else
      echo "self-test ($name): FAIL (want exit $want, got $rc — $out)" >&2; failed=$((failed+1))
    fi
  }

  # --- A. THE OPERATOR'S OWN COUNTER-EXAMPLE. Must REJECT. -------------------
  _expect_outcome "A1-operator-counterexample" 1 "The watchdog script exists and runs."
  _expect_outcome "A2-gate-wired"              1 "The gate is wired into the pre-commit hook."
  _expect_outcome "A3-field-renders"           1 "The new status field renders on the settings page."
  _expect_outcome "A4-test-passes"             1 "The self-test passes with 499 assertions."
  _expect_outcome "A5-hook-registered"         1 "The hook is registered in settings.json."
  # C1 REGRESSION (harness-reviewer, 2026-07-30): the golden scenario with the block
  # message's own advice applied as a framing clause. Naming a person must NOT rescue
  # a restatement, and perception is not a state change.
  _expect_outcome "A6-framing-clause-evasion"  1 "I see the watchdog script exists and runs."
  _expect_outcome "A7-framing-clause-evasion2" 1 "When I look, the operator sees the gate is wired."

  # --- B. THE FIVE REAL DEFECTS OF 2026-07-30, correctly stated. Must ACCEPT. -
  _expect_outcome "B1-watchdog" 0 \
    "After a usage limit resets, my work continues without me touching anything."
  _expect_outcome "B2-shape-only" 0 \
    "When I break a behaviour the suite claims to cover, the suite goes red and I see the failure."
  _expect_outcome "B3-drag" 0 \
    "When I drag a plan row onto another group, the row appears in that group and stays there after I reload."
  _expect_outcome "B4-running-signal" 0 \
    "A green running chip means work is progressing for me right now, and it turns grey within a minute of that work stopping."
  _expect_outcome "B5-self-learning" 0 \
    "When I correct the same mistake twice, I stop seeing it a third time without filing anything."

  # --- C. UNDECIDABLE — no reject signal, not enough positive evidence. -------
  _expect_outcome "C1-vague-no-human" 2 "Latency improves across the estate."
  _expect_outcome "C2-no-change-verb" 2 "The operator has a reliable pipeline."

  # --- D. Full plan-file mode. -----------------------------------------------
  cat > "$tmp/good.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** After a usage limit resets, my work continues
without me touching anything.
**Observation:** The session resumes on its own and the transcript shows activity
timestamped after the reset.
**Deterministic pass/fail:** Resumption happened within 5 minutes of the reset with
zero human actions recorded in between.
**Explicitly NOT included:** Does not promise resumption after a crash, only after a
usage-limit reset.
**Human dependencies:**
- None required at runtime — INTENDED

## Goal
x
PLAN
  _expect_plan "D1-complete-good-plan" 0 "$tmp/good.md"

  cat > "$tmp/nosection.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Goal
Do the thing.
PLAN
  _expect_plan "D2-missing-section" 1 "$tmp/nosection.md"

  cat > "$tmp/restate.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** The watchdog script exists and runs on a schedule.
**Observation:** The script is present in the scripts directory and the log shows it
executing every fifteen minutes as configured.
**Deterministic pass/fail:** The process list contains exactly 1 watchdog entry.
**Explicitly NOT included:** Does not promise anything about what the watchdog does
once it has started running on the schedule.
**Human dependencies:**
- None required at runtime — INTENDED
PLAN
  _expect_plan "D3-restatement-in-plan" 1 "$tmp/restate.md"

  cat > "$tmp/defect.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** After a usage limit resets, my work continues
without me touching anything.
**Observation:** The session resumes on its own and the transcript shows activity
timestamped after the reset.
**Deterministic pass/fail:** Resumption happened within 5 minutes of the reset with
zero human actions recorded in between.
**Explicitly NOT included:** Does not promise resumption after a crash, only after a
usage-limit reset.
**Human dependencies:**
- The operator must arm the marker before each session — DEFECT
PLAN
  _expect_plan "D4-human-dependency-DEFECT" 1 "$tmp/defect.md"

  cat > "$tmp/nondet.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** After a usage limit resets, my work continues
without me touching anything.
**Observation:** The session resumes on its own and the transcript shows activity
timestamped after the reset.
**Deterministic pass/fail:** A reviewer reads the transcript and forms a judgement on
whether the resumption looked healthy enough to count as working.
**Explicitly NOT included:** Does not promise resumption after a crash, only after a
usage-limit reset.
**Human dependencies:**
- None required at runtime — INTENDED
PLAN
  _expect_plan "D5-nondeterministic-rule" 1 "$tmp/nondet.md"

  # D7/D8 — M8 regressions (harness-reviewer 2026-07-30).
  # D7: a NEGATED judgement word is a declaration of determinism, not judgement
  # vocabulary. The plan template literally instructs "the rule with no judgement
  # call", so the unconditional veto rejected the phrasing it was teaching.
  cat > "$tmp/negated.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** After a usage limit resets, my work continues
without me touching anything.
**Observation:** The session resumes on its own and the transcript shows activity
timestamped after the reset, visible to anyone without reading code.
**Deterministic pass/fail:** Resumption happened within 5 minutes of the reset, with
no judgement call required from whoever checks it.
**Explicitly NOT included:** Does not promise resumption after a crash, only after a
usage-limit reset of the kind described above.
**Human dependencies:**
- None required at runtime — INTENDED
PLAN
  _expect_plan "D7-negated-judgement-word-passes" 0 "$tmp/negated.md"

  # D8: a digit-free BINARY predicate is deterministic. Absence of a threshold is
  # absence of evidence, not evidence of non-determinism -> UNDECIDABLE, not REJECT.
  cat > "$tmp/binary.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** After a usage limit resets, my work continues
without me touching anything.
**Observation:** The session resumes on its own and the transcript shows activity
timestamped after the reset, visible to anyone without reading code.
**Deterministic pass/fail:** The commit is refused and the plan file is left
unchanged on disk.
**Explicitly NOT included:** Does not promise resumption after a crash, only after a
usage-limit reset of the kind described above.
**Human dependencies:**
- None required at runtime — INTENDED
PLAN
  _expect_plan "D8-digit-free-binary-rule-undecidable-not-reject" 2 "$tmp/binary.md"

  cat > "$tmp/unfilled.md" <<'PLAN'
# Plan: seeded
Status: ACTIVE

## Intended Functionality

**Outcome (operator's terms):** [describe what becomes true for the operator]
**Observation:** [how anyone tells, without reading code]
**Deterministic pass/fail:** [the rule with no judgement call]
**Explicitly NOT included:** [what this does not promise]
**Human dependencies:**
- [each one marked INTENDED or DEFECT]
PLAN
  _expect_plan "D6-unfilled-template" 1 "$tmp/unfilled.md"

  echo "" >&2
  echo "self-test summary: $passed passed, $failed failed (of $((passed+failed)) scenarios)" >&2
  if [[ "$failed" -eq 0 ]]; then
    echo "self-test: OK" >&2
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
if_usage() {
  cat <<USAGE
$SELF_NAME — anti-restatement checker for Intended-Functionality statements

  $SELF_NAME <plan-file>            check a plan's '## Intended Functionality'
  $SELF_NAME --outcome "<text>"     check one outcome sentence
  $SELF_NAME --corpus <dir> [dir…]  measure against existing plans' Goal sentences
                                    (IF_CORPUS_DETAIL=1 for per-plan rows)
  $SELF_NAME --self-test
  $SELF_NAME --help

Exit: 0 ACCEPT · 1 REJECT · 2 UNDECIDABLE (route to the operator) · 3 usage
USAGE
}

case "${1:---help}" in
  --self-test) if_self_test; exit $? ;;
  --help|-h)   if_usage; exit 0 ;;
  --outcome)   [[ $# -ge 2 ]] || { if_usage >&2; exit 3; }
               if_check_outcome "$2"; exit $? ;;
  --corpus)    shift; [[ $# -ge 1 ]] || { if_usage >&2; exit 3; }
               if_corpus "$@"; exit 0 ;;
  -*)          if_usage >&2; exit 3 ;;
  *)           if_check_plan "$1"; exit $? ;;
esac
