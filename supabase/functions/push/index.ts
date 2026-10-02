// Sends one notifications row to the user's devices. Called by the notifications insert trigger
// (push_notification); the trigger's x-push-secret is the only way in. Muted kinds are skipped.
// APNs key in Vault: apns_key (.p8 text), apns_key_id. Adapted from Masterplan's push function,
// with GoodMinton's rule: a BadDeviceToken is retried on the other APNs host before the token is dropped.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const TEAM = "36J8TBMX5T";
const APP = "com.bayujo.Ataste";
const HOST: Record<string, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

async function secret(name: string): Promise<string> {
  const { data, error } = await admin.rpc("secret", { name });
  if (error) throw error;
  return String(data ?? "").trim();
}

/// Shared provider token, renewed after 40 minutes (APNs refuses one older than 60).
async function providerToken(): Promise<string> {
  const { data } = await admin.from("apns_jwt").select("token, issued_at").maybeSingle();
  if (data && Date.now() - Date.parse(data.issued_at) < 40 * 60_000) return data.token;
  const key = await importPKCS8(await secret("apns_key"), "ES256");
  const token = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: await secret("apns_key_id") })
    .setIssuer(TEAM).setIssuedAt().sign(key);
  await admin.from("apns_jwt").upsert({ id: true, token, issued_at: new Date().toISOString() });
  return token;
}

async function send(env: string, device: string, payload: unknown, collapse: string) {
  const res = await fetch(`${HOST[env] ?? HOST.production}/3/device/${device}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-push-type": "alert", "apns-topic": APP, "apns-priority": "10", "apns-collapse-id": collapse,
    },
    body: JSON.stringify(payload),
  });
  if (res.ok) return null;
  const reason = ((await res.json().catch(() => ({}))) as { reason?: string }).reason ?? String(res.status);
  console.error(`apns ${res.status}: ${reason}`);
  return res.status === 410 ? "Unregistered" : reason;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== await secret("push_hook_secret")) {
    return new Response("forbidden", { status: 403 });
  }
  const { id } = await req.json();
  const { data: n } = await admin.from("notifications").select("*").eq("id", id).maybeSingle();
  if (!n) return new Response("no such notification", { status: 404 });
  const { data: prof } = await admin.from("profiles").select("notify_mute").eq("id", n.user_id).maybeSingle();
  if ((prof?.notify_mute ?? []).includes(n.kind)) return Response.json({ sent: false, muted: true });

  const { data: devices } = await admin.from("devices").select("token, env").eq("user_id", n.user_id);
  for (const d of devices ?? []) {
    const payload = {
      aps: { alert: { title: n.title, body: n.body }, sound: "default", "thread-id": n.group_id ?? "ataste" },
      group: n.group_id, kind: n.kind,
    };
    let reason = await send(d.env, d.token, payload, `${n.kind}-${n.group_id ?? n.id}`);
    if (reason === "BadDeviceToken") {
      reason = await send(d.env === "sandbox" ? "production" : "sandbox", d.token, payload, `${n.kind}-${n.group_id ?? n.id}`);
    }
    if (reason === "Unregistered" || reason === "BadDeviceToken") {
      await admin.from("devices").delete().eq("token", d.token);
    }
  }
  return Response.json({ sent: true });
});
