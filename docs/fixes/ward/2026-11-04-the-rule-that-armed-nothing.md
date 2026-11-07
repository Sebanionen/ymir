# The rule that armed nothing

**Date:** 2026-11-04 · **Component:** ward · **Door:** `bin/ward/garmr.sh` (`rules_text`, `arm_senses`)

## What was wrong

`audit-rules.service` has failed at every boot since **2026-10-22**, and the failure was quiet
enough to survive eleven days: the journal says `Failed to start Load Audit Rules`, the unit is
red, and nothing else notices.

```
Nov 04 17:50:50 heimdall augenrules[1000]: Error sending add rule data request (No such file or directory)
Nov 04 17:50:50 heimdall augenrules[1000]: There was an error in line 23 of /etc/audit/audit.rules
```

Line 23 of the installed ruleset is:

```
-w /etc/cron.d -p wa -k ymir-persist
```

and this seat has **no `/etc/cron.d`** — it is a systemd-only box. auditd refuses the *entire*
ruleset when a `-w` names a path that is not there, so the house has been running with **no
watched paths at all**: no identity watches on `passwd`/`shadow`/`sudoers`, no persistence
watches on the unit directories, no sensitive-path watches on the hoard. The ward was green by
being absent, and `auditd` spent about **3% of a core policing an empty ruleset**.

Two more watches named paths this seat also lacks — `/etc/crontab` and `/var/spool/cron` — and
one named `$YMIR_HOME/.ssh/authorized_keys`, which does not exist: the fleet's keys live at
`$HOME/.ssh/authorized_keys`. So the one watch that was meant to witness a key being added was
pointed at a directory the hoard never had.

## The second fault, found while reading it

The rules block is a **heredoc whose terminator was unquoted** (`<<RULES`). Its own explanatory
comment carries backticks — `a1`, `a2`, `pidfd_send_signal`, `rt_*sigqueueinfo` — and unquoted
those are command substitution, so every install printed

```
bin/ward/garmr.sh: line 72: a1: command not found
bin/ward/garmr.sh: line 72: pidfd_send_signal: command not found
```

and blanked the comment that explains why those rules exist. A heredoc that is quoted keeps its
text; the one watch that needed `$home` is now emitted after the block instead.

## The mend

- The heredoc is quoted (`<<'RULES'`), so no rule file can execute its own commentary.
- Every `-w` is guarded by the path's own existence — the shape the `ymir-sensitive` and
  autostart watches already used. A ruleset whose watches all exist cannot fail this way, on any
  seat: cron directories, `sudoers.d`, `authorized_keys` and the unit directories differ between
  machines, and a rule generated for a path a machine does not have is a rule that disarms it.
- `$HOME/.ssh/authorized_keys` is watched — where the keys actually are — and the hoard's own
  copy too, when a seat has one.

## Proof, without root

`rules_text` was extracted and run directly, so the generated set can be read before it is armed:

```
$ bash -c 'eval "$(sed -n "/^rules_text()/,/^}$/p" bin/ward/garmr.sh)"; rules_text <hoard>' | grep -E '^-w'
-w /etc/passwd                                     EXISTS
-w /etc/shadow                                     EXISTS
-w /etc/group                                      EXISTS
-w /etc/sudoers                                    EXISTS
-w /etc/sudoers.d                                  EXISTS
-w /home/heimdall/.ssh/authorized_keys              EXISTS
-w /etc/systemd/system                             EXISTS
-w /etc/systemd/user                               EXISTS
-w <hoard>/hodd/evidence                            EXISTS
-w <hoard>/hodd/life/meetings                       EXISTS
-w <hoard>/hodd/secrets                             EXISTS
```

`garmr.sh install --dry-run` now reports **0** "command not found". Every watched path exists.

## Still owed

Arming it needs root, which this operator session does not have. The single command is:

```
sudo bash bin/ward/garmr.sh install
```

run from a tree carrying this change. Until it runs, `audit-rules.service` stays red — correctly
red now, because the ruleset it will load is one that can actually load.
