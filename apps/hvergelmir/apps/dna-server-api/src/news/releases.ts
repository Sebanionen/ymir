/** Exact release URLs identify a package. Ordinary articles that mention versions are not release entries. */
export interface PackageRelease {
  key: string;
  version: string;
}

/** Missing dates sort behind known publication dates. Arrival order breaks exact ties only. */
export function comparePublished(
  a: { id: number; publishedAt?: string },
  b: { id: number; publishedAt?: string },
): number {
  const date = (s?: string) => {
    const n = s ? Date.parse(s) : NaN;
    return Number.isFinite(n) ? n : -Infinity;
  };
  const x = date(a.publishedAt),
    y = date(b.publishedAt);
  return x === y ? a.id - b.id : x > y ? 1 : -1;
}

export function packageRelease(url: string): PackageRelease | undefined {
  try {
    const u = new URL(url);
    if (
      !["https:", "http:"].includes(u.protocol) ||
      u.hostname.toLowerCase().replace(/^www\./, "") !== "github.com"
    )
      return undefined;
    const path = u.pathname.match(/^\/([^/]+)\/([^/]+)\/releases\/tag\/(.+?)\/?$/);
    if (!path) return undefined;
    const tag = decodeURIComponent(path[3]);
    const match = tag.match(/^(.*?)(?:v)?(\d+\.\d+\.\d+(?:-[\da-zA-Z.-]+)?(?:\+[\da-zA-Z.-]+)?)$/);
    if (!match) return undefined;
    const prefix = match[1].replace(/[-@/]$/, "").toLowerCase();
    return {
      key: `github:${path[1].toLowerCase()}/${path[2].toLowerCase()}:${prefix}`,
      version: match[2],
    };
  } catch {
    return undefined;
  }
}
