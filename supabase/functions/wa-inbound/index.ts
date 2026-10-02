// Called only by the Ataste WhatsApp bridge on the VPS when "ATASTE XXXX" arrives from a user's own
// WhatsApp. The sender's number comes from WhatsApp itself, never from the app. Header
// x-bridge-secret is checked against its SHA-256 in Vault. Idempotent on wa_id: a re-delivered
// message answers "duplicate" and the bridge stays quiet.
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  const { data: want } = await admin.rpc("secret", { name: "bridge_secret_sha256" });
  if ((await sha256(req.headers.get("x-bridge-secret") ?? "")) !== String(want ?? "").trim()) {
    return new Response("forbidden", { status: 403 });
  }
  const { code, phone, wa_id, push_name } = await req.json();
  const digits = String(phone ?? "").replace(/\D/g, "");
  if (!/^[0-9]{8,15}$/.test(digits) || !wa_id) return Response.json({ status: "unknown" });

  const { data: seen } = await admin.from("wa_codes").select("code").eq("wa_id", wa_id).maybeSingle();
  if (seen) return Response.json({ status: "duplicate" });

  const { data: row } = await admin.from("wa_codes").select("*").eq("code", String(code).toUpperCase()).maybeSingle();
  if (!row) return Response.json({ status: "unknown" });
  if (row.verified_at) return Response.json({ status: "duplicate" });
  if (Date.parse(row.expires_at) < Date.now()) return Response.json({ status: "expired" });

  const { data: done } = await admin.from("wa_codes")
    .update({ phone: digits, push_name: String(push_name ?? "").slice(0, 60), wa_id, verified_at: new Date().toISOString() })
    .eq("code", row.code).is("verified_at", null).select("code").maybeSingle();
  return Response.json({ status: done ? "verified" : "duplicate" });
});
