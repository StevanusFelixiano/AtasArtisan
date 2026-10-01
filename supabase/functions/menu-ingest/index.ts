// Called only by the VPS menu scraper (header x-scraper-secret, checked against its SHA-256 in
// Vault). Body: {collections: [{id, name, sort}], products: [{id, collection_id, name, description,
// photo_url, base_price, option_groups, variants, available, sort}]}. Upserts everything sent and
// marks products missing from the payload unavailable, which fires the sold-out notices.
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  const { data: want } = await admin.rpc("secret", { name: "scraper_secret_sha256" });
  if ((await sha256(req.headers.get("x-scraper-secret") ?? "")) !== String(want ?? "").trim()) {
    return new Response("forbidden", { status: 403 });
  }
  const { collections = [], products = [] } = await req.json();
  if (!products.length) return new Response("empty menu refused", { status: 400 }); // a broken scrape must not empty the menu
  const now = new Date().toISOString();
  let e = (await admin.from("collections").upsert(collections)).error;
  if (!e) e = (await admin.from("products").upsert(products.map((p: Record<string, unknown>) => ({ ...p, updated_at: now })))).error;
  if (e) return new Response(e.message, { status: 500 });
  const ids = products.map((p: { id: string }) => p.id);
  const { data: gone } = await admin.from("products").update({ available: false })
    .not("id", "in", `(${ids.map((i: string) => `"${i}"`).join(",")})`).eq("available", true).select("id");
  await admin.from("menu_meta").upsert({ id: true, synced_at: now });
  return Response.json({ products: ids.length, collections: collections.length, gone: gone?.length ?? 0 });
});
