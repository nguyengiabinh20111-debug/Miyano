const TTL_MS = 30 * 60 * 1000; // Tự xoá tin nhắn cũ hơn 30 phút
const MAX_MESSAGES = 100;
const KV_KEY = "hirose_miyano_messages";
const COUNTER_KEY = "hirose_miyano_seq";

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
  const nowMs = Date.now();

  const valid = list.filter((item) => {
    if (!item || typeof item !== "object") return false;
    const tsMs = typeof item.ts === "number"
      ? item.ts
      : (typeof item.time === "number" ? item.time * 1000 : nowMs);
    return nowMs - tsMs <= TTL_MS;
  });

  if (valid.length !== list.length) {
    await env.CHAT_KV.put(KV_KEY, JSON.stringify(valid));
  }

  return valid;
}

async function nextNumericId(env) {
  const currentRaw = await env.CHAT_KV.get(COUNTER_KEY);
  const currentNum = Number(currentRaw) || 0;
  const nextNum = currentNum + 1;
  await env.CHAT_KV.put(COUNTER_KEY, String(nextNum));
  return nextNum;
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
        const afterParam = Number(url.searchParams.get("after") || "0") || 0;
        const allMessages = await loadAndCleanMessages(env);
        const filtered = afterParam > 0
          ? allMessages.filter((m) => (Number(m.id) || 0) > afterParam)
          : allMessages;

        return jsonResponse({ ok: true, messages: filtered });
      }

      if (request.method === "POST" && path === "/send") {
        let body = {};
        try {
          body = await request.json();
        } catch {
          return jsonResponse({ ok: false, error: "Invalid JSON" }, 400);
        }

        const userName = String(
          body.user || body.sender || body.displayName || body.username || "Player"
        )
          .trim()
          .slice(0, 40);

        const text = String(body.text || body.message || body.content || "")
          .trim()
          .slice(0, 200);

        if (!text) {
          return jsonResponse({ ok: false, error: "Message text is required" }, 400);
        }

        const nowMs = Date.now();
        const nowSec = typeof body.time === "number" && body.time > 0
          ? Math.floor(body.time)
          : Math.floor(nowMs / 1000);

        const numericId = await nextNumericId(env);
        const messages = await loadAndCleanMessages(env);

        const newMsg = {
          id: numericId,
          user: userName || "Player",
          sender: userName || "Player",
          displayName: String(body.displayName || userName || "Player").trim().slice(0, 40),
          userId: Number(body.userId) || 0,
          text,
          time: nowSec,
          ts: nowMs,
          server: String(body.server || "Global").slice(0, 24),
        };

        messages.push(newMsg);
        const trimmed = messages.slice(-MAX_MESSAGES);
        await env.CHAT_KV.put(KV_KEY, JSON.stringify(trimmed));

        return jsonResponse({ ok: true, message: newMsg }, 201);
      }

      if (request.method === "POST" && path === "/ping") {
        return jsonResponse({ ok: true, users: [] });
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
