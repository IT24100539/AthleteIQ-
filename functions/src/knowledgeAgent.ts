/**
 * Knowledge Agent (Section 6) — RAG over a small local sports-science
 * corpus. Chunks + hashed embeddings land in LangChain's in-memory
 * vector store (Chroma would need a sidecar; this set is three short
 * notes). Retrieval is grounded; the LLM may only paraphrase retrieved
 * text and must not invent papers or numbers.
 */

import { Document } from '@langchain/core/documents';
import { HumanMessage, SystemMessage } from '@langchain/core/messages';
import { createChatAnthropic } from './anthropic';
import { Embeddings } from '@langchain/core/embeddings';
import { StringOutputParser } from '@langchain/core/output_parsers';
import { logger } from 'firebase-functions';
import * as fs from 'fs';
import { RecursiveCharacterTextSplitter } from 'langchain/text_splitter';
import { MemoryVectorStore } from 'langchain/vectorstores/memory';
import * as path from 'path';
import { RiskAssessment } from './riskModel';

export interface ResearchCitation {
  tag: string;
  text: string;
  source: string;
}

export interface ResearchNote {
  note: string;
  citations: ResearchCitation[];
  source: 'llm' | 'retrieved';
}

const EMBED_DIM = 256;

/**
 * Lightweight hashed n-gram embeddings — no extra API key or model download.
 * Distinct topic vocab (ACWR vs Banister vs session-RPE) separates cleanly
 * in this space for a corpus this small.
 */
class HashedNgramEmbeddings extends Embeddings {
  constructor() {
    super({});
  }

  async embedDocuments(texts: string[]): Promise<number[][]> {
    return texts.map((t) => this.embed(t));
  }

  async embedQuery(text: string): Promise<number[]> {
    return this.embed(text);
  }

  private embed(text: string): number[] {
    const vec = new Array<number>(EMBED_DIM).fill(0);
    const tokens = text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    for (const tok of tokens) {
      this.add(vec, tok, 1);
      const padded = `  ${tok} `;
      for (let i = 0; i < padded.length - 2; i++) {
        this.add(vec, padded.slice(i, i + 3), 0.4);
      }
    }
    const mag = Math.sqrt(vec.reduce((s, x) => s + x * x, 0)) || 1;
    return vec.map((x) => x / mag);
  }

  private add(vec: number[], key: string, weight: number): void {
    let h = 2166136261;
    for (let i = 0; i < key.length; i++) {
      h ^= key.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    vec[Math.abs(h) % EMBED_DIM] += weight;
  }
}

/** Plain SystemMessage — no ChatPromptTemplate, so JSON braces are literal. */
const RESEARCH_PROMPT = `You are AthleteIQ's Knowledge Agent. You write a short research note for a coach explaining why a risk call is scientifically grounded.

Rules:
- Use ONLY the retrieved reference notes below. Do not invent papers, authors, journals, years, or numbers.
- Keep the "note" to 1-2 sentences. Mention the ACWR controversy if any retrieved chunk discusses it.
- Return JSON only, no markdown fences:
{"note":"...","citations":[{"tag":"...","text":"...","source":"..."}]}
- citations: 1-3 items. "text" is one sentence paraphrasing a retrieved chunk. "tag" and "source" must come from the retrieved metadata (tag / source fields).`;

let storePromise: Promise<MemoryVectorStore> | null = null;

function knowledgeDir(): string {
  return path.join(__dirname, '..', 'knowledge');
}

function parseFrontmatter(raw: string): { meta: Record<string, string>; body: string } {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!match) return { meta: {}, body: raw.trim() };
  const meta: Record<string, string> = {};
  for (const line of match[1].split(/\r?\n/)) {
    const idx = line.indexOf(':');
    if (idx === -1) continue;
    meta[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return { meta, body: match[2].trim() };
}

async function loadVectorStore(): Promise<MemoryVectorStore> {
  const dir = knowledgeDir();
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.md'));
  const docs: Document[] = [];

  for (const file of files) {
    const raw = fs.readFileSync(path.join(dir, file), 'utf8');
    const { meta, body } = parseFrontmatter(raw);
    docs.push(
      new Document({
        pageContent: body,
        metadata: {
          id: meta.id ?? file,
          tag: meta.tag ?? meta.id ?? file,
          source: meta.source ?? 'AthleteIQ knowledge base',
          topics: meta.topics ?? '',
          file,
        },
      }),
    );
  }

  const splitter = new RecursiveCharacterTextSplitter({
    chunkSize: 1400,
    chunkOverlap: 100,
  });
  const chunks = await splitter.splitDocuments(docs);
  return MemoryVectorStore.fromDocuments(chunks, new HashedNgramEmbeddings());
}

function getVectorStore(): Promise<MemoryVectorStore> {
  if (!storePromise) {
    storePromise = loadVectorStore();
  }
  return storePromise;
}

/** Map an assessment to retrieval query terms (Section 6 factor list). */
export function factorsFromAssessment(assessment: RiskAssessment): string[] {
  const factors = ['session-RPE training load'];
  factors.push('ACWR acute chronic workload ratio');
  if (assessment.acwr > 1.3 || assessment.acwr < 0.8) {
    factors.push('workload spikes injury risk 1.5 threshold controversy');
  }
  if (assessment.recoveryTrend !== 'stable') {
    factors.push('recovery trend fatigue decay');
  }
  factors.push('Banister Fitness-Fatigue performance');
  return factors;
}

export async function retrieveResearchChunks(
  assessment: RiskAssessment,
  k = 3,
): Promise<Document[]> {
  const store = await getVectorStore();
  const query = [
    ...factorsFromAssessment(assessment),
    `ACWR ${assessment.acwr.toFixed(2)}`,
    `recovery ${assessment.recoveryTrend}`,
    `performance ${assessment.performancePrediction} (${assessment.performanceFrame})`,
    assessment.reason,
  ].join('. ');
  const hits = await store.similaritySearch(query, 8);
  const byId = new Map<string, Document>();
  for (const doc of hits) {
    const id = String(doc.metadata.id ?? doc.metadata.file ?? doc.pageContent.slice(0, 24));
    if (!byId.has(id)) byId.set(id, doc);
    if (byId.size >= k) break;
  }
  return [...byId.values()];
}

function citationsFromDocs(docs: Document[]): ResearchCitation[] {
  const seen = new Set<string>();
  const citations: ResearchCitation[] = [];
  for (const doc of docs) {
    const tag = String(doc.metadata.tag ?? 'Reference');
    if (seen.has(tag)) continue;
    seen.add(tag);
    const firstSentence = doc.pageContent.split(/(?<=\.)\s+/)[0]?.trim() ?? doc.pageContent.slice(0, 220);
    citations.push({
      tag,
      text: firstSentence,
      source: String(doc.metadata.source ?? 'AthleteIQ knowledge base'),
    });
  }
  return citations.slice(0, 3);
}

function defaultNote(assessment: RiskAssessment): string {
  if (assessment.acwr > 1.3) {
    return 'ACWR is a useful spike signal, not a perfect one — the 1.5 danger cutoff is contested in the literature and is one input among several, not treated as absolute truth.';
  }
  return 'This call is grounded in session-RPE training load, ACWR, and a simplified Banister Fitness–Fatigue read of the same series — models, not lab tests.';
}

function parseJsonObject(raw: string): { note?: string; citations?: ResearchCitation[] } | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    return JSON.parse(trimmed.slice(start, end + 1)) as {
      note?: string;
      citations?: ResearchCitation[];
    };
  } catch {
    return null;
  }
}

function retrievedFallback(assessment: RiskAssessment, docs: Document[]): ResearchNote {
  return {
    note: defaultNote(assessment),
    citations: citationsFromDocs(docs),
    source: 'retrieved',
  };
}

/**
 * Retrieve relevant chunks for this assessment and generate a short
 * grounded research note. Never throws — returns retrieved-only text
 * if the LLM is missing or fails.
 */
export async function generateResearchNote(assessment: RiskAssessment): Promise<ResearchNote> {
  const docs = await retrieveResearchChunks(assessment);
  const fallback = retrievedFallback(assessment, docs);
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey || docs.length === 0) {
    return fallback;
  }

  const retrieved = docs
    .map((d, i) => {
      const tag = d.metadata.tag;
      const source = d.metadata.source;
      return `[${i + 1}] tag: ${tag}\nsource: ${source}\n${d.pageContent}`;
    })
    .join('\n\n');

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 400 });
    const human = [
      'Assessment factors:',
      `risk ${assessment.riskLevel}, ACWR ${assessment.acwr.toFixed(2)}, recovery ${assessment.recoveryTrend}, performance ${assessment.performancePrediction} (${assessment.performanceFrame})`,
      `Reason: ${assessment.reason}`,
      '',
      'Retrieved notes:',
      retrieved,
    ].join('\n');
    const raw = await model.pipe(new StringOutputParser()).invoke([
      new SystemMessage(RESEARCH_PROMPT),
      new HumanMessage(human),
    ]);
    const parsed = parseJsonObject(raw);
    if (!parsed?.note || !Array.isArray(parsed.citations) || parsed.citations.length === 0) {
      logger.warn('knowledge agent: invalid LLM JSON, using retrieved fallback', {
        rawPreview: raw.slice(0, 400),
      });
      return fallback;
    }
    const citations = parsed.citations
      .filter((c) => c && c.tag && c.text && c.source)
      .slice(0, 3)
      .map((c) => ({
        tag: String(c.tag),
        text: String(c.text),
        source: String(c.source),
      }));
    if (citations.length === 0) {
      logger.warn('knowledge agent: citations missing tag/text/source, using retrieved fallback');
      return fallback;
    }
    return { note: parsed.note.trim(), citations, source: 'llm' };
  } catch (err) {
    logger.error('knowledge agent LLM failed', err);
    return fallback;
  }
}
