// codex-adapter: OpenAI Responses API (/v1/responses) -> OpenAI Chat Completions (New API)
//
// ENV:
//   NEW_API_BASE_URL   default http://127.0.0.1:3000
//   PORT               default 3001
//   DEBUG_PAYLOAD=1    log ringkasan pesan + dump payload akhir ke /tmp/codex-adapter-<reqId>.json
//   DEFAULT_MODEL      default meng/deepseek-v4-flash-0731

const NEW_API_BASE_URL = process.env.NEW_API_BASE_URL || "http://127.0.0.1:3000";
const PORT = Number(process.env.PORT || 3001);
const DEBUG = process.env.DEBUG_PAYLOAD === "1";
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || "meng/deepseek-v4-flash-0731";

type ChatMsg = {
  role: string;
  content: any;
  tool_calls?: any[];
  tool_call_id?: string;
  name?: string;
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

const uid = (prefix: string) =>
  `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;

// ---------- Konversi input ----------

function normalizeRole(role: any): string {
  const r = String(role || "user").toLowerCase();
  if (r === "developer") return "system";
  return r;
}

/** Ubah content Responses (string | array of parts) jadi string untuk chat completions. */
function partsToText(content: any): string {
  if (content == null) return "";
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((c) => {
        if (typeof c === "string") return c;
        if (!c || typeof c !== "object") return "";
        switch (c.type) {
          case "input_text":
          case "output_text":
          case "text":
          case "summary_text":
            return c.text ?? "";
          case "refusal":
            return c.refusal ?? "";
          case "input_image":
          case "image_url":
            return ""; // gambar diabaikan (DeepSeek text-only)
          default:
            return c.text ?? c.input_text ?? "";
        }
      })
      .filter((s) => s !== "")
      .join("\n");
  }
  if (typeof content === "object") return JSON.stringify(content);
  return String(content);
}

function makeToolCall(item: any) {
  return {
    id: item.call_id || item.id || uid("call"),
    type: "function",
    function: {
      name: item.name || item.function?.name || "",
      arguments:
        typeof item.arguments === "string"
          ? item.arguments
          : JSON.stringify(item.arguments ?? item.function?.arguments ?? {}),
    },
  };
}

function convertInputToMessages(body: any): ChatMsg[] {
  const out: ChatMsg[] = [];

  const pushAssistantToolCall = (tc: any) => {
    const last = out[out.length - 1];
    if (last && last.role === "assistant" && Array.isArray(last.tool_calls)) {
      last.tool_calls.push(tc);
      return;
    }
    out.push({ role: "assistant", content: null, tool_calls: [tc] });
  };

  if (Array.isArray(body.messages) && body.messages.length > 0) {
    // Sudah format chat completions — normalisasi role saja
    for (const m of body.messages) {
      if (!m || typeof m !== "object") continue;
      out.push({
        ...m,
        role: normalizeRole(m.role),
        content: Array.isArray(m.content) && m.role !== "user" ? partsToText(m.content) : m.content,
      });
    }
  } else if (typeof body.input === "string") {
    out.push({ role: "user", content: body.input });
  } else if (Array.isArray(body.input)) {
    for (const item of body.input) {
      if (typeof item === "string") {
        out.push({ role: "user", content: item });
        continue;
      }
      if (!item || typeof item !== "object") continue;

      // Item gaya chat completions yang nyasar ke input[]
      if (Array.isArray(item.tool_calls) && item.tool_calls.length) {
        out.push({
          role: "assistant",
          content: partsToText(item.content) || null,
          tool_calls: item.tool_calls.map(makeToolCall),
        });
        continue;
      }
      if (item.tool_call_id) {
        out.push({ role: "tool", tool_call_id: item.tool_call_id, content: partsToText(item.content ?? item.output) });
        continue;
      }

      const type = item.type || (item.role ? "message" : "");
      switch (type) {
        case "message":
          out.push({
            role: normalizeRole(item.role),
            content: partsToText(item.content ?? item.text),
          });
          break;

        case "function_call":
          pushAssistantToolCall(makeToolCall(item));
          break;

        case "function_call_output":
          out.push({
            role: "tool",
            tool_call_id: item.call_id || "",
            content: partsToText(item.output),
          });
          break;

        case "reasoning":
        case "item_reference":
          // jangan kirim balik reasoning ke model
          break;

        default:
          out.push({ role: normalizeRole(item.role), content: partsToText(item.content ?? item.text ?? item) });
      }
    }
  }

  if (typeof body.instructions === "string" && body.instructions.trim()) {
    if (!out.some((m) => m.role === "system")) {
      out.unshift({ role: "system", content: body.instructions });
    }
  }

  // Buang pesan user/assistant yang benar-benar kosong (tanpa tool_calls) —
  // pesan kosong di akhir bikin sebagian model langsung EOS.
  return out.filter((m) => {
    if (m.role === "tool" || m.role === "system") return true;
    if (Array.isArray(m.tool_calls) && m.tool_calls.length) return true;
    return typeof m.content === "string" ? m.content.trim() !== "" : m.content != null;
  });
}

// ---------- Konversi tools ----------

function convertTools(tools: any): any[] | undefined {
  if (!Array.isArray(tools)) return undefined;
  const res: any[] = [];
  for (const t of tools) {
    if (!t || typeof t !== "object") continue;
    // sudah format chat completions
    if (t.type === "function" && t.function && typeof t.function === "object") {
      res.push({ type: "function", function: t.function });
      continue;
    }
    // format Responses (flat)
    if ((t.type === "function" || !t.type) && t.name) {
      res.push({
        type: "function",
        function: {
          name: t.name,
          description: t.description || "",
          parameters: t.parameters || { type: "object", properties: {} },
        },
      });
      continue;
    }
    // web_search, file_search, computer_use, dll — tidak ada padanan di chat completions
  }
  return res.length ? res : undefined;
}

function convertToolChoice(tc: any): any {
  if (tc == null) return undefined;
  if (typeof tc === "string") return tc; // auto | none | required
  if (typeof tc === "object") {
    if (tc.type === "function") {
      const name = tc.name || tc.function?.name;
      return name ? { type: "function", function: { name } } : undefined;
    }
    if (tc.type === "allowed_tools") return tc.mode === "required" ? "required" : "auto";
  }
  return undefined;
}

// ---------- Usage ----------

function toResponsesUsage(u: any) {
  const input = u?.input_tokens ?? u?.prompt_tokens ?? 0;
  const output = u?.output_tokens ?? u?.completion_tokens ?? 0;
  return {
    input_tokens: input,
    output_tokens: output,
    total_tokens: u?.total_tokens ?? input + output,
    input_tokens_details: { cached_tokens: u?.prompt_tokens_details?.cached_tokens ?? 0 },
    output_tokens_details: { reasoning_tokens: u?.completion_tokens_details?.reasoning_tokens ?? 0 },
  };
}

// ---------- Server ----------

Bun.serve({
  port: PORT,
  hostname: "127.0.0.1",
  async fetch(req) {
    const reqId = Math.random().toString(36).substring(2, 7).toUpperCase();
    const startTime = Date.now();

    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json", ...CORS },
      });
    }

    try {
      const rawHeader =
        req.headers.get("authorization") || req.headers.get("api-key") || req.headers.get("x-api-key") || "";
      const cleanToken = rawHeader.replace(/^bearer\s+/i, "").replace(/["']/g, "").trim();
      const authHeader = cleanToken ? `Bearer ${cleanToken}` : "";

      let body: any = {};
      try {
        body = await req.json();
      } catch (e: any) {
        console.error(`[${reqId}][ERROR] Failed to parse JSON body:`, e.message);
        return new Response(JSON.stringify({ error: "Invalid JSON Body" }), {
          status: 400,
          headers: { "Content-Type": "application/json", ...CORS },
        });
      }

      const targetModel = body.model || DEFAULT_MODEL;
      const isStream = body.stream !== false;
      const chatMessages = convertInputToMessages(body);
      const tools = convertTools(body.tools);
      const toolChoice = tools ? convertToolChoice(body.tool_choice) : undefined;

      // Payload whitelist — jangan spread body, biar param Responses (reasoning, text, store, include, dll) tidak bocor
      const payload: Record<string, any> = {
        model: targetModel,
        messages: chatMessages,
        stream: isStream,
      };
      if (tools) payload.tools = tools;
      if (toolChoice) payload.tool_choice = toolChoice;
      if (typeof body.parallel_tool_calls === "boolean" && tools) payload.parallel_tool_calls = body.parallel_tool_calls;
      if (typeof body.temperature === "number") payload.temperature = body.temperature;
      if (typeof body.top_p === "number") payload.top_p = body.top_p;
      const tokenLimit = body.max_tokens || body.max_output_tokens || body.max_completion_tokens;
      if (tokenLimit) payload.max_tokens = tokenLimit;
      if (isStream) payload.stream_options = { include_usage: true };
      if (body.user) payload.user = body.user;

      const inputCount = Array.isArray(body.input) ? body.input.length : body.input ? 1 : 0;
      console.log(
        `[${reqId}][INCOMING] Model: ${targetModel} | Stream: ${isStream} | Input items: ${inputCount} | Messages: ${chatMessages.length} | Tools: ${Array.isArray(body.tools) ? body.tools.length : 0} -> ${tools?.length ?? 0}`
      );

      if (DEBUG) {
        const summary = chatMessages
          .map((m) => {
            const len = typeof m.content === "string" ? m.content.length : m.content == null ? 0 : JSON.stringify(m.content).length;
            const tc = m.tool_calls ? `+${m.tool_calls.length}tc` : "";
            return `${m.role}(${len}${tc})`;
          })
          .join(" ");
        console.log(`[${reqId}][DEBUG MSGS] ${summary}`);
        const dumpPath = `/tmp/codex-adapter-${reqId}.json`;
        await Bun.write(dumpPath, JSON.stringify(payload, null, 2));
        console.log(`[${reqId}][DEBUG] payload dumped to ${dumpPath}`);
      }

      if (chatMessages.length === 0) {
        return new Response(JSON.stringify({ error: { message: "No messages after conversion", type: "invalid_request_error" } }), {
          status: 400,
          headers: { "Content-Type": "application/json", ...CORS },
        });
      }

      const upstreamRes = await fetch(`${NEW_API_BASE_URL}/v1/chat/completions`, {
        method: "POST",
        headers: { Authorization: authHeader, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!upstreamRes.ok) {
        const errText = await upstreamRes.text();
        console.error(`[${reqId}][UPSTREAM HTTP ${upstreamRes.status}] Duration: ${Date.now() - startTime}ms | Response: ${errText.slice(0, 500)}`);
        return new Response(errText, {
          status: upstreamRes.status,
          headers: { "Content-Type": "application/json", ...CORS },
        });
      }

      console.log(`[${reqId}][UPSTREAM 200 OK] TTFB: ${Date.now() - startTime}ms`);

      const responseId = uid("resp");
      const messageItemId = uid("msg");
      const createdAt = Math.floor(Date.now() / 1000);

      const baseResponse = (status: string, output: any[], usage?: any) => ({
        id: responseId,
        object: "response",
        created_at: createdAt,
        status,
        model: targetModel,
        output,
        usage: toResponsesUsage(usage),
      });

      // ---------- Non-stream ----------
      if (!isStream) {
        const data: any = await upstreamRes.json();
        if (DEBUG) console.log(`[${reqId}][NON-STREAM DATA]`, JSON.stringify(data).slice(0, 400));
        if (data.error) {
          console.error(`[${reqId}][UPSTREAM ERROR BODY]`, JSON.stringify(data.error).slice(0, 400));
          return new Response(JSON.stringify(data), { status: 502, headers: { "Content-Type": "application/json", ...CORS } });
        }
        const choice = data.choices?.[0]?.message || {};
        const outputItems: any[] = [];

        if (typeof choice.content === "string" && choice.content.length) {
          outputItems.push({
            id: messageItemId,
            type: "message",
            status: "completed",
            role: "assistant",
            content: [{ type: "output_text", text: choice.content, annotations: [] }],
          });
        }

        if (Array.isArray(choice.tool_calls)) {
          for (const tc of choice.tool_calls) {
            const id = tc.id || uid("call");
            outputItems.push({
              id: `fc_${id}`,
              type: "function_call",
              name: tc.function?.name || "",
              call_id: id,
              arguments: tc.function?.arguments || "{}",
              status: "completed",
            });
          }
        }

        console.log(
          `[${reqId}][COMPLETED] Total Time: ${Date.now() - startTime}ms | Text Len: ${choice.content?.length ?? 0} | Tool calls: ${choice.tool_calls?.length ?? 0}`
        );
        if (outputItems.length === 0) console.warn(`[${reqId}][EMPTY RESPONSE] upstream returned no content/tool_calls — check New API log`);

        return new Response(JSON.stringify(baseResponse("completed", outputItems, data.usage)), {
          headers: { "Content-Type": "application/json", ...CORS },
        });
      }

      // ---------- Stream ----------
      const encoder = new TextEncoder();
      const decoder = new TextDecoder();
      let buffer = "";
      let fullText = "";
      let reasoningLen = 0;
      let textItemStarted = false;
      let chunkCount = 0;
      let seq = 0;
      let upstreamUsage: any = null;
      let upstreamError: any = null;
      let nextOutputIndex = 0;

      const toolCallsMap: Record<number, { id: string; name: string; arguments: string; started: boolean; outputIndex: number }> = {};

      const sendEvent = (event: string, data: Record<string, any>) =>
        encoder.encode(`event: ${event}\ndata: ${JSON.stringify({ type: event, sequence_number: seq++, ...data })}\n\n`);

      const transformStream = new TransformStream({
        start(controller) {
          controller.enqueue(sendEvent("response.created", { response: baseResponse("in_progress", []) }));
          controller.enqueue(sendEvent("response.in_progress", { response: baseResponse("in_progress", []) }));
        },
        transform(chunk, controller) {
          buffer += decoder.decode(chunk, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || !trimmed.startsWith("data:")) continue;
            const dataStr = trimmed.replace(/^data:\s*/, "");
            if (dataStr === "[DONE]") continue;

            chunkCount++;
            if (chunkCount === 1 && DEBUG) console.log(`[${reqId}][FIRST RAW CHUNK]:`, dataStr.slice(0, 300));

            let parsed: any;
            try {
              parsed = JSON.parse(dataStr);
            } catch {
              console.warn(`[${reqId}][CHUNK PARSE WARN]:`, dataStr.slice(0, 80));
              continue;
            }

            if (parsed.error) {
              upstreamError = parsed.error;
              console.error(`[${reqId}][IN-STREAM ERROR]:`, JSON.stringify(parsed.error).slice(0, 400));
              continue;
            }
            if (parsed.usage) upstreamUsage = parsed.usage;

            const delta = parsed.choices?.[0]?.delta;
            if (!delta) continue;

            if (delta.reasoning_content) reasoningLen += delta.reasoning_content.length;

            const textChunk = delta.content || "";
            if (textChunk) {
              if (!textItemStarted) {
                textItemStarted = true;
                const outputIndex = nextOutputIndex++;
                controller.enqueue(
                  sendEvent("response.output_item.added", {
                    output_index: outputIndex,
                    item: { id: messageItemId, type: "message", status: "in_progress", role: "assistant", content: [] },
                  })
                );
                controller.enqueue(
                  sendEvent("response.content_part.added", {
                    item_id: messageItemId,
                    output_index: outputIndex,
                    content_index: 0,
                    part: { type: "output_text", text: "", annotations: [] },
                  })
                );
              }
              fullText += textChunk;
              controller.enqueue(
                sendEvent("response.output_text.delta", {
                  item_id: messageItemId,
                  output_index: 0,
                  content_index: 0,
                  delta: textChunk,
                })
              );
            }

            if (Array.isArray(delta.tool_calls)) {
              for (const tc of delta.tool_calls) {
                const idx = tc.index ?? 0;
                if (!toolCallsMap[idx]) {
                  toolCallsMap[idx] = { id: tc.id || uid("call"), name: tc.function?.name || "", arguments: "", started: false, outputIndex: -1 };
                }
                const cur = toolCallsMap[idx];
                if (tc.id) cur.id = tc.id;
                if (tc.function?.name) cur.name = tc.function.name;

                if (!cur.started && cur.name) {
                  cur.started = true;
                  cur.outputIndex = nextOutputIndex++;
                  console.log(`[${reqId}][TOOL CALL STARTED] Index: ${idx} | Function: ${cur.name}`);
                  controller.enqueue(
                    sendEvent("response.output_item.added", {
                      output_index: cur.outputIndex,
                      item: { id: `fc_${cur.id}`, type: "function_call", name: cur.name, call_id: cur.id, arguments: "", status: "in_progress" },
                    })
                  );
                }

                if (tc.function?.arguments) {
                  cur.arguments += tc.function.arguments;
                  if (cur.started) {
                    controller.enqueue(
                      sendEvent("response.function_call_arguments.delta", {
                        item_id: `fc_${cur.id}`,
                        output_index: cur.outputIndex,
                        delta: tc.function.arguments,
                      })
                    );
                  }
                }
              }
            }
          }
        },
        flush(controller) {
          const finalOutputItems: any[] = [];

          if (textItemStarted) {
            const textObj = {
              id: messageItemId,
              type: "message",
              status: "completed",
              role: "assistant",
              content: [{ type: "output_text", text: fullText, annotations: [] }],
            };
            finalOutputItems.push(textObj);
            controller.enqueue(sendEvent("response.output_text.done", { item_id: messageItemId, output_index: 0, content_index: 0, text: fullText }));
            controller.enqueue(
              sendEvent("response.content_part.done", {
                item_id: messageItemId,
                output_index: 0,
                content_index: 0,
                part: { type: "output_text", text: fullText, annotations: [] },
              })
            );
            controller.enqueue(sendEvent("response.output_item.done", { output_index: 0, item: textObj }));
          }

          const tools = Object.keys(toolCallsMap)
            .map((k) => toolCallsMap[Number(k)])
            .filter((t) => t.started)
            .sort((a, b) => a.outputIndex - b.outputIndex);

          for (const tc of tools) {
            const toolObj = { id: `fc_${tc.id}`, type: "function_call", name: tc.name, call_id: tc.id, arguments: tc.arguments || "{}", status: "completed" };
            finalOutputItems.push(toolObj);
            controller.enqueue(
              sendEvent("response.function_call_arguments.done", { item_id: `fc_${tc.id}`, output_index: tc.outputIndex, arguments: toolObj.arguments })
            );
            controller.enqueue(sendEvent("response.output_item.done", { output_index: tc.outputIndex, item: toolObj }));
          }

          if (upstreamError && finalOutputItems.length === 0) {
            controller.enqueue(
              sendEvent("response.failed", {
                response: { ...baseResponse("failed", [], upstreamUsage), error: { code: "server_error", message: upstreamError.message || JSON.stringify(upstreamError) } },
              })
            );
          } else {
            controller.enqueue(sendEvent("response.completed", { response: baseResponse("completed", finalOutputItems, upstreamUsage) }));
          }

          console.log(
            `[${reqId}][COMPLETED] Total Time: ${Date.now() - startTime}ms | Chunks: ${chunkCount} | Text Len: ${fullText.length} | Reasoning Len: ${reasoningLen} | Tool calls: ${tools.length} | Usage: ${
              upstreamUsage ? `${upstreamUsage.prompt_tokens}/${upstreamUsage.completion_tokens}` : "n/a"
            }`
          );
          if (finalOutputItems.length === 0) {
            console.warn(`[${reqId}][EMPTY RESPONSE] upstream returned no content/tool_calls — check New API log for this request`);
          }
        },
      });

      return new Response(upstreamRes.body?.pipeThrough(transformStream), {
        headers: {
          "Content-Type": "text/event-stream; charset=utf-8",
          "Cache-Control": "no-cache, no-transform",
          Connection: "keep-alive",
          "X-Accel-Buffering": "no",
          ...CORS,
        },
      });
    } catch (err: any) {
      console.error(`[${reqId}][CRITICAL ERROR]`, err.stack || err.message);
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: { "Content-Type": "application/json", ...CORS },
      });
    }
  },
});

console.log(`Bun Adapter running on http://127.0.0.1:${PORT} -> ${NEW_API_BASE_URL}`);
