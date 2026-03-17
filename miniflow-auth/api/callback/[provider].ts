import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getProvider, getCredentials } from "../../lib/providers";
import { encodePayload } from "../../lib/crypto";

export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  const { provider: providerName } = req.query;
  if (typeof providerName !== "string") {
    return res.status(400).json({ error: "Missing provider" });
  }

  const provider = getProvider(providerName);
  if (!provider) {
    return res.status(404).json({ error: `Unknown provider: ${providerName}` });
  }

  const code = req.query.code as string;
  const stateParam = req.query.state as string;

  if (!code) {
    const errorDesc =
      (req.query.error_description as string) ||
      (req.query.error as string) ||
      "Unknown error";
    return res.status(400).send(`
      <html><body style="font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f7f9fc;color:#0f1923">
        <div style="text-align:center"><h2>Connection Failed</h2><p>${errorDesc}</p></div>
      </body></html>
    `);
  }

  // Decode state to get the local port and PKCE verifier
  let port = "8080";
  let originalState = "";
  let codeVerifier = "";
  try {
    const decoded = JSON.parse(
      Buffer.from(stateParam, "base64url").toString("utf8")
    );
    port = decoded.port || "8080";
    originalState = decoded.state || "";
    codeVerifier = decoded.cv || "";
  } catch {
    // Fall back to defaults
  }

  const { clientId, clientSecret } = getCredentials(provider);
  const proxyOrigin = `https://${req.headers.host}`;
  const redirectUri = `${proxyOrigin}/api/callback/${providerName}`;

  // Exchange the authorization code for tokens
  const params = new URLSearchParams();
  params.set("grant_type", "authorization_code");
  params.set("code", code);
  params.set("redirect_uri", redirectUri);
  params.set("client_id", clientId);
  if (clientSecret) {
    params.set("client_secret", clientSecret);
  }
  if (codeVerifier) {
    params.set("code_verifier", codeVerifier);
  }

  try {
    const tokenRes = await fetch(provider.tokenUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: params.toString(),
    });

    const body = await tokenRes.json();

    // Check for errors
    if (body.error || body.ok === false) {
      const errMsg =
        body.error_description || body.error || "Token exchange failed";
      return res.status(400).send(`
        <html><body style="font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f7f9fc;color:#0f1923">
          <div style="text-align:center"><h2>Connection Failed</h2><p>${errMsg}</p></div>
        </body></html>
      `);
    }

    // Extract tokens — handle both standard OAuth and Slack V2 structure
    const accessToken =
      body.access_token || body.authed_user?.access_token || "";
    const refreshToken = body.refresh_token || "";
    const expiresIn = body.expires_in || 0;

    const tokenPayload = JSON.stringify({
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: expiresIn,
      provider: providerName,
      scopes: provider.scopes,
    });

    const encoded = encodePayload(tokenPayload);

    // Redirect to the local MiniFlow callback server
    const localUrl = `http://localhost:${port}/callback?data=${encodeURIComponent(encoded)}&state=${encodeURIComponent(originalState)}`;
    res.redirect(302, localUrl);
  } catch (err: any) {
    return res.status(500).send(`
      <html><body style="font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f7f9fc;color:#0f1923">
        <div style="text-align:center"><h2>Server Error</h2><p>${err.message || "Unknown error"}</p></div>
      </body></html>
    `);
  }
}
