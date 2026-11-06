// Keywords per section, feedback on cards, and the taste questions the agent asks.
import type { HfsCategory, Keyword, TasteQuestion } from "@dna/sdk";
import { bind, bool, type Db, nowIso, num, parse, str } from "../db.ts";

export type KeywordKind = Keyword["kind"];

const toKeyword = (r: any): Keyword => ({
  id: r.id,
  kind: r.kind,
  term: r.term,
  weight: r.weight,
  source: r.source,
  enabled: bool(r.enabled),
  lastSearchedAt: str(r.last_searched_at),
});

const toQuestion = (r: any): TasteQuestion => ({
  id: r.id,
  cardId: num(r.card_id),
  itemId: num(r.item_id),
  question: r.question,
  status: r.status,
  answerLabels: parse(r.answer_labels_json, []),
  createdAt: r.created_at,
  answeredAt: str(r.answered_at),
});

export class TasteRepo {
  constructor(private readonly db: Db) {}

  seed(groups: Record<KeywordKind, string[]>): number {
    const insert = this.db.prepare(
      "INSERT OR IGNORE INTO keywords (kind, term, source, created_at, updated_at) VALUES (?, ?, 'seed', ?, ?)",
    );
    let added = 0;
    const now = nowIso();
    for (const [kind, terms] of Object.entries(groups))
      for (const term of terms) added += Number(insert.run(kind, term, now, now).changes);
    return added;
  }

  keywords(kind?: KeywordKind, enabledOnly = false): Keyword[] {
    const where = [kind ? "kind = :kind" : "", enabledOnly ? "enabled = 1" : ""]
      .filter(Boolean)
      .join(" AND ");
    return (
      this.db
        .prepare(
          `SELECT * FROM keywords ${where ? `WHERE ${where}` : ""} ORDER BY kind, weight DESC, term`,
        )
        .all(bind({ ...(kind ? { kind } : {}) })) as any[]
    ).map(toKeyword);
  }

  keyword(id: number): Keyword | undefined {
    const r = this.db.prepare("SELECT * FROM keywords WHERE id = ?").get(id);
    return r ? toKeyword(r) : undefined;
  }

  findKeyword(kind: KeywordKind, term: string): Keyword | undefined {
    const r = this.db
      .prepare("SELECT * FROM keywords WHERE kind = ? AND lower(term) = lower(?)")
      .get(kind, term);
    return r ? toKeyword(r) : undefined;
  }

  addKeyword(kind: KeywordKind, term: string, weight = 1): Keyword {
    const now = nowIso();
    this.db
      .prepare(
        "INSERT INTO keywords (kind, term, weight, source, created_at, updated_at) VALUES (?, ?, ?, 'user', ?, ?) ON CONFLICT (kind, term) DO UPDATE SET enabled = 1, updated_at = excluded.updated_at",
      )
      .run(kind, term.trim(), weight, now, now);
    return this.findKeyword(kind, term.trim())!;
  }

  updateKeyword(
    id: number,
    patch: { weight?: number; enabled?: boolean; term?: string },
  ): Keyword | undefined {
    const k = this.keyword(id);
    if (!k) return undefined;
    this.db
      .prepare(
        "UPDATE keywords SET weight = :weight, enabled = :enabled, term = :term, updated_at = :now WHERE id = :id",
      )
      .run(
        bind({
          id,
          weight: clamp(patch.weight ?? k.weight),
          enabled: patch.enabled ?? k.enabled,
          term: patch.term?.trim() || k.term,
          now: nowIso(),
        }),
      );
    return this.keyword(id);
  }

  removeKeyword(id: number): boolean {
    return Number(this.db.prepare("DELETE FROM keywords WHERE id = ?").run(id).changes) > 0;
  }

  /** Add delta to a weight, clamped to 0.1..2.0. */
  nudge(id: number, delta: number): Keyword | undefined {
    const k = this.keyword(id);
    if (!k) return undefined;
    return this.updateKeyword(id, { weight: Math.round((k.weight + delta) * 100) / 100 });
  }

  markSearched(ids: number[]): void {
    const now = nowIso();
    const stmt = this.db.prepare("UPDATE keywords SET last_searched_at = ? WHERE id = ?");
    for (const id of ids) stmt.run(now, id);
  }

  addFeedback(
    cardId: number,
    input: { signal?: "more" | "less"; labels?: HfsCategory[]; note?: string },
  ): void {
    this.db
      .prepare(
        "INSERT INTO feedback (card_id, signal, labels_json, note, created_at) VALUES (:card_id, :signal, :labels, :note, :now)",
      )
      .run(
        bind({
          card_id: cardId,
          signal: input.signal,
          labels: input.labels,
          note: input.note,
          now: nowIso(),
        }),
      );
  }

  /** Recent feedback joined to card titles, newest first. */
  recentFeedback(limit = 20): {
    cardId: number;
    title: string;
    signal?: "more" | "less";
    labels: HfsCategory[];
    at: string;
  }[] {
    return (
      this.db
        .prepare(
          `SELECT f.card_id, f.signal, f.labels_json, f.created_at, COALESCE(json_extract(c.props_json, '$.title'), i.title, '') AS title
           FROM feedback f JOIN cards c ON c.id = f.card_id LEFT JOIN items i ON i.id = c.item_id
           ORDER BY f.id DESC LIMIT ?`,
        )
        .all(limit) as any[]
    ).map((r) => ({
      cardId: r.card_id,
      title: r.title,
      signal: r.signal ?? undefined,
      labels: parse(r.labels_json, []),
      at: r.created_at,
    }));
  }

  // Taste questions

  askQuestion(input: {
    cardId?: number;
    itemId?: number;
    question: string;
    toolCallId: string;
    conversationId?: number;
  }): { question: TasteQuestion; created: boolean } {
    const existing = this.db
      .prepare("SELECT * FROM taste_questions WHERE tool_call_id = ?")
      .get(input.toolCallId);
    if (existing) return { question: toQuestion(existing), created: false };
    const open = input.itemId
      ? this.db
          .prepare("SELECT * FROM taste_questions WHERE item_id = ? AND status = 'open'")
          .get(input.itemId)
      : undefined;
    if (open) return { question: toQuestion(open), created: false };
    const r = this.db
      .prepare(
        "INSERT INTO taste_questions (card_id, item_id, question, tool_call_id, conversation_id, created_at) VALUES (:card_id, :item_id, :question, :tool_call_id, :conversation_id, :now)",
      )
      .run(
        bind({
          card_id: input.cardId,
          item_id: input.itemId,
          question: input.question,
          tool_call_id: input.toolCallId,
          conversation_id: input.conversationId,
          now: nowIso(),
        }),
      );
    return { question: this.question(Number(r.lastInsertRowid))!, created: true };
  }

  question(id: number): TasteQuestion | undefined {
    const r = this.db.prepare("SELECT * FROM taste_questions WHERE id = ?").get(id);
    return r ? toQuestion(r) : undefined;
  }

  questions(status?: TasteQuestion["status"]): TasteQuestion[] {
    const sql = status
      ? "SELECT * FROM taste_questions WHERE status = ? ORDER BY id"
      : "SELECT * FROM taste_questions ORDER BY id";
    return (status ? this.db.prepare(sql).all(status) : this.db.prepare(sql).all()).map(toQuestion);
  }

  answer(id: number, labels: HfsCategory[]): TasteQuestion | undefined {
    this.db
      .prepare(
        "UPDATE taste_questions SET status = 'answered', answer_labels_json = ?, answered_at = ? WHERE id = ? AND status = 'open'",
      )
      .run(JSON.stringify(labels), nowIso(), id);
    return this.question(id);
  }
}

export const clamp = (weight: number) => Math.min(2, Math.max(0.1, weight));
