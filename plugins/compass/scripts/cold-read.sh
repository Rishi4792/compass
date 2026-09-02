#!/usr/bin/env bash
# v0.32.0 S8 — the COLD-READ harness.
#
# WHY THE HARNESS PICKS THE ROWS, AND NOT THE READERS. A cold reader told "open the page and see if
# you can finish a few rows" will pick rows that read easily — and a row the page did not shorten
# renders no control at all, so it is trivially finishable. Two lazy readers choosing freely would
# pass a page on which nothing is reachable. So the candidates come from the rows the page ACTUALLY
# SHORTENED, which is a fact about the page rather than a preference of the reader.
#
# WHAT THIS SCRIPT IS AND IS NOT. It is the harness: it picks the rows, writes one task packet per
# reader, and can grade a CONTROL page mechanically. It is NOT the readers — those are LLM
# subagents and they run OUT OF BAND, in minutes, on the split budget contract §9 states. Nothing
# here claims to have read anything.
#
# Usage:
#   cold-read.sh <build-dir> [--view review] [--emit <dir>]   pick rows, write task packets
#   cold-read.sh --self-check [<repo-root>]                   the control pair, both directions
# Exit: 0 pass · 1 fail · 2 usage.
set -uo pipefail

_root_of() { cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd; }
ROOT="$(_root_of)"
GEN="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"

# The rows a page SHORTENED are the ones carrying a disclosure control. That is the population; a
# reader is never offered a row the page rendered whole.
_candidates() { # <page.html> -> one candidate per line: "<shown half> :: <remainder length>"
  node -e '
    const fs = require("fs");
    const html = fs.readFileSync(process.argv[1], "utf8");
    const strip = (x) => x.replace(/<[^>]+>/g, " ").replace(/&nbsp;|&#160;/g, " ")
      .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/\s+/g, " ").trim();
    const out = [];
    for (const m of html.matchAll(/<details class="rest"[\s\S]*?<\/details>/g)) {
      const body = strip(m[0].replace(/<summary[\s\S]*?<\/summary>/, " "));
      if (body.length < 12) continue;                 // too short to be a real remainder
      const before = strip(html.slice(Math.max(0, m.index - 400), m.index));
      const shown = before.slice(-90);
      if (shown.length < 12) continue;                // no visible row to continue
      out.push(shown + " :: " + body.length);
    }
    process.stdout.write(out.join("\n"));
  ' "$1" 2>/dev/null
}

if [ "${1:-}" = "--self-check" ]; then
  R="${2:-$ROOT}"; R="$(cd "$R" 2>/dev/null && pwd)" || { echo "cold-read: cannot resolve root"; exit 2; }
  GEN="$R/plugins/compass/skills/compass-visual/gen.mjs"
  [ -f "$GEN" ] || { echo "cold-read: no generator at $GEN"; exit 2; }
  command -v node >/dev/null 2>&1 || { echo "cold-read: node is not on PATH, so nothing was exercised. An ERR, never a pass."; exit 2; }
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/b"
  # The CONTRACT has to be long, not just the ledger: on the review page the shortened rows are the
  # fact rows built from contract fields, and a first version of this control wrote a short contract
  # and a long ledger and produced ZERO controls — a harness self-check that could not fail.
  { printf '# Contract — cold · v1\n\nfacets: library\n\n## Goal & scope\n'
    printf '**Goal:** '
    i=0; while [ "$i" -lt 12 ]; do i=$((i+1))
      printf 'clause %s of a deliberately long goal sentence, written well past the width any page will render so the generator must shorten it and leave a control behind carrying the remainder; ' "$i"
    done
    printf '\n\n### NOW\n'
    i=0; while [ "$i" -lt 10 ]; do i=$((i+1)); printf '%s. scope item %s, also written long enough that the six-item cap and the field width both bite on it and the rest has to go somewhere a reader can reach\n' "$i" "$i"; done
    printf '\n## Acceptance & INVARIANTs\n'
    i=0; while [ "$i" -lt 8 ]; do i=$((i+1))
      printf -- '- **INV-COLD-%s:** a deliberately long invariant statement, number %s, whose assert recipe runs past the width the page renders. → *assert:* the harness finds candidates and each one carries its remainder where a reader can open it.\n' "$i" "$i"
    done
    printf '\n## Done\nA long done-means paragraph that also exceeds the width, so the fact row built from it is shortened too and contributes another candidate row for the readers to be offered.\n'
  } > "$T/b/contract.md"
  { printf '| Issue ID | Sev | Status | Failure mode |\n|---|---|---|---|\n'
    i=0; while [ "$i" -lt 6 ]; do i=$((i+1))
      printf '| C-%s | Maj | OPEN | a deliberately long failure mode, number %s, written past the width any page will render so the generator has to shorten it and leave a control behind carrying the rest of the sentence |\n' "$i" "$i"
    done; } > "$T/b/review-ledger.md"

  # ── THE READABLE CONTROL ──────────────────────────────────────────────────────────────────────
  # THE BRIEF, not the review. Measured while building this: for a control build the review view
  # renders 0 disclosure controls and the brief renders 2 — the review page's controls come from
  # long LEDGER text, the brief's from the contract's own fields. A self-check pointed at a view
  # that shortens nothing cannot fail, whatever the generator does.
  node "$GEN" "$T/b" brief --out "$T/ok.html" >/dev/null 2>&1
  [ -s "$T/ok.html" ] || { echo "cold-read: the readable control page did not render — UNMEASURED, not a pass."; exit 2; }
  n_ok="$(_candidates "$T/ok.html" | grep -c . || true)"
  # NON-EMPTY OR NOTHING. A harness that finds no candidates would "pass" every page ever written.
  if [ "${n_ok:-0}" -lt 2 ]; then
    echo "cold-read: self-check FAILED — the readable control offered only ${n_ok:-0} candidate rows. A harness with no candidates passes every page, which is the failure this check exists to stop."
    exit 1
  fi

  # ── THE UNREADABLE CONTROL ────────────────────────────────────────────────────────────────────
  # The same build, rendered by a generator whose disclosure control emits nothing. Every row is
  # still shortened; none is finishable. This is the page two freely-choosing readers would pass.
  # THE TREE LAYOUT MUST SURVIVE THE COPY. gen.mjs imports `../../scripts/reader-copy.mjs`, so a
  # flat copy of the skill directory cannot even load — the first version of this control silently
  # produced no page and the check reported UNMEASURED instead of grading anything.
  mkdir -p "$T/gen/plugins/compass/skills" "$T/gen/plugins/compass/scripts"
  cp -R "$R/plugins/compass/skills/compass-visual" "$T/gen/plugins/compass/skills/" 2>/dev/null
  cp -R "$R/plugins/compass/scripts/." "$T/gen/plugins/compass/scripts/" 2>/dev/null
  python3 - "$T/gen/plugins/compass/skills/compass-visual/gen.mjs" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function disclose(rest, label = 'Show the rest') {
  if (!rest) return '';"""
assert s.count(o)==1, "disclose anchor"
io.open(p,'w',encoding='utf-8').write(s.replace(o, o + "\n  return '';"))
PYEOF
  node "$T/gen/plugins/compass/skills/compass-visual/gen.mjs" "$T/b" brief --out "$T/bad.html" >/dev/null 2>&1
  [ -s "$T/bad.html" ] || { echo "cold-read: the unreadable control page did not render — UNMEASURED, not a pass."; exit 2; }
  n_bad="$(_candidates "$T/bad.html" | grep -c . || true)"
  if [ "${n_bad:-0}" -ne 0 ]; then
    echo "cold-read: self-check FAILED — the KNOWN-UNREADABLE control still offered ${n_bad} candidate rows with reachable remainders. The harness cannot tell a finishable page from an unfinishable one."
    exit 1
  fi
  echo "cold-read: self-check PASSED — the readable control offers $n_ok candidate rows and the known-unreadable one offers 0."
  echo "  What this proves: the harness picks from rows the page SHORTENED, and a page where nothing"
  echo "  is reachable yields no candidates at all rather than easy ones. What it does NOT prove is"
  echo "  that any human or model read anything — the readers run out of band."
  exit 0
fi

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "cold-read: usage: cold-read.sh <build-dir> [--view review] [--emit <dir>] | --self-check"; exit 2; }
shift
VIEW=brief; EMIT=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --view) [ $# -ge 2 ] || { echo "cold-read: --view needs a value" >&2; exit 2; }
            VIEW="${2:-review}"; shift 2 ;;
    --emit) [ $# -ge 2 ] || { echo "cold-read: --emit needs a value" >&2; exit 2; }
            EMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
command -v node >/dev/null 2>&1 || { echo "cold-read: node is not on PATH."; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
node "$GEN" "$DIR" "$VIEW" --out "$T/p.html" >/dev/null 2>&1
[ -s "$T/p.html" ] || { echo "cold-read: '$DIR' did not render a $VIEW page — nothing to read."; exit 2; }
cands="$(_candidates "$T/p.html")"
n="$(printf '%s' "$cands" | grep -c . || true)"
if [ "${n:-0}" -eq 0 ]; then
  echo "cold-read: '$(basename "$DIR")' shortened NO rows on its $VIEW page, so there is nothing to cold-read. That is not a pass — it means this page cannot exercise the question."
  exit 1
fi
echo "cold-read: $(basename "$DIR") · $VIEW · $n shortened row(s) are candidates."
if [ -n "$EMIT" ]; then
  mkdir -p "$EMIT" 2>/dev/null
  cp "$T/p.html" "$EMIT/page.html" 2>/dev/null
  # TWO readers, and a grader who never sees the contract. The packets are deliberately identical
  # so the two readings are independent rather than sequential.
  _i=0
  for _r in reader-1 reader-2; do
    _i=$((_i+1))
    { printf '# Cold read — %s\n\n' "$_r"
      printf 'You are reading `page.html` in this directory. You have NOT seen the contract and must not look for it.\n\n'
      printf 'For each row below: open the page, find that row, and answer ONE question — CAN YOU FINISH THE SENTENCE?\n'
      printf 'Answer FINISHED or CANNOT-FINISH per row, and say where you found the rest.\n\n'
      printf 'These rows were chosen because the page SHORTENED them. You may not substitute other rows.\n\n'
      printf '%s\n' "$cands" | sed 's/^/- /'
    } > "$EMIT/$_r.md"
  done
  { printf '# Cold-read grading\n\nYou grade two readings of `page.html`. You have NOT seen the contract and must not look for it.\n\n'
    printf 'A row PASSES only if BOTH readers say FINISHED and both name where the rest was.\n'
    printf 'Disagreement is a FAIL for that row: if two readers cannot agree whether a sentence finishes, a reader cannot finish it.\n\n'
    printf 'Rows under test (%s):\n\n' "$n"
    printf '%s\n' "$cands" | sed 's/^/- /'
  } > "$EMIT/grader.md"
  echo "cold-read: wrote page.html, reader-1.md, reader-2.md and grader.md to $EMIT"
  echo "  The readers and grader run OUT OF BAND, in minutes, on the split budget §9 states."
fi
exit 0
