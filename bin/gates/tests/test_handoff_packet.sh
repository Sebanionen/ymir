#!/usr/bin/env bash
# test_handoff_packet.sh — proves the packet door reads the schema's packet and refuses a false one.
#
# The refusals that carry plan 203, all tested here because they ARE the design (§15.3):
#   · a head that MOVED is refused, in §14.1's own words
#   · a changed list that understates the diff is refused, and the omitted path is named
#   · a gate tail that is a claim ("all pass") is refused
#   · a `review[]` block written by a smith is refused — the verdict is the reviewer's
#   · `floor partial` is refused — a partial floor is a refusal waiting to happen
#   · a base with no sha, and a missing packet, are refusals rather than silent passes
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="$here/../../forge/handoff-packet.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
out=""; rc=0
run() { out="$("$@" 2>&1)"; rc=$?; }

echo "test_handoff_packet"
[ -x "$tool" ] || { bad "the tool is not executable: $tool"; exit 1; }

# a throwaway repository whose rules floor LOADS (one source, one yaml) — a partial floor is a
# refusal, so a test that wants a sound packet must give the floor something to read.
repo="$tmp/repo"; mkdir -p "$repo"; cd "$repo" || exit 1
git init -q .; git config user.email t@ymir; git config user.name t
printf 'one\n' > a.txt; printf 'rules:\n  - a.txt\n' > .review-rules.yaml
git add -A; git commit -qm base; base="$(git rev-parse HEAD)"
git checkout -q -b work; printf 'two\n' > b.txt; git add b.txt; git commit -qm "add b"
head="$(git rev-parse HEAD)"

write_ok() { run python3 "$tool" write ok --task t --plan p --branch work --base "$base" --head "$head" \
  --gate "site|bash bin/gates/guards.sh|0|guards.sh: 27 PASS, 0 FAIL" \
  --test "bash bin/gates/tests/test_x.sh|0|7 passed, 0 failed" \
  --claim "the door reads the schema|unverified|schemas/handoff-packet.toon" \
  --repo "$repo" --packet "$tmp/ok.packet"; }

# 1 · a truthful packet is written, in the schema's shape
write_ok
[ "$rc" = 0 ] && ok "a packet with evidence is written" || bad "write failed: $out"
grep -q '^packet\[1\]{task,plan,branch,base,head,author,written_at,ruleset,floor}:' "$tmp/ok.packet" \
  && ok "the packet row matches schemas/handoff-packet.toon" || bad "the packet row is not the schema's"
grep -q '^changed\[[0-9]*\]{path,added,removed,why}:' "$tmp/ok.packet" \
  && ok "changed[] carries path, added, removed, why" || bad "changed[] is not the schema's block"

# 2 · and it reads as sound
run python3 "$tool" check ok --repo "$repo" --packet "$tmp/ok.packet"
[ "$rc" = 0 ] && ok "a true packet reads as sound" || bad "a true packet was refused: $out"

# 3 · the sha check (§14.1) — a moved head is refused, and says why
run python3 "$tool" check ok --repo "$repo" --packet "$tmp/ok.packet" --fetched "$base"
[ "$rc" = 1 ] && ok "a moved head is refused" || bad "a moved head was accepted (rc=$rc)"
case "$out" in *"may not vouch for code that moved"*) ok "the refusal quotes §14.1's rule" ;;
  *) bad "the refusal did not name the moved-head rule" ;; esac

# 4 · the changed list is checked, not believed
grep -v '"b.txt"' "$tmp/ok.packet" > "$tmp/lying.packet"
run python3 "$tool" check ok --repo "$repo" --packet "$tmp/lying.packet"
[ "$rc" = 1 ] && ok "an understated changed list is refused" || bad "a lying changed list passed"
case "$out" in *understated*) ok "the refusal says understated, and names the path" ;;
  *) bad "the refusal did not name the omission" ;; esac

# 5 · a gate tail that is a claim, not evidence
run python3 "$tool" write claim --task t --plan p --branch work --base "$base" --head "$head" \
  --gate "site|bash bin/gates/guards.sh|0|all pass" \
  --test "bash t.sh|0|7 passed" --repo "$repo" --packet "$tmp/claim.packet"
[ "$rc" = 1 ] && ok '"all pass" is refused as evidence' || bad '"all pass" was accepted as evidence'

# 6 · the reviewer's block may not be written by the smith
{ cat "$tmp/ok.packet"; printf '\nreview[1]{reviewer,at,ruleset,gates,tests,verdict,pr,merge,commit}:\n  "me","now","x","y","z","pass","1","2","3"\n'; } > "$tmp/withreview.packet"
run python3 "$tool" check ok --repo "$repo" --packet "$tmp/withreview.packet"
[ "$rc" = 1 ] && ok "a smith-written review[] is refused" || bad "a smith-written review[] was accepted"
case "$out" in *"reviewer's block"*) ok "the refusal says whose block it is" ;;
  *) bad "the refusal did not say whose block it is" ;; esac

# 7 · a partial floor is a refusal waiting to happen
norepo="$tmp/norepo"; mkdir -p "$norepo"; cd "$norepo" || exit 1
git init -q .; git config user.email t@ymir; git config user.name t
printf 'one\n' > a.txt; git add a.txt; git commit -qm base; pbase="$(git rev-parse HEAD)"
printf 'two\n' > b.txt; git add b.txt; git commit -qm head; phead="$(git rev-parse HEAD)"
run python3 "$tool" write partial --task t --plan p --base "$pbase" --head "$phead" \
  --gate "site|bash g.sh|0|g.sh: 1 PASS" --test "bash t.sh|0|1 passed" \
  --repo "$norepo" --packet "$tmp/partial.packet"
grep -q 'partial' "$tmp/partial.packet" && ok "a floor with nothing to read is recorded as partial" \
  || bad "the floor was not recorded as partial"
run python3 "$tool" check partial --repo "$norepo" --packet "$tmp/partial.packet"
[ "$rc" = 1 ] && ok "floor partial is refused at check" || bad "a partial floor was accepted"
case "$out" in *"refusal waiting to happen"*) ok "the refusal says what a partial floor means" ;;
  *) bad "the refusal did not name the partial floor" ;; esac

# 8 · a base with no sha — nobody could verify the diff
sed 's|^  "t","p","work","[0-9a-f]*"|  "t","p","work","origin/main"|' "$tmp/ok.packet" > "$tmp/nobase.packet"
run python3 "$tool" check ok --repo "$repo" --packet "$tmp/nobase.packet"
[ "$rc" = 1 ] && ok "a base with no sha is refused" || bad "a base with no sha was accepted"

# 9 · a missing packet is a refusal, never an empty pass
run python3 "$tool" check ghost --repo "$repo" --packet "$tmp/nope.packet"
[ "$rc" = 1 ] && ok "a missing packet is refused" || bad "a missing packet was accepted"

printf 'test_handoff_packet: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
