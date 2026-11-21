const TTL_MS = 30 * 60 * 1000; // Tự xoá tin nhắn cũ hơn 30 phút
const MAX_MESSAGES = 100;
const KV_KEY = "hirose_miyano_messages";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
    },
  });
}

async function loadAndCleanMessages(env) {
  if (!env.CHAT_KV) {
    throw new Error("Missing CHAT_KV binding");
  }

  const raw = await env.CHAT_KV.get(KV_KEY, { type: "json" });
  const list = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  const valid = list.filter((item) => item && typeof item.ts === "number" && now - item.ts <= TTL_MS);

  if (valid.length !== list.length) {
    await env.CHAT_KV.put(KV_KEY, JSON.stringify(valid));
  }

  return valid;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (request.method === "GET" && (path === "/" || path === "/health")) {
        return jsonResponse({ ok: true, service: "hirose-miyano-chat" });
      }

      if (request.method === "GET" && path === "/messages") {
        const messages = await loadAndCleanMessages(env);
        return jsonResponse({ ok: true, messages });
      }

      if (request.method === "POST" && path === "/send") {
        let body = {};
        try {
          body = await request.json();
        } catch {
          return jsonResponse({ ok: false, error: "Invalid JSON" }, 400);
        }

        const sender = String(body.sender || body.user || body.username || "Member")
          .trim()
          .slice(0, 40);
        const text = String(body.text || body.message || body.content || "")
          .trim()
          .slice(0, 500);

        if (!text) {
          return jsonResponse({ ok: false, error: "Message text is required" }, 400);
        }

        const messages = await loadAndCleanMessages(env);
        const newMsg = {
          id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
          sender: sender || "Member",
          text,
          ts: Date.now(),
        };

        messages.push(newMsg);
        const trimmed = messages.slice(-MAX_MESSAGES);
        await env.CHAT_KV.put(KV_KEY, JSON.stringify(trimmed));

        return jsonResponse({ ok: true, message: newMsg }, 201);
      }

      return jsonResponse({ ok: false, error: "Not Found" }, 404);
    } catch (err) {
      return jsonResponse(
        { ok: false, error: err && err.message ? err.message : "Internal Server Error" },
        500
      );
    }
  },
};
