// Article text through Readability on linkedom, plus the og:image and the publish date the page states (meta tags,
// JSON-LD, <time>, or a date in the url).
import { Readability } from "@mozilla/readability";
import { parseHTML } from "linkedom";
import { stripHtml } from "./http.ts";

export interface Article {
  title?: string;
  byline?: string;
  text: string;
  excerpt?: string;
  imageUrl?: string;
  publishedAt?: string;
}

export type DateSource = "feed" | "meta" | "jsonld" | "time" | "url" | "model" | "unknown";

const META = [
  "article:published_time",
  "og:published_time",
  "og:article:published_time",
  "article:published",
  "datePublished",
  "parsely-pub-date",
  "sailthru.date",
  "dc.date.issued",
  "DC.date.issued",
  "dc.date",
  "citation_publication_date",
  "publish-date",
  "publish_date",
  "pubdate",
  "date",
];

/** An ISO time for a plausible publish date: not before 1995, not more than a day ahead. */
export function plausible(value: unknown, now = Date.now()): string | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  const ms = Date.parse(value.trim());
  if (!Number.isFinite(ms) || ms < Date.UTC(1995, 0, 1) || ms > now + 86_400_000) return undefined;
  return new Date(ms).toISOString();
}

function jsonLd(value: unknown, depth = 0): string | undefined {
  if (!value || typeof value !== "object" || depth > 6) return undefined;
  if (Array.isArray(value)) {
    for (const v of value) {
      const found = jsonLd(v, depth + 1);
      if (found) return found;
    }
    return undefined;
  }
  const o = value as Record<string, unknown>;
  if (typeof o.datePublished === "string") return o.datePublished;
  for (const key of ["@graph", "mainEntity", "mainEntityOfPage"]) {
    const found = jsonLd(o[key], depth + 1);
    if (found) return found;
  }
  return typeof o.dateCreated === "string" ? o.dateCreated : undefined;
}

/** A date in the path: /2026/10/12/ or /2026-10-12-. */
export function dateInUrl(url: string, now = Date.now()): string | undefined {
  const m = url.match(/\/(20\d{2})[/-](\d{1,2})[/-](\d{1,2})(?=[/\-_.]|$)/);
  return m
    ? plausible(`${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`, now)
    : undefined;
}

/** The publish date a page states in its markup, and where it said so. */
export function dateInHtml(
  html: string,
  url: string,
  now = Date.now(),
): { at: string; source: DateSource } | undefined {
  return dateInDocument(parseHTML(html).document, url, now);
}

function dateInDocument(
  document: any,
  url: string,
  now = Date.now(),
): { at: string; source: DateSource } | undefined {
  for (const name of META) {
    const el =
      document.querySelector(`meta[property="${name}"]`) ??
      document.querySelector(`meta[name="${name}"]`) ??
      document.querySelector(`meta[itemprop="${name}"]`);
    const at = plausible(el?.getAttribute("content"), now);
    if (at) return { at, source: "meta" };
  }
  for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      const at = plausible(jsonLd(JSON.parse(script.textContent ?? "")), now);
      if (at) return { at, source: "jsonld" };
    } catch {
      // Broken JSON-LD is common; try the next block.
    }
  }
  const itemprop = document.querySelector('[itemprop="datePublished"]');
  const time =
    plausible(itemprop?.getAttribute("datetime") ?? itemprop?.getAttribute("content"), now) ??
    plausible(document.querySelector("article time[datetime]")?.getAttribute("datetime"), now) ??
    plausible(document.querySelector("time[pubdate]")?.getAttribute("datetime"), now) ??
    plausible(document.querySelector("time[datetime]")?.getAttribute("datetime"), now);
  if (time) return { at: time, source: "time" };
  const fromUrl = dateInUrl(url, now);
  return fromUrl ? { at: fromUrl, source: "url" } : undefined;
}

const meta = (document: any, names: string[]): string | undefined => {
  for (const name of names) {
    const el =
      document.querySelector(`meta[property="${name}"]`) ??
      document.querySelector(`meta[name="${name}"]`);
    const content = el?.getAttribute("content");
    if (content) return content;
  }
  return undefined;
};

export function extractArticle(html: string, url: string, maxChars = 12_000): Article {
  const { document } = parseHTML(html);
  const imageRaw = meta(document, [
    "og:image",
    "og:image:url",
    "twitter:image",
    "twitter:image:src",
  ]);
  let imageUrl: string | undefined;
  try {
    imageUrl = imageRaw ? new URL(imageRaw, url).toString() : undefined;
  } catch {
    imageUrl = undefined;
  }
  const published = dateInDocument(document, url)?.at;
  let parsed: {
    title?: string | null;
    byline?: string | null;
    textContent?: string | null;
    excerpt?: string | null;
  } | null = null;
  try {
    parsed = new Readability(document as any).parse();
  } catch {
    parsed = null;
  }
  const text = (parsed?.textContent ?? stripHtml(html, maxChars) ?? "")
    .replace(/\s+\n/g, "\n")
    .replace(/[ \t]+/g, " ")
    .trim()
    .slice(0, maxChars);
  return {
    title:
      parsed?.title ??
      meta(document, ["og:title", "twitter:title"]) ??
      document.querySelector("title")?.textContent ??
      undefined,
    byline: parsed?.byline ?? undefined,
    text,
    excerpt:
      parsed?.excerpt ??
      meta(document, ["og:description", "description", "twitter:description"]) ??
      text.slice(0, 400),
    imageUrl,
    publishedAt: published,
  };
}

export interface PageLink {
  text: string;
  url: string;
}

/** Every http(s) link a page's HTML points to, absolute, once each, without fragments or links back to itself. */
export function htmlLinks(html: string, base: string, max = 60): PageLink[] {
  const { document } = parseHTML(html);
  return uniqueLinks(
    [...document.querySelectorAll("a[href]")].map((a: any) => ({
      text: String(a.textContent ?? ""),
      url: String(a.getAttribute("href") ?? ""),
    })),
    base,
    max,
  );
}

/** Every http(s) link in markdown ([text](url)), absolute, once each. */
export function markdownLinks(markdown: string, base: string, max = 60): PageLink[] {
  return uniqueLinks(
    [...markdown.matchAll(/\[([^\]]*)\]\((\S+?)(?:\s+"[^"]*")?\)/g)].map((m) => ({
      text: m[1],
      url: m[2],
    })),
    base,
    max,
  );
}

function uniqueLinks(links: PageLink[], base: string, max: number): PageLink[] {
  const self = base.replace(/#.*$/, "");
  const out = new Map<string, PageLink>();
  for (const link of links) {
    let url: URL;
    try {
      url = new URL(link.url, base);
    } catch {
      continue;
    }
    url.hash = "";
    const href = url.toString();
    if (!/^https?:$/.test(url.protocol) || href === self || out.has(href)) continue;
    out.set(href, { text: link.text.replace(/\s+/g, " ").trim().slice(0, 100), url: href });
    if (out.size >= max) break;
  }
  return [...out.values()];
}
