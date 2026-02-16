import { describe, expect, it, vi } from "vitest";
import {
  createParagraphChunkedBlockReplyHarness,
  emitAssistantTextDeltaAndEnd,
  expectFencedChunks,
} from "./pi-embedded-subscribe.e2e-harness.js";

describe("subscribeEmbeddedPiSession", () => {
  const _THINKING_TAG_CASES = [
    { tag: "think", open: "<think>", close: "</think>" },
    { tag: "thinking", open: "<thinking>", close: "</thinking>" },
    { tag: "thought", open: "<thought>", close: "</thought>" },
    { tag: "antthinking", open: "<antthinking>", close: "</antthinking>" },
  ] as const;

  it("reopens fenced blocks when splitting inside them", () => {
    const onBlockReply = vi.fn();
    const { emit } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 10,
        maxChars: 30,
      },
    });

    const text = `\`\`\`txt\n${"a".repeat(80)}\n\`\`\``;
    emitAssistantTextDeltaAndEnd({ emit, text });
    expectFencedChunks(onBlockReply.mock.calls, "```txt");
  });
  it("avoids splitting inside tilde fences", () => {
    const onBlockReply = vi.fn();
    const { emit } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 5,
        maxChars: 25,
      },
    });

    const text = "Intro\n\n~~~sh\nline1\nline2\n~~~\n\nOutro";
    emitAssistantTextDeltaAndEnd({ emit, text });

    expect(onBlockReply).toHaveBeenCalledTimes(3);
    expect(onBlockReply.mock.calls[1][0].text).toBe("~~~sh\nline1\nline2\n~~~");
  });
});
