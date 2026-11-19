/**
 * Cliente da IA que lê as notificações. Fala o formato de API da OpenAI (chat/completions), que o
 * DeepSeek segue; trocar de serviço é só mudar AI_BASE_URL / AI_MODEL / AI_API_KEY no .env.
 */

export class AiError extends Error {}

export function aiConfigured(): boolean {
  return !!process.env.AI_API_KEY;
}

export async function chatJson(system: string, user: string): Promise<unknown> {
  const key = process.env.AI_API_KEY;
  if (!key) throw new AiError('IA não configurada (AI_API_KEY no .env)');
  const base = (process.env.AI_BASE_URL || 'https://api.deepseek.com').replace(/\/$/, '');
  const model = process.env.AI_MODEL || 'deepseek-flash';

  let res: Response;
  try {
    res = await fetch(`${base}/chat/completions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
      signal: AbortSignal.timeout(45_000),
    });
  } catch (e) {
    throw new AiError(`Não foi possível falar com a IA: ${(e as Error).message}`);
  }
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new AiError(`A IA respondeu ${res.status}: ${body.slice(0, 200)}`);
  }
  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new AiError('A IA não devolveu conteúdo');
  try {
    return JSON.parse(content.replace(/^```(?:json)?\s*|\s*```$/g, ''));
  } catch {
    throw new AiError(`A IA não devolveu JSON: ${content.slice(0, 200)}`);
  }
}
