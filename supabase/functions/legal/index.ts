// /legal/privacy | /legal/terms | /legal/support -> the PDF in the public `legal` bucket.
// Supabase serves function HTML as text/plain, so the documents are PDFs (Masterplan's pattern).
const DOCS = new Set(["privacy", "terms", "support"]);
Deno.serve((req) => {
  const doc = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!DOCS.has(doc)) return new Response("not found", { status: 404 });
  const url = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/legal/${doc}.pdf`;
  return new Response(null, { status: 302, headers: { location: url } });
});
