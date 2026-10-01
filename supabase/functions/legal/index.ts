// /legal/privacy | /legal/terms | /legal/support: the URLs App Store Connect has. Supabase serves function HTML as
// text/plain, so the pages live on the VPS (repo web/legal, built by legal/build.py); this redirects there.
const DOCS = new Set(["privacy", "terms", "support"]);
Deno.serve((req) => {
  const doc = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!DOCS.has(doc)) return new Response("not found", { status: 404 });
  return new Response(null, { status: 302, headers: { location: `https://ataste.51-79-240-114.sslip.io/legal/${doc}` } });
});
