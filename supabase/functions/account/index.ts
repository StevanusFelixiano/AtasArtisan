// DELETE (signed in): deletes the caller's account and everything that hangs off it (tables
// cascade from auth.users; receipts and delivery photos they uploaded are removed from storage), and disconnects
// their Apple ID by revoking its refresh token. App Store guideline 5.1.1(v). verify_jwt on.
import { createClient } from "npm:@supabase/supabase-js@2";
import { revoke } from "../_shared/apple.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function secret(name: string) {
  const { data, error } = await admin.rpc("secret", { name });
  if (error) throw error;
  return String(data ?? "").trim();
}

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

  // Apple's side failing never keeps the account: it is logged and the deletion goes ahead.
  const { data: apple } = await admin.from("apple_accounts").select("refresh_token").eq("user_id", user.id).maybeSingle();
  if (apple?.refresh_token && !(await revoke(apple.refresh_token, secret))) {
    console.error(`account: Apple revoke failed for ${user.id}; deleting anyway`);
  }

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return new Response(error.message, { status: 500 });
  return Response.json({ deleted: true });
});
