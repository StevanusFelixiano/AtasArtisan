// Sign in with Apple's server side, shared by `apple` (sign-in, linking) and `account` (deletion revokes the token).
// Apple's token endpoints take a client secret: an ES256 JWT signed with the Sign in with Apple key, Vault
// `siwa_key` (.p8 text) and `siwa_key_id`. Each function passes its own Vault reader (the `secret` RPC).
import { importPKCS8, SignJWT } from "npm:jose@5";

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_CLIENT_ID = "com.bayujo.Ataste";
const TEAM = "36J8TBMX5T";

type Secret = (name: string) => Promise<string>;

/// The client secret, good for one hour (Apple allows up to six months).
async function clientSecret(secret: Secret) {
  const key = await importPKCS8(await secret("siwa_key"), "ES256");
  return await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: await secret("siwa_key_id") })
    .setIssuer(TEAM).setSubject(APPLE_CLIENT_ID).setAudience(APPLE_ISSUER)
    .setIssuedAt().setExpirationTime("1h").sign(key);
}

/// Trades the one-time authorization code for a refresh token, which `account` needs to revoke the Apple ID on
/// deletion. Null when Apple refuses: signing in never depends on it.
export async function refreshToken(code: string, secret: Secret): Promise<string | null> {
  try {
    const res = await fetch(`${APPLE_ISSUER}/auth/token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID, client_secret: await clientSecret(secret), code, grant_type: "authorization_code",
      }),
    });
    const body = await res.json().catch(() => ({})) as { refresh_token?: string; error?: string };
    if (!res.ok || !body.refresh_token) {
      console.error(`apple token ${res.status}: ${body.error ?? "no refresh_token"}`);
      return null;
    }
    return body.refresh_token;
  } catch (e) {
    console.error("apple token", e);
    return null;
  }
}

/// Disconnects the Apple ID from Ataste (guideline 5.1.1(v)). Says whether Apple accepted it.
export async function revoke(token: string, secret: Secret): Promise<boolean> {
  try {
    const res = await fetch(`${APPLE_ISSUER}/auth/revoke`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID, client_secret: await clientSecret(secret), token, token_type_hint: "refresh_token",
      }),
    });
    if (!res.ok) console.error(`apple revoke ${res.status}: ${await res.text().catch(() => "")}`);
    return res.ok;
  } catch (e) {
    console.error("apple revoke", e);
    return false;
  }
}
