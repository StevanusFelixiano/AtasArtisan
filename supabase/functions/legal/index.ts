// /legal/privacy | /legal/terms | /legal/support: the Support and Privacy Policy URLs in App Store Connect. App Review
// could not open the sslip.io pages (guideline 1.5, 2026-10-29 and 2026-11-10), and Supabase rewrites function HTML to
// text/plain, so this serves plain-text copies (docs.json, written by legal/build.py). The app opens the styled pages.
import docs from "./docs.json" with { type: "json" };

const TEXT: Record<string, string> = docs;
Deno.serve((req) => {
  const doc = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!Object.hasOwn(TEXT, doc)) return new Response("not found", { status: 404 });
  return new Response(TEXT[doc], {
    headers: { "content-type": "text/plain; charset=utf-8", "x-robots-tag": "noindex, nofollow" },
  });
});
