// Reverse-OTP: the user sends "ATASTE 4K9X" from their own WhatsApp; the app never sees or sends a phone number.
//   POST /otp/start          -> {code: "ATASTE 4K9X", message, nonce, expires_at}   (app opens wa.me with message)
//   GET  /otp/status?nonce=  -> {status: pending|expired|verified|taken, phone?, push_name?, token_hash?, account?}
//   POST /otp/claim {nonce}  -> {token_hash}   9-7 "Continue as Rani": signed in, take over the number's account
//   POST /otp/review {code}  -> {token_hash}   App Review's demo account (code in Vault as a SHA-256)
// The VPS WhatsApp bridge marks a code verified through `wa-inbound` once the user's message arrives from their own
// number. Two modes, chosen at /start:
//   - Verify (signed in, Sign in with Apple builds): the code carries the caller's user_id and the number goes on
//     their profile, the Verified badge. A number on another account answers "taken" (9-7) instead.
//   - Sign-in (no session, builds 23 and older): a verified code is redeemed once for a magic-link token hash; the
//     app finishes with auth.verifyOTP(tokenHash:type:.magiclink).
// No JWT is minted here; GoTrue issues the session. Deployed with verify_jwt off: old builds' callers aren't signed in.
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

/// The text prefilled in WhatsApp. It explains itself; the bridge only reads the "ATASTE XXXX" in it.
function waMessage(code: string, verify: boolean) {
  return verify
    ? `ATASTE ${code}\n\nHi Ataste! This is my code. I'm pressing send to verify my number.`
    : `ATASTE ${code}\n\nHi Ataste! This is my sign-in code. I'm pressing send to sign in to the app.`;
}

/// The signed-in caller (verify mode), or null: old builds call while signed out.
async function caller(req: Request) {
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer /i, "");
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt);
  return data.user ?? null;
}

/// A one-time magic-link token hash for an existing user. The email is read, not derived from the number: an
/// Apple account's email is `<sub>@apple.ataste.invalid`, and a changed number leaves the old one in the email.
async function tokenFor(userID: string) {
  const { data, error } = await admin.auth.admin.getUserById(userID);
  if (error || !data.user?.email) throw error ?? new Error(`user ${userID} has no email`);
  const { data: link, error: e2 } = await admin.auth.admin.generateLink({ type: "magiclink", email: data.user.email });
  if (e2) throw e2;
  return link.properties.hashed_token;
}

/// Verify mode, once the message has arrived. The number becomes the caller's (also Change number), unless another
/// account has it: then "taken" with that account (9-7), and the code stays unclaimed for /claim.
async function verifyNumber(row: { nonce: string; phone: string; user_id: string; consumed_at: string | null }) {
  const { data: owner } = await admin.from("profiles").select("id, name, avatar, avatar_bg").eq("phone", row.phone).maybeSingle();
  if (owner && owner.id !== row.user_id) {
    if (row.consumed_at) return { status: "expired" };
    const { count } = await admin.from("members").select("group_id", { count: "exact", head: true })
      .eq("user_id", owner.id).is("removed_at", null);
    return {
      status: "taken", phone: row.phone,
      account: { name: owner.name, avatar: owner.avatar, avatar_bg: owner.avatar_bg, groups: count ?? 0 },
    };
  }
  // Redeem once, as in sign-in mode.
  const { data: claimed } = await admin.from("wa_codes").update({ consumed_at: new Date().toISOString() })
    .eq("nonce", row.nonce).is("consumed_at", null).select("phone").maybeSingle();
  if (!claimed) return { status: "expired" };
  if (!owner) {
    const { error } = await admin.from("profiles").update({ phone: row.phone }).eq("id", row.user_id);
    if (error) throw error;
  }
  return { status: "verified", phone: row.phone };
}

function ipOf(req: Request) {
  return (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
}

/// Sign-in mode: the user for this number, created on first sign-in, and a one-time magic-link token hash.
async function signIn(phone: string, pushName: string) {
  const { data: prof } = await admin.from("profiles").select("id").eq("phone", phone).maybeSingle();
  if (prof) return { phone, push_name: pushName, token_hash: await tokenFor(prof.id), new_user: false };
  const email = `${phone}@wa.ataste.invalid`;
  const { data: created, error } = await admin.auth.admin.createUser({
    email, email_confirm: true, user_metadata: { phone },
  });
  if (error) throw error;
  const { error: e2 } = await admin.from("profiles").insert({ id: created.user.id, phone, name: "" });
  if (e2) throw e2;
  const { data: link, error: e3 } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (e3) throw e3;
  return { phone, push_name: pushName, token_hash: link.properties.hashed_token, new_user: true };
}

Deno.serve(async (req) => {
  const path = new URL(req.url).pathname.replace(/^.*\/otp/, "");
  try {
    if (req.method === "POST" && path === "/start") {
      // No per-IP limit: a whole campus shares one IP. Codes can't be verified without the sender's
      // WhatsApp, so a flood only fills the 32^4 code space (~1.7k starts/s held for 10 min).
      const ip = ipOf(req);
      const user = await caller(req);
      const nonce = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
      for (let i = 0; i < 5; i++) {
        const code = randomCode();
        // A code is reusable once its previous holder expired: clear stale rows first.
        await admin.from("wa_codes").delete().eq("code", code).lt("expires_at", new Date().toISOString());
        const { data, error } = await admin.from("wa_codes").insert({ code, nonce, ip, user_id: user?.id ?? null })
          .select("expires_at").single();
        if (!error) return json({ code: `ATASTE ${code}`, message: waMessage(code, !!user), nonce, expires_at: data.expires_at });
      }
      return json({ error: "Please try again." }, 503);
    }

    if (req.method === "GET" && path === "/status") {
      const nonce = new URL(req.url).searchParams.get("nonce") ?? "";
      const { data: row } = await admin.from("wa_codes").select("*").eq("nonce", nonce).maybeSingle();
      if (!row) return json({ status: "expired" });
      // A verify-mode code answers only the user who started it.
      if (row.user_id && (await caller(req))?.id !== row.user_id) return json({ status: "expired" });
      if (!row.verified_at) {
        return json({ status: Date.parse(row.expires_at) < Date.now() ? "expired" : "pending" });
      }
      if (row.user_id) return json(await verifyNumber(row));
      // Sign-in mode. Redeem once: the first status call after verification takes the session.
      const { data: claimed } = await admin.from("wa_codes").update({ consumed_at: new Date().toISOString() })
        .eq("nonce", nonce).is("consumed_at", null).select("phone, push_name").maybeSingle();
      if (!claimed) return json({ status: "expired" });
      return json({ status: "verified", ...(await signIn(claimed.phone, claimed.push_name ?? "")) });
    }

    // 9-7 "Continue as Rani": the caller verified a number that belongs to an older account (a TestFlight user who
    // signed in with WhatsApp). This Apple ID moves to that account, the caller's new empty account is deleted, and
    // the app signs in to the old one.
    if (req.method === "POST" && path === "/claim") {
      const user = await caller(req);
      if (!user) return json({ error: "Your session ended. Sign in again." }, 401);
      const { nonce } = await req.json().catch(() => ({ nonce: "" }));
      const ranOut = json({ error: "This code ran out. Verify your number again." }, 409);
      const { data: row } = await admin.from("wa_codes").select("*").eq("nonce", String(nonce ?? "")).maybeSingle();
      if (!row || row.user_id !== user.id || !row.verified_at || row.consumed_at ||
          Date.now() - Date.parse(row.verified_at) > 10 * 60_000) return ranOut;
      const { data: owner } = await admin.from("profiles").select("id").eq("phone", row.phone).maybeSingle();
      if (!owner || owner.id === user.id) return ranOut;
      const { count } = await admin.from("members").select("group_id", { count: "exact", head: true }).eq("user_id", user.id);
      if (count) return json({ error: "This account already has group orders. Verify a different number." }, 409);
      const { data: mine } = await admin.from("apple_accounts").select("sub").eq("user_id", user.id).maybeSingle();
      const { data: theirs } = await admin.from("apple_accounts").select("sub").eq("user_id", owner.id).maybeSingle();
      if (theirs && theirs.sub !== mine?.sub) return json({ error: "That account signs in with a different Apple ID." }, 409);
      const { data: claimed } = await admin.from("wa_codes").update({ consumed_at: new Date().toISOString() })
        .eq("nonce", row.nonce).is("consumed_at", null).select("code").maybeSingle();
      if (!claimed) return ranOut;
      if (mine && !theirs) {
        const { error } = await admin.from("apple_accounts").update({ user_id: owner.id }).eq("user_id", user.id);
        if (error) throw error;
      }
      const token_hash = await tokenFor(owner.id);
      const { error } = await admin.auth.admin.deleteUser(user.id);
      if (error) console.error("claim: deleting the empty account", error);
      return json({ token_hash });
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
