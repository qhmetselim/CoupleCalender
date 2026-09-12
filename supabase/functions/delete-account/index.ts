import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const JSON_HEADERS = { "Content-Type": "application/json" };
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function getAdminKey(): string | undefined {
  const configuredSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (configuredSecretKeys) {
    try {
      const keys = JSON.parse(configuredSecretKeys) as Record<string, string>;
      if (keys.default) return keys.default;
    } catch {
      // Fall through to the platform's legacy service-role secret.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
}

function adminHeaders(secretKey: string, extra: HeadersInit = {}): Headers {
  return new Headers({
    apikey: secretKey,
    Authorization: `Bearer ${secretKey}`,
    ...extra,
  });
}

async function resolveCallerID(
  baseURL: string,
  secretKey: string,
  authorization: string,
): Promise<string | undefined> {
  const response = await fetch(`${baseURL}/auth/v1/user`, {
    headers: {
      apikey: secretKey,
      Authorization: authorization,
    },
  });

  if (!response.ok) return undefined;

  const user = await response.json() as { id?: string };
  return user.id && UUID_PATTERN.test(user.id) ? user.id : undefined;
}

async function removeCouplesForUser(
  baseURL: string,
  secretKey: string,
  userID: string,
): Promise<void> {
  // Removing the user's couple rows first releases the profile foreign-key
  // restriction. Cascades remove memberships and private invites, while the
  // profile cascade removes the user's own memories and interaction data.
  const query = new URLSearchParams({
    or: `(member_a_id.eq.${userID},member_b_id.eq.${userID})`,
  });
  const response = await fetch(`${baseURL}/rest/v1/couples?${query.toString()}`, {
    method: "DELETE",
    headers: adminHeaders(secretKey, { Prefer: "return=minimal" }),
  });

  if (!response.ok) {
    throw new Error(`couple_cleanup_failed_${response.status}`);
  }
}

async function deleteAuthUser(
  baseURL: string,
  secretKey: string,
  userID: string,
): Promise<void> {
  const response = await fetch(`${baseURL}/auth/v1/admin/users/${encodeURIComponent(userID)}`, {
    method: "DELETE",
    headers: adminHeaders(secretKey),
  });

  if (!response.ok) {
    throw new Error(`auth_delete_failed_${response.status}`);
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const baseURL = Deno.env.get("SUPABASE_URL")?.replace(/\/+$/, "");
  const secretKey = getAdminKey();
  const authorization = request.headers.get("Authorization");
  if (!baseURL || !secretKey) {
    return json({ error: "server_not_configured" }, 503);
  }
  if (!authorization?.toLowerCase().startsWith("bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }

  const userID = await resolveCallerID(baseURL, secretKey, authorization);
  if (!userID) return json({ error: "unauthorized" }, 401);

  try {
    await removeCouplesForUser(baseURL, secretKey, userID);
    await deleteAuthUser(baseURL, secretKey, userID);
    return json({ deleted: true });
  } catch (error) {
    console.error("account_deletion_failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "account_deletion_failed" }, 500);
  }
});
