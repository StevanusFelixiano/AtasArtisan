// DELETE (signed in): deletes the caller's account and everything that hangs off it (tables
// cascade from auth.users; receipts and delivery photos they uploaded are removed from storage).
// App Store guideline 5.1.1(v). verify_jwt on.
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  if (req.method !== "DELETE") return new Response("method not allowed", { status: 405 });
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return new Response("unauthorized", { status: 401 });

  const { data: groups } = await admin.from("members").select("group_id").eq("user_id", user.id);
  const receipts = (groups ?? []).map((g) => `${g.group_id}/${user.id}.jpg`);
  if (receipts.length) await admin.storage.from("receipts").remove(receipts);
  const { data: photos } = await admin.from("delivery_proofs").select("path").eq("by_user", user.id);
  if (photos?.length) await admin.storage.from("delivery").remove(photos.map((p) => p.path));

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return new Response(error.message, { status: 500 });
  return Response.json({ deleted: true });
});
