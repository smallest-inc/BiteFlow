import { createCipheriv, createDecipheriv, randomBytes } from "crypto";

const ALGO = "aes-256-gcm";

function getKey(): Buffer | null {
  const hex = process.env.ENCRYPTION_KEY || "";
  if (hex.length !== 64) return null;
  return Buffer.from(hex, "hex");
}

export function hasEncryptionKey(): boolean {
  return getKey() !== null;
}

export function encodePayload(plaintext: string): string {
  const key = getKey();
  if (!key) {
    return Buffer.from(plaintext, "utf8").toString("base64url");
  }
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALGO, key, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  const combined = Buffer.concat([iv, tag, encrypted]);
  return combined.toString("base64url");
}

export function decrypt(encoded: string): string {
  const key = getKey();
  if (!key) {
    return Buffer.from(encoded, "base64url").toString("utf8");
  }
  const combined = Buffer.from(encoded, "base64url");
  const iv = combined.subarray(0, 12);
  const tag = combined.subarray(12, 28);
  const ciphertext = combined.subarray(28);
  const decipher = createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}
