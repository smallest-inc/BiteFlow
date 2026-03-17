import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getProvider, getCredentials } from "../../lib/providers";

export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { provider: providerName } = req.query;
  if (typeof providerName !== "string") {
    return res.status(400).json({ error: "Missing provider" });
  }

  const provider = getProvider(providerName);
  if (!provider) {
    return res.status(404).json({ error: `Unknown provider: ${providerName}` });
  }

  const { refresh_token: refreshToken } = req.body || {};
  if (!refreshToken) {
    return res.status(400).json({ error: "Missing refresh_token in body" });
  }

  const { clientId, clientSecret } = getCredentials(provider);

  const params = new URLSearchParams();
  params.set("grant_type", "refresh_token");
  params.set("refresh_token", refreshToken);
  params.set("client_id", clientId);
  if (clientSecret) {
    params.set("client_secret", clientSecret);
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

    if (body.error) {
      return res
        .status(400)
        .json({ error: body.error_description || body.error });
    }

    return res.json({
      access_token: body.access_token,
      refresh_token: body.refresh_token || refreshToken,
      expires_in: body.expires_in || 0,
    });
  } catch (err: any) {
    return res
      .status(500)
      .json({ error: err.message || "Token refresh failed" });
  }
}
