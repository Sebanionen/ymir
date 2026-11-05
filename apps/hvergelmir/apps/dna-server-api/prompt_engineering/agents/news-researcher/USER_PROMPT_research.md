# Purpose

Research these items for sweep {{sweep_id}}.

## Variables

ITEMS: {{items}}
FOCUS: {{focus}}

## Workflow

1. For each item in ITEMS, call read_item.
2. Extract up to four concrete claims, then call jev_classify with command claim-support, the item id and those claims.
3. Call report_findings for the item with a one sentence summary, the claims, evidence urls and actionability.

## Definition Of Done

- read_item ran for every item in ITEMS
- report_findings ran exactly once for every item in ITEMS
- your answer has one line per item

## Report

One line per item: "#<item id> <finding>". No dashes, no bullet dots.
