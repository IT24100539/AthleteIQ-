import { ChatAnthropic } from '@langchain/anthropic';

/**
 * LangChain defaults topP/topK to -1 ("unset") and always sends temperature.
 * Claude Sonnet 5 rejects both: `top_p cannot be set to -1` and
 * `temperature is deprecated for this model`.
 */
export function createChatAnthropic(fields: {
  apiKey: string;
  maxTokens: number;
}): ChatAnthropic {
  const model = new ChatAnthropic({
    apiKey: fields.apiKey,
    model: process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-5',
    maxTokens: fields.maxTokens,
    temperature: null,
  });
  const raw = model as unknown as { topP?: number; topK?: number };
  raw.topP = undefined;
  raw.topK = undefined;
  return model;
}
