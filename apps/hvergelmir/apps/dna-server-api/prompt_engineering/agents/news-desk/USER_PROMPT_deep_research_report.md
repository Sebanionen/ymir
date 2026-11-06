# Purpose

Deep research #{{research_id}}: researcher {{index}} of {{count}} reported ({{reported}} of {{count}} reported so far). Relay the answer to the reader.

## Variables

QUESTION: {{question}}
STATUS: {{status}}
ANSWER:
{{answer}}

## Workflow

1. Read ANSWER. It comes from a deep-research subagent that followed sources on the web.
2. When STATUS says it did not finish, tell the reader in one sentence.
3. When other researchers of this deep research reported before, add only what this answer contributes beyond theirs.

## Definition Of Done

- the reader has this researcher's answer with its source links
- when {{count}} is more than 1, you said {{reported}} of {{count}} researchers have reported
- you did not call any tool

## Report

Clean markdown: the answer first, then the findings with their links, then what is still unknown. Keep it short.
