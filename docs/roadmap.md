This file contains a roadmap for possible future feature implementations.

1. Post Processing (llm) - After finishing the transcription the text gets sent to an LLM endpoint and the LLM corrects the text with better context and understanding. The engine for this already exists: `LanguageModelProvider` + `LanguageModelClient` back both OpenRouter and the local mlx-lm engine (`LocalLLMEngine`), so this is a third caller of `makeClient`, not new infrastructure. A local model here means dictation cleanup never leaves the Mac.
2. Meeting recording - A simple list interface to record and see transcriptions and summaries of meetings.
