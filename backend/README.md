# Backend MVP Scaffold

FastAPI backend scaffold for the AI character study app.

## Run

```powershell
cd backend
python -m uvicorn app.main:app --reload
```

## Test

```powershell
python -m unittest discover backend/tests
```

## Current Scope

- Demo user flow for local MVP testing
- Minimal profile and character creation
- PDF page text chunking scaffold
- Character prompt wrapping
- Daily/PDF chat response through a switchable text API provider. Hosted Google Gemini API Gemma 4 31B is the default text route; local LM Studio is still supported through `TEXT_API_PROVIDER=local_lmstudio`, and OpenAI can be restored with `TEXT_API_PROVIDER=openai`.
- Quiz generation scaffold
- Affinity stage crossing
- Three costume variants prepared when a character is created
- Affinity-based costume unlocks at 25, 50, and 75
- Wardrobe list, equip, and default-outfit restore endpoints

Text generation now uses the direct Google Gemini API by default. Set `TEXT_API_PROVIDER=gemini`, `GEMINI_API_KEY`, `GEMINI_API_BASE_URL`, and `GEMINI_TEXT_MODEL=gemini-3-flash-preview`. To switch back to hosted Gemma, set `TEXT_API_PROVIDER=gemma` and `GEMMA_TEXT_MODEL=gemma-4-31b-it`. For local LM Studio text generation later, run the LM Studio local server and set `TEXT_API_PROVIDER=local_lmstudio`, `LOCAL_LLM_BASE_URL=http://127.0.0.1:1234`, and `LOCAL_LLM_MODEL=gemma-4-e4b`. No local API key is required unless the local server is configured to require one. To switch back to OpenAI text generation later, set `TEXT_API_PROVIDER=openai` and keep `OPENAI_API_KEY` / `OPENAI_*_MODEL` values. Image generation can use Google Gemini native image generation with `IMAGE_API_PROVIDER=gemini` and `GEMINI_IMAGE_MODEL=gemini-3.1-flash-image-preview` for Nano Banana 2, or OpenAI image APIs with `IMAGE_API_PROVIDER=openai`. Set `GEMINI_IMAGE_GROUNDING=both` to let base character image generation use Google Web Search and Image Search; keep it `off` for normal character-consistent generation. Embeddings, storage, and database migrations are still represented by provider boundaries/placeholders. Kakao login is deferred for now; local flows use the seeded demo user.
