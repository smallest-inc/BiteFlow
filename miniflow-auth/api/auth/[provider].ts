import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getProvider, getCredentials } from "../../lib/providers";
import { randomBytes, createHash } from "crypto";

export default function handler(req: VercelRequest, res: VercelResponse) {
  const { provider: providerName } = req.query;
  if (typeof providerName !== "string") {
    return res.status(400).json({ error: "Missing provider" });
  }

  const provider = getProvider(providerName);
  if (!provider) {
    return res.status(404).json({ error: `Unknown provider: ${providerName}` });
  }

  const { clientId } = getCredentials(provider);
  if (!clientId) {
    return res
      .status(500)
      .json({ error: `${providerName} not configured on server` });
  }

  const port = (req.query.port as string) || "8080";
  const state = (req.query.state as string) || randomBytes(16).toString("hex");

  // Build the proxy's own callback URL
  const proxyOrigin = `https://${req.headers.host}`;
  const redirectUri = `${proxyOrigin}/api/callback/${providerName}`;

  const params = new URLSearchParams();
  params.set("client_id", clientId);
  params.set("redirect_uri", redirectUri);
  params.set("response_type", "code");

  if (provider.scopes.length > 0) {
    params.set("scope", provider.scopes.join(" "));
  }

  // PKCE: generate code_verifier and challenge, pass verifier via state
  let codeVerifier: string | undefined;
  if (provider.usePkce) {
    codeVerifier = randomBytes(32).toString("base64url");
    const challenge = createHash("sha256")
      .update(codeVerifier)
      .digest("base64url");
    params.set("code_challenge", challenge);
    params.set("code_challenge_method", "S256");
  }

  // Encode port + verifier + original state into the OAuth state param
  const statePayload = JSON.stringify({
    port,
    state,
    cv: codeVerifier || "",
  });
  params.set(
    "state",
    Buffer.from(statePayload).toString("base64url")
  );

  // Provider-specific extra params
  if (provider.extraAuthParams) {
    for (const [key, value] of Object.entries(provider.extraAuthParams)) {
      params.set(key, value);
    }
  }

  const authUrl = `${provider.authUrl}?${params.toString()}`;
  res.redirect(302, authUrl);
}
