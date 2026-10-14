// Sign in with Apple (9-1), and linking an Apple ID to a signed-in account (9-8).
//   POST /apple {identity_token, authorization_code, nonce, given_name?}
//     no session         -> {token_hash, new_user, given_name}   the app finishes with auth.verifyOTP(tokenHash:type:.magiclink)
//     Bearer <user jwt>  -> {linked: true}                       409 when this Apple ID already has its own account
// The identity token must be Apple's (their JWKS), for this app, and carry SHA-256(nonce): the app made the nonce
// for this one sign-in, so a token lifted from elsewhere can't be replayed. A new Apple ID gets a new account with no
// phone number (`<sub>@apple.ataste.invalid`); verifying a number is a separate, optional step (`otp`).
// No JWT is minted here; GoTrue issues the session. Deployed with verify_jwt off: sign-in callers have no session.
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, decodeJwt, jwtVerify } from "npm:jose@5";
import { APPLE_CLIENT_ID, APPLE_ISSUER, refreshToken } from "../_shared/apple.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const JWKS = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));

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

/// Apple's user id from a verified identity token, or null.
async function appleSub(idToken: string, nonce: string) {
  try {
    const { payload } = await jwtVerify(idToken, JWKS, { issuer: APPLE_ISSUER, audience: APPLE_CLIENT_ID });
    if (!nonce || payload.nonce !== await sha256(nonce) || !payload.sub) return null;
    return payload.sub;
  } catch (e) {
    console.error("apple identity token", e);
    return null;
  }
}

/// A one-time magic-link token hash for an existing user. The email is read, not derived: an account made by
/// WhatsApp sign-in (`<phone>@wa.ataste.invalid`) can sign in with Apple once linked or claimed (9-7).
async function tokenFor(userID: string) {
  const { data, error } = await admin.auth.admin.getUserById(userID);
  if (error || !data.user?.email) throw error ?? new Error(`user ${userID} has no email`);
  const { data: link, error: e2 } = await admin.auth.admin.generateLink({ type: "magiclink", email: data.user.email });
  if (e2) throw e2;
  return link.properties.hashed_token;
}

/// The caller's session token, when the request is from a signed-in user (the SDK sends no Authorization header
/// while signed out with a publishable key; an anon-role JWT also means "not signed in").
function userJWT(req: Request) {
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer /i, "");
  try {
    return decodeJwt(jwt).role === "authenticated" ? jwt : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "not found" }, 404);
  try {
    const body = await req.json().catch(() => ({}));
    const sub = await appleSub(String(body.identity_token ?? ""), String(body.nonce ?? ""));
    if (!sub) return json({ error: "Couldn't sign in. Try again." }, 401);
    const givenName = String(body.given_name ?? "").trim().slice(0, 60);
    const refresh = body.authorization_code ? await refreshToken(String(body.authorization_code), secret) : null;
    // A failed exchange keeps whatever refresh token is already stored.
    const apple = { sub, ...(refresh ? { refresh_token: refresh } : {}) };

    // 9-8: link this Apple ID to the signed-in account.
    const jwt = userJWT(req);
    if (jwt) {
      const { data: { user } } = await admin.auth.getUser(jwt);
      if (!user) return json({ error: "Your session ended. Sign in again." }, 401);
      const { data: owner } = await admin.from("apple_accounts").select("user_id").eq("sub", sub).maybeSingle();
      if (owner && owner.user_id !== user.id) return json({ error: "This Apple ID already has its own Ataste account." }, 409);
      const { error } = await admin.from("apple_accounts").upsert({ user_id: user.id, ...apple });
      if (error) throw error;
      return json({ linked: true });
    }

    // 9-1: sign in. A known Apple ID signs in to its account.
    const { data: known } = await admin.from("apple_accounts").select("user_id").eq("sub", sub).maybeSingle();
    if (known) {
      if (refresh) await admin.from("apple_accounts").update({ refresh_token: refresh }).eq("user_id", known.user_id);
      return json({ token_hash: await tokenFor(known.user_id), new_user: false, given_name: givenName });
    }

    // A new Apple ID: a new account without a number. "Already registered" is a sign-in that failed half-way; the
    // link below still finds that user, and the rows are written again.
    const email = `${sub}@apple.ataste.invalid`;
    const { error: e1 } = await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: { apple: true } });
    if (e1 && (e1 as { code?: string }).code !== "email_exists") throw e1;
    const { data: link, error: e2 } = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (e2) throw e2;
    const id = link.user.id;
    const { error: e3 } = await admin.from("profiles").upsert({ id, name: givenName }, { onConflict: "id", ignoreDuplicates: true });
    if (e3) throw e3;
    const { error: e4 } = await admin.from("apple_accounts").upsert({ user_id: id, ...apple });
    if (e4) throw e4;
    return json({ token_hash: link.properties.hashed_token, new_user: true, given_name: givenName });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
