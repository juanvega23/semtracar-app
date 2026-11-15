import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };
  const base64url = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const signingInput = `${base64url(header)}.${base64url(payload)}`;
  const privateKey = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");
  const binaryKey = Uint8Array.from(atob(privateKey), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cryptoKey,
    new TextEncoder().encode(signingInput)
  );
  const signatureBase64url = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const jwt = `${signingInput}.${signatureBase64url}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) throw new Error("No se pudo obtener access token");
  return tokenData.access_token;
}

async function sendFCM(accessToken: string, token: string, title: string, body: string) {
  return fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          android: { priority: "high", notification: { channel_id: "nica_cargo_channel" } },
        },
      }),
    }
  );
}

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const payload = await req.json();

    // ── Caso 1: envío directo desde la app (delivery / repartidor) ────────────
    if (payload.title) {
      // Seguridad: solo usuarios autenticados de la app pueden enviar.
      // El SDK de Flutter manda el JWT de la sesión en Authorization.
      const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
      const { data: userData, error: authError } = await supabase.auth.getUser(jwt);
      if (authError || !userData?.user) {
        return new Response(JSON.stringify({ error: "No autorizado" }), {
          status: 401, headers: { "Content-Type": "application/json" },
        });
      }

      const accessToken = await getAccessToken();
      const { title, body, user_ids, role } = payload;
      let q = supabase.from("user_push_tokens").select("token");
      if (user_ids?.length > 0) {
        q = q.in("user_id", user_ids);
      } else if (role) {
        const { data: users } = await supabase.from("users").select("id").eq("role", role).eq("is_available", true);
        const ids = (users ?? []).map((u: any) => u.id);
        if (!ids.length) return new Response(JSON.stringify({ sent: 0 }));
        q = q.in("user_id", ids);
      }
      const { data: tokens } = await q;
      if (!tokens?.length) return new Response(JSON.stringify({ sent: 0 }));
      const results = await Promise.all(
        tokens.map(({ token }: { token: string }) =>
          sendFCM(accessToken, token, title, body).then(r => r.ok)
        )
      );
      return new Response(JSON.stringify({ sent: results.filter(Boolean).length }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── Caso 2: webhook de estado de paquete ──────────────────────────────────
    // Seguridad: solo el webhook de la BD conoce este secreto.
    const secret = req.headers.get("x-webhook-secret");
    if (!secret || secret !== Deno.env.get("WEBHOOK_SECRET")) {
      return new Response(JSON.stringify({ error: "No autorizado" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    const { record } = payload;

    const { data: packageData } = await supabase
      .from("packages").select("user_id, tracking_code")
      .eq("id", record.package_id).single();
    if (!packageData) throw new Error("Paquete no encontrado");

    const { data: statusData } = await supabase
      .from("status_types").select("name")
      .eq("id", record.status_id).single();

    const { data: tokenData } = await supabase
      .from("user_push_tokens").select("token")
      .eq("user_id", packageData.user_id).single();
    if (!tokenData) throw new Error("Token FCM no encontrado");

    const accessToken = await getAccessToken();
    const fcmResult = await sendFCM(
      accessToken,
      tokenData.token,
      "Semtracar",
      `Tu paquete ${packageData.tracking_code} está: ${statusData?.name ?? "Actualizado"}`
    );

    return new Response(JSON.stringify({ success: true, result: await fcmResult.json() }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
