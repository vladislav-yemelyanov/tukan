import type { ClientConfig } from "tukan";

export const DEFAULT_API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";

export interface ClientRuntimeOptions {
  baseUrl?: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}

export function createClientConfig(runtime: ClientRuntimeOptions = {}): ClientConfig {
  return {
    baseUrl: runtime.baseUrl ?? DEFAULT_API_BASE_URL,
    timeoutMs: runtime.timeoutMs ?? 10_000,
    ...(runtime.fetch ? { fetch: runtime.fetch } : {}),
  };
}
