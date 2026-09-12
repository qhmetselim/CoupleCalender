import "@supabase/functions-js/edge-runtime.d.ts";

const JSON_HEADERS = { "Content-Type": "application/json" };
const NOTIFICATION_TYPE = "memory_created";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type DatabaseWebhookPayload = {
  type?: string;
  table?: string;
  schema?: string;
  record?: {
    id?: string;
    owner_id?: string;
    calendar_day?: string;
  } | null;
};

type DeviceToken = {
  token: string;
  environment: "development" | "production";
};

type DeliveryClaim = { id: string };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function getSecretKey(): string | undefined {
  const configuredSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (configuredSecretKeys) {
    try {
      const keys = JSON.parse(configuredSecretKeys) as Record<string, string>;
      if (keys.default) return keys.default;
    } catch {
      // Fall back to the legacy variable below when the JSON secret is absent.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
}

function apiHeaders(secretKey: string, extra: HeadersInit = {}): Headers {
  return new Headers({ apikey: secretKey, Authorization: `Bearer ${secretKey}`, ...extra });
}

async function restRequest<T>(
  baseURL: string,
  secretKey: string,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(`${baseURL}/rest/v1/${path}`, {
    ...init,
    headers: apiHeaders(secretKey, init.headers),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Supabase REST request failed (${response.status}): ${details.slice(0, 240)}`);
  }

  if (response.status === 204) return undefined as T;
  return await response.json() as T;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function base64URL(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
}

async function createAPNsJWT(): Promise<string> {
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replaceAll("\\n", "\n");
  if (!keyID || !teamID || !privateKey) throw new Error("APNs credentials are not configured");

  const header = base64URL(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: keyID })));
  const payload = base64URL(
    new TextEncoder().encode(JSON.stringify({ iss: teamID, iat: Math.floor(Date.now() / 1000) })),
  );
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64URL(new Uint8Array(signature))}`;
}

async function sendAPNsNotification(
  token: DeviceToken,
  memoryID: string,
  calendarDay: string,
  calendarOwnerID: string,
): Promise<{ status: number; reason?: string }> {
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  if (!bundleID) throw new Error("APNS_BUNDLE_ID is not configured");

  const jwt = await createAPNsJWT();
  const host = token.environment === "development"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const response = await fetch(`${host}/3/device/${encodeURIComponent(token.token)}`, {
    method: "POST",
    headers: {
      Authorization: `bearer ${jwt}`,
      "apns-topic": bundleID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: {
          title: "Yeni bir anı 💌",
          body: "Partnerin takvimine yeni bir anı ekledi.",
        },
        sound: "default",
      },
      type: NOTIFICATION_TYPE,
      memory_id: memoryID,
      calendar_day: calendarDay,
      calendar_owner_id: calendarOwnerID,
    }),
  });

  let reason: string | undefined;
  try {
    const responseBody = await response.json() as { reason?: string };
    reason = responseBody.reason;
  } catch {
    // APNs commonly returns an empty body on success.
  }
  return { status: response.status, reason };
}

async function findPartnerID(baseURL: string, secretKey: string, ownerID: string): Promise<string | undefined> {
  const query = new URLSearchParams({
    select: "member_a_id,member_b_id",
    status: "eq.active",
    or: `(member_a_id.eq.${ownerID},member_b_id.eq.${ownerID})`,
    limit: "1",
  });
  const couples = await restRequest<Array<{ member_a_id: string; member_b_id: string | null }>>(
    baseURL,
    secretKey,
    `couples?${query.toString()}`,
  );
  const couple = couples[0];
  if (!couple) return undefined;
  return couple.member_a_id === ownerID ? couple.member_b_id ?? undefined : couple.member_a_id;
}

async function claimDelivery(
  baseURL: string,
  secretKey: string,
  memoryID: string,
  recipientUserID: string,
  token: DeviceToken,
): Promise<DeliveryClaim | undefined> {
  const deviceTokenHash = await sha256Hex(token.token);
  const response = await fetch(`${baseURL}/rest/v1/notification_deliveries`, {
    method: "POST",
    headers: apiHeaders(secretKey, {
      "Content-Type": "application/json",
      Prefer: "return=representation,resolution=ignore-duplicates",
    }),
    body: JSON.stringify({
      memory_id: memoryID,
      notification_type: NOTIFICATION_TYPE,
      recipient_user_id: recipientUserID,
      device_token_hash: deviceTokenHash,
      environment: token.environment,
      status: "pending",
      attempt_count: 1,
    }),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Delivery claim failed (${response.status}): ${details.slice(0, 240)}`);
  }

  const claims = await response.json() as DeliveryClaim[];
  return claims[0];
}

async function updateDelivery(
  baseURL: string,
  secretKey: string,
  deliveryID: string,
  values: Record<string, unknown>,
): Promise<void> {
  await restRequest(baseURL, secretKey, `notification_deliveries?id=eq.${deliveryID}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(values),
  });
}

async function removeInvalidToken(baseURL: string, secretKey: string, token: string): Promise<void> {
  const query = new URLSearchParams({ token: `eq.${token}` });
  await restRequest(baseURL, secretKey, `device_tokens?${query.toString()}`, {
    method: "DELETE",
    headers: { Prefer: "return=minimal" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const webhookSecret = Deno.env.get("DATABASE_WEBHOOK_SECRET");
  if (!webhookSecret || request.headers.get("x-webhook-secret") !== webhookSecret) {
    return json({ error: "unauthorized" }, 401);
  }

  const baseURL = Deno.env.get("SUPABASE_URL");
  const secretKey = getSecretKey();
  if (!baseURL || !secretKey) return json({ error: "server_not_configured" }, 503);

  let payload: DatabaseWebhookPayload;
  try {
    payload = await request.json() as DatabaseWebhookPayload;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const record = payload.record;
  if (
    payload.type !== "INSERT" || payload.schema !== "public" || payload.table !== "memories" ||
    !record?.id || !record.owner_id || !record.calendar_day ||
    !UUID_PATTERN.test(record.id) || !UUID_PATTERN.test(record.owner_id) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(record.calendar_day)
  ) {
    return json({ error: "unsupported_payload" }, 400);
  }

  try {
    const partnerID = await findPartnerID(baseURL, secretKey, record.owner_id);
    if (!partnerID) return json({ delivered: 0, reason: "no_active_partner" });

    const tokenQuery = new URLSearchParams({
      select: "token,environment",
      user_id: `eq.${partnerID}`,
      platform: "eq.ios",
    });
    const tokens = await restRequest<DeviceToken[]>(baseURL, secretKey, `device_tokens?${tokenQuery.toString()}`);
    if (tokens.length === 0) return json({ delivered: 0, reason: "no_registered_devices" });

    let delivered = 0;
    for (const token of tokens) {
      const claim = await claimDelivery(baseURL, secretKey, record.id, partnerID, token);
      if (!claim) continue;

      try {
        const result = await sendAPNsNotification(token, record.id, record.calendar_day, record.owner_id);
        const invalid = result.status === 400 || result.status === 410;
        if (result.status === 200) {
          await updateDelivery(baseURL, secretKey, claim.id, {
            status: "sent",
            apns_status: result.status,
            last_error: null,
          });
          delivered += 1;
        } else {
          await updateDelivery(baseURL, secretKey, claim.id, {
            status: invalid ? "invalid_token" : "failed",
            apns_status: result.status,
            last_error: result.reason ?? "APNs request failed",
          });
          if (invalid) await removeInvalidToken(baseURL, secretKey, token.token);
        }
      } catch (error) {
        await updateDelivery(baseURL, secretKey, claim.id, {
          status: "failed",
          last_error: error instanceof Error ? error.message.slice(0, 500) : "APNs request failed",
        });
      }
    }

    return json({ delivered, device_count: tokens.length });
  } catch (error) {
    console.error("memory notification failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "notification_delivery_failed" }, 500);
  }
});
