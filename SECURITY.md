# Security

## Reporting

Open an issue at [github.com/Rishi4792/compass/issues](https://github.com/Rishi4792/compass/issues).
If the report itself would expose something, say so in the issue without the detail and we will find
another route.

---

## Disclosures

Things this project got wrong and has published rather than quietly fixed. They are here because a
tool that checks other people's repositories for leaked secrets has no standing to be discreet about
its own.

### Assistant session links in commit messages — 2026-07-21 to 2026-09-03

**What happened.** Commit messages in this repository ended with a link to the assistant session that
produced them. **150 commits carry one, across 8 distinct session identifiers**, and **132 of those
are on public `main`**, going back to 21 July 2026.

**What the identifier is.** An opaque identifier for a conversation. It is not a credential, not an
API key, and not an access token: pasting one into a browser does not open anything. What it does do
is confirm that a particular conversation existed and tie a set of commits to it — which is more
metadata about how this repository was built than anyone chose to publish deliberately.

**What was done.**

- **Stopped.** No commit authored on or after **2026-09-05** carries one.
- **Made mechanical.** `plugins/compass/scripts/session-trailer-check.sh` fails on any commit written
  on or after that date that carries a session link, and it is a step in `RELEASING.md`. A policy
  that lives only in somebody's memory comes back the first time anyone is in a hurry.
- **Counted, not estimated.** The figures above come from walking the history, not from recollection.

**What was NOT done, and why.** The history was not rewritten. 132 of the 150 are already on public
`main` and a published git history is published — rewriting cannot recall what has been fetched,
forked or cached. That left 18 commits on an unmerged branch, and rewriting only those would have
changed every commit identifier this release pinned its published measurements to, in exchange for
removing 18 links out of 150. The honest trade was to leave the history intact and say what is in it.

### An absolute home path shipped inside the plugin — 14 tagged releases

**What happened.** A path containing the author's operating-system username was committed inside the
published plugin and shipped in **14 tagged releases** before anyone noticed.

**What was done.** Removed, and then made mechanical rather than remembered:
`compass.sh secret-scan --tracked` scans everything git tracks — not just the plugin directory,
because `README.md`, `CHANGELOG.md` and `docs/` are equally public — and `leak-scan-check.sh` runs it
as part of the release. The first version of that check reported the tree clean while a reviewer's
planted home path sat in three tracked files, so it is now asserted by behaviour on a throwaway
repository rather than by searching the check for a word.

**Related.** The scanner's rules are graded against a corpus kept in the repository
(`plugins/compass/scripts/fixtures/secrets/`): lines that must be refused, and ordinary lines that
must not. It is a fixture and not a private list because an earlier version was written *after* the
rules were tuned, scored itself perfectly, and an independent reviewer then measured a 49% false
alarm rate on real code.

---

## A note on the checks themselves

Two mechanisms here can let something through, and both are deliberate, bounded and loud:

- **`fixtures/secrets/cleared-history.txt`** clears a single finding in committed history, named by
  path and by the SHA-256 of the exact line. One character different and the finding stands. Every
  use is printed in the summary. It exists because a finding in a patch cannot be cleared by editing
  a file — correct for a real secret, and therefore permanent for a false alarm.
- **`plugins/compass/scripts/perf-exception.txt`** lets one named release ship over the speed
  ceiling. It expires when the version changes, it names the figure it covers, and it requires a
  signer.

Neither can be used silently, and neither survives the release it was written for.
