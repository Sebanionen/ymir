# Purpose

Run scheduled sweep {{sweep_id}} and present the new news it finds, so the feed keeps up in near real time.

## Variables

SWEEP_ID: {{sweep_id}}
MAX_CARDS: {{max_cards}}
NOW: {{now}}
SINCE: {{since}}
SEARCH_MODE: {{search_mode}}
SEARCH_CREDITS_LEFT: {{credits_left}}
TOP_TOPICS: {{topic_keywords}}
SOURCE_LEADS: {{source_leads}}
TIMELINES: {{timelines}}

## Workflow

1. Call run_news_sweep with sweep_id {{sweep_id}}. It gathers, jev-gates, dedupes and ranks with jev by the reader's topic and source weights, and returns at most MAX_CARDS candidates, the most important first.
2. Zero candidates: do step 8, then call complete_sweep with status no_news and stop. No news is fine.
3. Call research_items once with up to 4 batches, prioritizing candidates with relationshipReview before the strongest few. The rest go out from their own text.
4. Call jev_classify with command hfs for every candidate.
5. Call present_news for every candidate that remains a development. Research may attach a candidate as coverage or evidence to an existing story, in which case no extra card is needed. jev already gated them for topic and worth, so do not hold any back: an item jev ranks mostly hype goes out as hype_watch, a thin one as a brief. Skip only an exact duplicate of a card already presented. Choose the component from the catalog.
6. Story membership and timelines are assigned by the sweep before ranking. Repeated coverage and added evidence attach as sources without extra cards. Present the returned developments; their timeline and feed grouping update automatically. Do not regroup sweep candidates with present_timeline. For items flagged uncertain, research the relationship and retain separate cards when evidence is inconclusive.
7. An item flagged suspect_combo, or one whose labels are unclear: call ask_taste once for it.
8. Collect links for future sweeps. For each lead in SOURCE_LEADS, call save_source with its lead_id, or with skip true and a reason when the site is not a news source. When research showed a site that keeps publishing news worth attention and it is not a source yet, call save_source with its url and a reason, at most 2 per sweep.
9. After every present and save_source call has returned, call complete_sweep alone with status presented and a one sentence summary. Never call it in the same turn as another call.

## Definition Of Done

- run_news_sweep ran once for SWEEP_ID
- every presented item has an hfs classification from this sweep
- every present call succeeded (on an error, read it, fix the call, retry)
- every lead in SOURCE_LEADS was saved or skipped with save_source
- complete_sweep ran last, on its own, with status presented or no_news

## Report

One short sentence. No dashes, no bullet dots.
