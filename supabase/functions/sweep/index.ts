// Daily (cron ataste-sweep): deletes receipts and delivery photos older than a week, and the delivery_proofs
// rows that point at them. Storage objects can't be deleted with SQL (storage.protect_delete), hence a function.
// The cron's x-push-secret is the only way in.
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  const { data: secret } = await admin.rpc("secret", { name: "push_hook_secret" });
  if (req.headers.get("x-push-secret") !== String(secret ?? "").trim()) return new Response("forbidden", { status: 403 });
  const { data, error } = await admin.rpc("expired_images");
  if (error) return new Response(error.message, { status: 500 });
  const removed: Record<string, number> = {};
  for (const bucket of ["receipts", "delivery"]) {
    // ponytail: one remove call per bucket, fine below ~1000 expired files a day; batch it past that.
    const names = (data as { bucket_id: string; name: string }[]).filter((o) => o.bucket_id === bucket).map((o) => o.name);
    if (!names.length) continue;
    const { error } = await admin.storage.from(bucket).remove(names);
    if (error) return new Response(error.message, { status: 500 });
    if (bucket === "delivery") await admin.from("delivery_proofs").delete().in("path", names);
    removed[bucket] = names.length;
  }
  return Response.json(removed);
});
