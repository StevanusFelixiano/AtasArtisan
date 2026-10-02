// Reverse-OTP sign-in. The app never sees or sends a phone number:
//   POST /otp/start          -> {code: "ATASTE 4K9X", nonce, expires_at}   (app opens wa.me with the code)
//   GET  /otp/status?nonce=  -> {status: pending|expired|verified, phone?, push_name?, token_hash?}
//   POST /otp/review {code}  -> {token_hash}   App Review's demo account (code in Vault as a SHA-256)
// The VPS WhatsApp bridge marks a code verified through `wa-inbound` once the user's message
// arrives from their own number. A verified code is redeemed once: we create the user if needed
// and hand back a magic-link token hash; the app finishes with auth.verifyOTP(tokenHash:type:.magiclink).
// No JWT is minted here; GoTrue issues the session. Deployed with verify_jwt off: callers aren't signed in yet.
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const REVIEW_PHONE = "6200000000001";

const json = (body: unknown, status = 200) => Response.json(body, { status });

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function secret(name: string) {
  const { data, error } = await admin.rpc("secret", { name });
  if (error) throw error;
  return String(data ?? "").trim();
}

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(4));
  return [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join("");
}

function ipOf(req: Request) {
  return (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
}

/// The user for this number, created on first sign-in, and a one-time magic-link token hash.
async function signIn(phone: string, pushName: string) {
  const email = `${phone}@wa.ataste.invalid`;
  const { data: prof } = await admin.from("profiles").select("id").eq("phone", phone).maybeSingle();
  if (!prof) {
    const { data: created, error } = await admin.auth.admin.createUser({
      email, email_confirm: true, user_metadata: { phone },
    });
    if (error) throw error;
    const { error: e2 } = await admin.from("profiles").insert({ id: created.user.id, phone, name: "" });
    if (e2) throw e2;
  }
  const { data: link, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (error) throw error;
  return { phone, push_name: pushName, token_hash: link.properties.hashed_token, new_user: !prof };
}

Deno.serve(async (req) => {
  const path = new URL(req.url).pathname.replace(/^.*\/otp/, "");
  try {
    if (req.method === "POST" && path === "/start") {
      const ip = ipOf(req);
      const since = new Date(Date.now() - 10 * 60_000).toISOString();
      const { count } = await admin.from("wa_codes").select("code", { count: "exact", head: true })
        .eq("ip", ip).gte("created_at", since);
      if ((count ?? 0) >= 6) return json({ error: "Too many attempts. Try again in a few minutes." }, 429);
      const nonce = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
      for (let i = 0; i < 5; i++) {
        const code = randomCode();
        // A code is reusable once its previous holder expired: clear stale rows first.
        await admin.from("wa_codes").delete().eq("code", code).lt("expires_at", new Date().toISOString());
        const { data, error } = await admin.from("wa_codes").insert({ code, nonce, ip }).select("expires_at").single();
        if (!error) return json({ code: `ATASTE ${code}`, nonce, expires_at: data.expires_at });
      }
      return json({ error: "Please try again." }, 503);
    }

    if (req.method === "GET" && path === "/status") {
      const nonce = new URL(req.url).searchParams.get("nonce") ?? "";
      const { data: row } = await admin.from("wa_codes").select("*").eq("nonce", nonce).maybeSingle();
      if (!row) return json({ status: "expired" });
      if (!row.verified_at) {
        return json({ status: Date.parse(row.expires_at) < Date.now() ? "expired" : "pending" });
      }
      // Redeem once: the first status call after verification takes the session.
      const { data: claimed } = await admin.from("wa_codes").update({ consumed_at: new Date().toISOString() })
        .eq("nonce", nonce).is("consumed_at", null).select("phone, push_name").maybeSingle();
      if (!claimed) return json({ status: "expired" });
      return json({ status: "verified", ...(await signIn(claimed.phone, claimed.push_name ?? "")) });
    }

    if (req.method === "POST" && path === "/review") {
      const { code } = await req.json().catch(() => ({ code: "" }));
      const ok = String(code ?? "").length >= 6 &&
        (await sha256(String(code).trim().toUpperCase())) === (await secret("review_code_sha256"));
      if (!ok) {
        await new Promise((r) => setTimeout(r, 1500)); // slow down guessing
        return json({ error: "That code isn't right." }, 403);
      }
      return json({ status: "verified", ...(await signIn(REVIEW_PHONE, "App Review")) });
    }
    return json({ error: "not found" }, 404);
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
