# rename-marker

**How it was found.** Contract §9 cheat 1. Three published figures — 340, 340, 717 — were all
produced by searching rendered pages for a marker string. This cheat is one `sed` away from taking
any of them to zero without fixing anything.

**Reproduce.**
```
cp -R <repo> /tmp/cheat && bash apply.sh /tmp/cheat
bash /tmp/cheat/plugins/compass/scripts/reachable-argument-check.sh /tmp/cheat --corpus <tracked-corpus>
```

**What must happen.** The unreachable figure must NOT fall. The check reads no marker, so renaming
one is invisible to it.
