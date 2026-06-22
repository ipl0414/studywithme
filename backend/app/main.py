from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from html import escape
from datetime import date
from pathlib import Path
from uuid import uuid4

from fastapi import BackgroundTasks, Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from .config import get_env, load_backend_env
from .domain import (
    AffinityService,
    CharacterContext,
    LLMRouter,
    PdfChunker,
    PdfTextExtractor,
    PromptBuilder,
    QuizChunkSelector,
    SimpleRagRetriever,
)
from .openai_provider import OpenAIImageClient, OpenAIProviderError, OpenAITextClient
from .schemas import (
    AffinityEventRequest,
    AffinityResponse,
    AffinityStatusResponse,
    AuthResponse,
    CharacterCreateRequest,
    CharacterIdRequest,
    CharacterResponse,
    CharacterUpdateRequest,
    ChatMessageRequest,
    ChatMessageResponse,
    ChatHistoryMessageResponse,
    CostumeResponse,
    EquipCostumeRequest,
    ExternalLoginRequest,
    MaterialCreateRequest,
    MaterialResponse,
    ProfileUpdateRequest,
    QuizGenerateRequest,
    QuizResponse,
    TestLoginRequest,
)
from .store import ChatMessageRecord, CostumeRecord, UserRecord, store


load_backend_env()

app = FastAPI(title="AI Character Study App", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:8082",
        "http://localhost:8082",
        "http://127.0.0.1:8081",
        "http://localhost:8081",
    ],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
generated_dir = Path(__file__).resolve().parents[1] / "generated"
generated_dir.mkdir(parents=True, exist_ok=True)
app.mount("/generated", StaticFiles(directory=generated_dir), name="generated")
router = LLMRouter.default()
prompt_builder = PromptBuilder()
affinity_service = AffinityService()
pdf_text_extractor = PdfTextExtractor()
rag_retriever = SimpleRagRetriever()
quiz_chunk_selector = QuizChunkSelector()
openai_client = OpenAITextClient.from_env()
openai_image_client = OpenAIImageClient.from_env()
QUIZ_AFFINITY_DAILY_LIMIT = 0
CHECKIN_REWARD_DELTA = 1
COSTUME_DEFINITIONS: tuple[tuple[str, int, str], ...] = (
    (
        "마법소녀",
        25,
        "a bright magical girl inspired outfit with layered pastel dress, star and ribbon accents, short cape, decorative wand accessory, sparkling study-room fantasy background, energetic heroic pose, cute but tasteful, adult college-age styling, non-sexualized visual novel character design. Absolutely no bunny ears, no leotard, no swimsuit, no jeans, no denim, no casual streetwear",
    ),
    (
        "메이드복",
        50,
        "a stylish modest maid-inspired cafe outfit with frills, ribbon details, apron, black and white fabric, elegant cafe study room background, playful but tasteful",
    ),
    (
        "비키니",
        75,
        "an unmistakable tasteful two-piece bikini swimsuit: bikini top and bikini bottom, bare midriff, bare legs, beach sandals optional, sunlit poolside or beach study retreat background, cheerful vacation mood, adult college-age styling, non-sexualized relaxed standing pose. Absolutely no jeans, no denim, no pants, no trousers, no skirt, no shorts, no leggings, no school uniform, no casual streetwear",
    ),
)
EXPRESSION_DEFINITIONS: tuple[tuple[str, str], ...] = (
    (
        "neutral",
        "a calm neutral face with relaxed eyebrows and a gentle natural mouth",
    ),
    (
        "happy",
        "a warm happy smile, bright eyes, friendly cheerful energy",
    ),
    (
        "shy",
        "a shy embarrassed expression, soft blush, slightly averted eyes, small hesitant smile",
    ),
    (
        "angry",
        "an angry annoyed expression with furrowed brows, slight pout, and one small anime anger vein mark near the temple",
    ),
    (
        "sad",
        "a sad worried expression with softened eyebrows and slightly downturned mouth",
    ),
    (
        "surprised",
        "a surprised expression with widened eyes and slightly open mouth",
    ),
)


TEST_AUTH_TOKEN = "test-token-test_user"


def demo_user_id() -> str:
    return store.demo_user_id


def current_user_id(authorization: str | None = Header(default=None)) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header is required.")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Bearer token is required.")
    user_id = store.get_user_id_for_session(token)
    if user_id is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token.")
    return user_id


def get_character_or_404(character_id: str):
    try:
        return store.get_character(character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc


def get_user_character_or_404(user_id: str, character_id: str):
    character = get_character_or_404(character_id)
    if character.user_id != user_id:
        raise HTTPException(status_code=404, detail="Character not found.")
    return character


def character_response(character) -> CharacterResponse:
    stage = affinity_service.stage_for(character.affinity_score)
    return CharacterResponse(
        id=character.id,
        name=character.name,
        persona_text=character.persona_text,
        appearance_text=character.appearance_text,
        relationship_stage=stage.label,
        affinity_score=character.affinity_score,
        base_image_url=character.base_image_url,
        profile_image_url=character.profile_image_url,
        visual_novel_image_url=character.visual_novel_image_url,
        expression_image_urls=_current_expression_image_urls(character),
        current_outfit_id=character.current_outfit_id,
    )


def material_response(material) -> MaterialResponse:
    return MaterialResponse(
        id=material.id,
        title=material.title,
        status=material.status,
        chunk_count=len(material.chunks),
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "text_api": "configured" if openai_client.is_configured else "missing",
        "text_provider": getattr(openai_client, "provider_name", "unknown"),
        "image_api": "disabled"
        if _image_generation_disabled()
        else "configured"
        if openai_image_client.is_configured
        else "missing",
    }


@app.get("/dev/generated-images", response_class=HTMLResponse)
def generated_images_dev_page() -> str:
    image_records = _generated_image_records()
    rows = "\n".join(
        (
            "<article class='card'>"
            f"<a href='{escape(record['url'])}' target='_blank' rel='noreferrer'>"
            f"<img src='{escape(record['url'])}' alt='{escape(record['file'])}' loading='lazy'>"
            "</a>"
            f"<div class='meta'><strong>{escape(record['kind'])}</strong>"
            f"<span>{escape(record['character_name'])}</span>"
            f"<code>{escape(record['file'])}</code>"
            f"<a href='{escape(record['url'])}' target='_blank' rel='noreferrer'>{escape(record['url'])}</a>"
            "</div>"
            "</article>"
        )
        for record in image_records
    )
    if not rows:
        rows = "<p class='empty'>No generated images yet.</p>"
    return f"""
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Generated Images</title>
  <style>
    body {{ margin: 0; font-family: Arial, sans-serif; background: #111; color: #f7f1ea; }}
    header {{ position: sticky; top: 0; z-index: 1; padding: 18px 22px; background: rgba(17,17,17,.9); border-bottom: 1px solid #333; }}
    h1 {{ margin: 0; font-size: 20px; }}
    .count {{ margin-top: 6px; color: #bbb; font-size: 13px; }}
    main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; padding: 18px; }}
    .card {{ overflow: hidden; border: 1px solid #333; border-radius: 8px; background: #1b1b1b; }}
    img {{ display: block; width: 100%; aspect-ratio: 9 / 13; object-fit: cover; object-position: top center; background: #2a2a2a; }}
    .meta {{ display: grid; gap: 6px; padding: 12px; font-size: 13px; }}
    strong {{ color: #ffd0df; }}
    span {{ color: #ddd; }}
    code {{ overflow-wrap: anywhere; color: #9ee7ff; }}
    a {{ color: #a9d8ff; overflow-wrap: anywhere; text-decoration: none; }}
    .empty {{ padding: 24px; color: #bbb; }}
  </style>
</head>
<body>
  <header>
    <h1>Generated Images</h1>
    <div class="count">{len(image_records)} files · click an image to open original</div>
  </header>
  <main>{rows}</main>
</body>
</html>
"""


@app.get("/dev/generated-images.json")
def generated_images_dev_json() -> list[dict[str, str]]:
    return _generated_image_records()


@app.post("/dev/chat/seed-compact-test")
def seed_compact_chat_test(character_id: str | None = None) -> dict:
    character = (
        get_character_or_404(character_id)
        if character_id
        else store.get_current_character(demo_user_id())
    )
    if character is None:
        raise HTTPException(status_code=404, detail="No character has been created.")
    messages = [
        ChatMessageRecord(
            character_id=character.id,
            role="user" if index % 2 == 0 else "assistant",
            text=f"테스트 메시지 {index}",
        )
        for index in range(10)
    ]
    store.replace_chat_messages(character.id, messages)
    character.interaction_summary = "No prior interaction yet."
    compacted_messages = store.compact_first_chat_messages(character.id, 5)
    character.interaction_summary = _compact_interaction_summary(
        character.interaction_summary,
        compacted_messages,
    )
    store.save_character(character)
    remaining_messages = store.list_chat_messages(character.id)
    return {
        "character_id": character.id,
        "compacted_count": len(compacted_messages),
        "remaining_count": len(remaining_messages),
        "compacted_texts": [message.text for message in compacted_messages],
        "remaining_texts": [message.text for message in remaining_messages],
        "interaction_summary": character.interaction_summary,
    }


def _image_generation_disabled() -> bool:
    return (get_env("TEST_NO_IMAGE", "no") or "no").strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


def _unlock_all_costumes_for_test() -> bool:
    return (get_env("UNLOCK_ALL_COSTUMES_FOR_TEST", "no") or "no").strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


def _test_generated_image_character_id() -> str | None:
    value = (get_env("TEST_GENERATED_IMAGE_CHARACTER_ID", "") or "").strip()
    if not value:
        return None
    if not (generated_dir / value).exists():
        return None
    return value


def _test_generated_image_url(filename: str) -> str | None:
    character_id = _test_generated_image_character_id()
    if not character_id:
        return None
    image_path = generated_dir / character_id / filename
    if not image_path.exists():
        return None
    return f"/generated/{character_id}/{filename}"


def _test_profile_image_url() -> str:
    return _test_generated_image_url("profile.png") or "/assets/default-character.png"


def _test_visual_novel_image_url() -> str:
    return _test_generated_image_url("visual_novel.png") or _test_profile_image_url()


def _test_costume_image_url(index: int) -> str:
    return _test_generated_image_url(f"costume_{index}.png") or "/assets/default-outfit.png"


def _test_expression_image_urls(source_key: str, base_image_url: str) -> dict[str, str]:
    urls: dict[str, str] = {"neutral": base_image_url}
    for key, _ in EXPRESSION_DEFINITIONS:
        if key == "neutral":
            continue
        urls[key] = (
            _test_generated_image_url(f"expression_{source_key}_{key}.png")
            or base_image_url
        )
    return urls


def _text_model_for(task_type: str) -> str:
    provider_name = getattr(openai_client, "provider_name", "openai")
    default_model = getattr(openai_client, "default_model", router.model_for(task_type))
    if provider_name in {"local_lmstudio", "local", "lmstudio", "lm_studio"}:
        return get_env("LOCAL_LLM_MODEL", default_model) or default_model
    if provider_name in {"gemini", "google_gemini"}:
        return (
            get_env("GEMINI_TEXT_MODEL")
            or get_env("GEMMA_TEXT_MODEL")
            or default_model
        )
    if provider_name in {"gemma", "google_gemma", "google"}:
        return (
            get_env("GEMMA_TEXT_MODEL")
            or default_model
        )

    if task_type in {"daily_chat", "study_rag_chat"}:
        return get_env("OPENAI_DAILY_CHAT_MODEL", default_model) or default_model
    return get_env("OPENAI_PREMIUM_MODEL", default_model) or default_model


def _image_model_for() -> str:
    provider_name = getattr(openai_image_client, "provider_name", "openai_image")
    default_model = getattr(openai_image_client, "default_model", router.model_for("image_generation"))
    if provider_name in {"gemini_image", "gemini", "google_image"}:
        return get_env("GEMINI_IMAGE_MODEL", default_model) or default_model
    return get_env("OPENAI_IMAGE_MODEL", default_model) or default_model


def _generated_image_records() -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    image_paths = sorted(
        path
        for path in generated_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
    )
    for path in image_paths:
        relative_path = path.relative_to(generated_dir).as_posix()
        character_id = relative_path.split("/", 1)[0]
        character = store.characters.get(character_id)
        records.append(
            {
                "character_id": character_id,
                "character_name": character.name if character else character_id,
                "kind": _generated_image_kind(path.name),
                "file": relative_path,
                "url": f"/generated/{relative_path}",
            }
        )
    return records


def _generated_image_kind(filename: str) -> str:
    if filename == "profile.png":
        return "profile"
    if filename == "visual_novel.png":
        return "visual novel"
    if filename.startswith("costume_"):
        return "costume"
    if filename.startswith("expression_"):
        return "expression"
    return "generated"


@app.post("/auth/external", response_model=AuthResponse)
def login_with_external_provider(request: ExternalLoginRequest) -> AuthResponse:
    user = store.create_user_from_external_token(request.access_token)
    session = store.create_session(user.id)
    return AuthResponse(access_token=session.token, user_id=user.id)


@app.post("/auth/test", response_model=AuthResponse)
def login_with_test_account(request: TestLoginRequest) -> AuthResponse:
    user_id = request.user_id.strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="User id is required.")
    try:
        store.get_user(user_id)
    except KeyError:
        store.save_user(
            UserRecord(
                id=user_id,
                external_auth_id=f"dev_login_{user_id}",
                display_name=user_id,
            )
        )
    token = TEST_AUTH_TOKEN if user_id == "test_user" else None
    session = store.create_session(user_id, token)
    return AuthResponse(access_token=session.token, user_id=session.user_id)


@app.patch("/profile")
def update_profile(
    request: ProfileUpdateRequest,
    user_id: str = Depends(current_user_id),
) -> dict[str, str]:
    profile = store.upsert_profile(user_id, request.department, request.study_goal)
    return {
        "user_id": profile.user_id,
        "department": profile.department,
        "study_goal": profile.study_goal,
    }


@app.post("/characters", response_model=CharacterResponse)
def create_character(
    request: CharacterCreateRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    try:
        character = store.create_character(
            user_id,
            request.name,
            request.persona_text,
            request.appearance_text,
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    character.profile_image_url = _generate_character_profile_image(character)
    character.visual_novel_image_url = _generate_character_visual_novel_image(character)
    character.base_image_url = character.visual_novel_image_url
    character.expression_image_urls = _generate_character_expression_images(character)
    store.save_character(character)
    costumes = _create_character_costume_records(character.id)
    if _image_generation_disabled():
        for index, costume in enumerate(costumes, start=1):
            costume.image_url = _test_costume_image_url(index)
            costume.expression_image_urls = _test_expression_image_urls(
                f"costume{index}",
                costume.image_url,
            )
            costume.generation_status = "ready"
            store.save_costume(costume)
    else:
        background_tasks.add_task(_generate_character_costumes, character.id)
    return character_response(character)


@app.get("/characters", response_model=list[CharacterResponse])
def list_characters(user_id: str = Depends(current_user_id)) -> list[CharacterResponse]:
    return [character_response(character) for character in store.list_characters(user_id)]


@app.get("/characters/current", response_model=CharacterResponse)
def get_current_character(user_id: str = Depends(current_user_id)) -> CharacterResponse:
    character = store.get_current_character(user_id)
    if character is None:
        raise HTTPException(status_code=404, detail="No character has been created.")
    return character_response(character)


@app.post("/characters/{character_id}/select", response_model=CharacterResponse)
def select_character(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    try:
        character = store.select_character(user_id, character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    return character_response(character)


@app.patch("/characters/{character_id}", response_model=CharacterResponse)
def update_character(
    character_id: str,
    request: CharacterUpdateRequest,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    try:
        character = store.update_character(
            user_id,
            character_id,
            name=request.name,
            persona_text=request.persona_text,
            appearance_text=request.appearance_text,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    return character_response(character)


@app.delete("/characters/{character_id}", response_model=CharacterResponse)
def delete_character(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    try:
        character = store.delete_character(user_id, character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    return character_response(character)


@app.post("/characters/{character_id}/equip-default", response_model=CharacterResponse)
def equip_default_character_image(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    character = get_user_character_or_404(user_id, character_id)
    character.base_image_url = (
        character.visual_novel_image_url
        or character.profile_image_url
        or "/assets/default-character.png"
    )
    character.current_outfit_id = None
    character.expression_image_urls = _expression_fallback_images(character)
    store.save_character(character)
    return character_response(character)


@app.post("/characters/{character_id}/visual-novel-image", response_model=CharacterResponse)
def generate_visual_novel_character_image(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    character = get_user_character_or_404(user_id, character_id)
    character.visual_novel_image_url = _generate_character_visual_novel_image(character)
    if character.current_outfit_id is None:
        character.base_image_url = character.visual_novel_image_url
    character.expression_image_urls = _generate_character_expression_images(character)
    store.save_character(character)
    return character_response(character)


@app.post("/materials", response_model=MaterialResponse)
def create_material(
    request: MaterialCreateRequest,
    user_id: str = Depends(current_user_id),
) -> MaterialResponse:
    temp_material_id = f"mat_{uuid4().hex[:12]}"
    chunks = PdfChunker().chunk_pages(temp_material_id, request.pages)
    material = store.create_material(user_id, request.title, chunks, temp_material_id)
    return material_response(material)


@app.get("/materials", response_model=list[MaterialResponse])
def list_materials(user_id: str = Depends(current_user_id)) -> list[MaterialResponse]:
    return [material_response(material) for material in store.list_materials(user_id)]


@app.delete("/materials/{material_id}")
def delete_material(
    material_id: str,
    user_id: str = Depends(current_user_id),
) -> dict[str, str]:
    try:
        store.delete_material(user_id, material_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Material not found.") from exc
    return {"status": "deleted", "id": material_id}


@app.post("/materials/upload", response_model=MaterialResponse)
async def upload_material(
    file: UploadFile = File(...),
    user_id: str = Depends(current_user_id),
) -> MaterialResponse:
    filename = file.filename or "uploaded.pdf"
    if not filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF uploads are supported.")
    pdf_bytes = await file.read()
    try:
        pages = pdf_text_extractor.extract_pages(pdf_bytes)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not read text from the PDF: {exc}") from exc
    if not pages:
        raise HTTPException(status_code=400, detail="No extractable text was found in the PDF.")

    material_id = f"mat_{uuid4().hex[:12]}"
    chunks = PdfChunker().chunk_pages(material_id, pages)
    material = store.create_material(user_id, filename, chunks, material_id)
    return material_response(material)


@app.post("/chat/messages", response_model=ChatMessageResponse)
def send_chat_message(
    request: ChatMessageRequest,
    user_id: str = Depends(current_user_id),
) -> ChatMessageResponse:
    character = get_user_character_or_404(user_id, request.character_id)
    context = CharacterContext(
        persona_text=character.persona_text,
        appearance_text=character.appearance_text,
        relationship_stage=affinity_service.stage_for(character.affinity_score).label,
        interaction_summary=character.interaction_summary,
    )
    selected_material_ids = _selected_material_ids(request.material_id, request.material_ids)
    chat_mode = _normalize_chat_mode(request.mode, has_material=bool(selected_material_ids))
    system_prompt = prompt_builder.build_system_prompt(context, chat_mode)
    model_task = "study_rag_chat" if selected_material_ids else "daily_chat"
    model = _text_model_for(model_task)

    source_chunk_ids: list[str] = []
    material_context = "No PDF material context was provided."
    if selected_material_ids:
        materials = _get_materials_or_404(user_id, selected_material_ids)
        all_chunks = [chunk for material in materials for chunk in material.chunks]
        source_chunks = rag_retriever.search(all_chunks, request.message, limit=6)
        source_chunk_ids = [chunk.id for chunk in source_chunks]
        material_context = "\n\n".join(
            f"[{chunk.id} page {chunk.page_number}]\n{chunk.text}" for chunk in source_chunks
        )
    recent_history = store.list_chat_messages(
        request.character_id,
        limit=store.max_chat_messages_per_character,
    )
    conversation_history = "\n".join(
        f"{message.role}: {message.text}" for message in recent_history
    )

    input_text = (
        "[Compacted prior conversation]\n"
        f"{character.interaction_summary or 'No compacted prior conversation yet.'}\n\n"
        "[Conversation history]\n"
        f"{conversation_history or 'No previous conversation with this character yet.'}\n\n"
        f"User message:\n{request.message}\n\n"
        f"Relevant material context:\n{material_context}"
    )
    try:
        raw_reply = openai_client.generate_text(
            model=model,
            instructions=system_prompt,
            input_text=input_text,
            max_output_tokens=_chat_max_output_tokens(chat_mode),
        )
    except OpenAIProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    environment_box, reply, model_expression = _parse_chat_environment_response(raw_reply)
    store.add_chat_message(request.character_id, "user", request.message)
    if environment_box:
        store.add_chat_message(request.character_id, "environment", environment_box)
    store.add_chat_message(request.character_id, "assistant", reply)
    compacted_messages = store.compact_chat_messages(request.character_id)
    if compacted_messages:
        character.interaction_summary = _compact_interaction_summary(
            character.interaction_summary,
            compacted_messages,
        )
        store.save_character(character)
    expression = model_expression or _expression_for_chat(request.message, reply)
    return ChatMessageResponse(
        reply=reply,
        environment_box=environment_box,
        expression=expression,
        expression_image_url=_expression_image_url(character, expression),
        model=model,
        system_prompt_preview=system_prompt[:800],
        source_chunk_ids=source_chunk_ids,
    )


@app.get("/chat/messages", response_model=list[ChatHistoryMessageResponse])
def list_chat_messages(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> list[ChatHistoryMessageResponse]:
    character = get_user_character_or_404(user_id, character_id)
    compacted_messages = store.compact_chat_messages(character_id)
    if compacted_messages:
        character.interaction_summary = _compact_interaction_summary(
            character.interaction_summary,
            compacted_messages,
        )
        store.save_character(character)
    return [
        ChatHistoryMessageResponse(role=message.role, text=message.text)
        for message in store.list_chat_messages(
            character_id,
            limit=store.max_chat_messages_per_character,
        )
    ]


@app.post("/quizzes/generate", response_model=QuizResponse)
def generate_quiz(
    request: QuizGenerateRequest,
    user_id: str = Depends(current_user_id),
) -> QuizResponse:
    selected_material_ids = _selected_material_ids(request.material_id, request.material_ids)
    if not selected_material_ids:
        raise HTTPException(status_code=400, detail="At least one material is required.")
    materials = _get_materials_or_404(user_id, selected_material_ids)
    all_chunks = [chunk for material in materials for chunk in material.chunks]
    question_count = request.question_count or _recommended_quiz_question_count(
        len(all_chunks)
    )
    quiz_chunks = quiz_chunk_selector.select(
        all_chunks,
        question_count=question_count,
        max_chunks=12,
    )
    source_context = "\n\n".join(
        f"[{chunk.id} page {chunk.page_number}]\n{chunk.text}"
        for chunk in quiz_chunks
    )
    material_title = " + ".join(material.title for material in materials)
    character_context_text = "No character context was provided."
    if request.character_id:
        character = get_user_character_or_404(user_id, request.character_id)
        character_context_text = (
            f"Character persona: {character.persona_text}\n"
            f"Character appearance: {character.appearance_text}\n"
            "Relationship stage: "
            f"{affinity_service.stage_for(character.affinity_score).label}\n"
            f"Recent interaction summary: {character.interaction_summary}"
        )
    instructions = (
        "You are an expert Korean university tutor and exam-question writer. "
        "Create a high-quality quiz from the provided PDF excerpts. "
        "Generate the entire quiz in one response. Do not require follow-up calls. "
        "Before returning JSON, internally identify key concepts, draft questions, "
        "remove weak or ambiguous questions, and revise trivial keyword-matching questions. "
        "Do not show this review. "
        "Return only valid JSON with a top-level questions array. "
        f"Create exactly {question_count} multiple-choice questions, never more than 10. "
        "Use only the provided source chunks. Write in Korean. "
        "At least half of the questions must test understanding, comparison, cause-effect, process, exception, or application. "
        "Avoid tiny isolated facts unless they are central definitions. "
        "Use four choices per question and answer_index as a zero-based integer. "
        "Exactly one choice must be correct. Distractors must be plausible misunderstandings based on the source. "
        "Avoid all-of-the-above, none-of-the-above, silly distractors, and ambiguous wording. "
        "Include a difficulty of easy, medium, or hard. "
        "The explanation must teach the concept, and choice_explanations must briefly explain each choice. "
        "Write correct_reaction and wrong_reaction as short character dialogue that reflects the character persona, "
        "current relationship stage, and recent chat context. "
        "Do not make these reactions generic teacher feedback."
    )
    input_text = (
        f"{character_context_text}\n\n"
        f"Material title: {material_title}\n"
        f"Material ids: {', '.join(selected_material_ids)}\n"
        f"Question count: {question_count}\n"
        "Create questions that help a university student check whether they truly understood the material. "
        "Avoid simply copying source sentences; transform them into comparison, scenario, or most-accurate-statement questions when possible.\n"
        f"Source chunks:\n{source_context}"
    )
    quiz_model = _text_model_for("quiz_generation")
    try:
        raw_quiz = _generate_quiz_text_with_fallback(
            model=quiz_model,
            instructions=instructions,
            input_text=input_text,
        )
        questions = _parse_quiz_questions(raw_quiz)
    except OpenAIProviderError as exc:
        raise HTTPException(status_code=502, detail=_friendly_text_provider_error(str(exc))) from exc
    return QuizResponse(
        id=f"quiz_{uuid4().hex[:12]}",
        material_id=selected_material_ids[0],
        material_ids=selected_material_ids,
        title=f"{material_title} Quiz",
        questions=questions,
        model=quiz_model,
    )


def _generate_quiz_text_with_fallback(
    *,
    model: str,
    instructions: str,
    input_text: str,
) -> str:
    try:
        return openai_client.generate_text(
            model=model,
            instructions=instructions,
            input_text=input_text,
            max_output_tokens=_quiz_max_output_tokens(_extract_question_count(input_text)),
            text_format=_quiz_response_text_format(),
        )
    except OpenAIProviderError as exc:
        if not _should_retry_quiz_without_schema(str(exc)):
            raise

    fallback_instructions = (
        f"{instructions}\n\n"
        "[Gemini structured-output fallback]\n"
        "The previous schema-constrained request failed at the provider. "
        "Return the same quiz as plain JSON only, with no Markdown fences and no commentary. "
        "The JSON must still have exactly this shape: "
        '{"questions":[{"type":"multiple_choice","difficulty":"easy|medium|hard",'
        '"question":"...","choices":["...","...","...","..."],"answer_index":0,'
        '"explanation":"...","choice_explanations":["...","...","...","..."],'
        '"correct_reaction":"...","wrong_reaction":"...","source_chunk_ids":["..."]}]}'
    )
    return openai_client.generate_text(
        model=model,
        instructions=fallback_instructions,
        input_text=input_text,
        max_output_tokens=_quiz_max_output_tokens(_extract_question_count(input_text)),
        text_format=None,
    )


@app.post("/affinity/events", response_model=AffinityResponse)
def apply_affinity_event(
    request: AffinityEventRequest,
    user_id: str = Depends(current_user_id),
) -> AffinityResponse:
    character = get_user_character_or_404(user_id, request.character_id)
    today = request.event_date or date.today()
    _reset_daily_affinity_if_needed(character, today)
    if (
        request.event_type.startswith("quiz_")
        and request.reward_key
        and request.reward_key in character.claimed_affinity_reward_keys
    ):
        stage = affinity_service.stage_for(character.affinity_score)
        return _affinity_response(
            character=character,
            score=character.affinity_score,
            relationship_stage=stage.key,
            relationship_stage_label=stage.label,
            unlocked_costume_ids=[],
            affinity_applied=False,
            applied_delta=0,
        )
    delta = request.delta
    if request.event_type.startswith("quiz_"):
        if request.reward_key:
            character.claimed_affinity_reward_keys.add(request.reward_key)
    result = affinity_service.apply_event(
        current_score=character.affinity_score,
        event_type=request.event_type,
        delta=delta,
    )
    character.affinity_score = result.new_score
    character.relationship_stage = result.current_stage.key
    if request.event_type.startswith("quiz_"):
        character.quiz_affinity_gained_today += result.new_score - result.previous_score
    store.save_character(character)
    return _affinity_response(
        character=character,
        score=result.new_score,
        relationship_stage=result.current_stage.key,
        relationship_stage_label=result.current_stage.label,
        unlocked_costume_ids=_costume_ids_for_unlock_scores(
            character.id,
            result.unlocked_costume_scores,
        ),
        affinity_applied=True,
        applied_delta=result.new_score - result.previous_score,
    )


@app.get("/affinity/status", response_model=AffinityStatusResponse)
def get_affinity_status(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> AffinityStatusResponse:
    character = get_user_character_or_404(user_id, character_id)
    _reset_daily_affinity_if_needed(character, date.today())
    stage = affinity_service.stage_for(character.affinity_score)
    return AffinityStatusResponse(
        score=character.affinity_score,
        relationship_stage=stage.key,
        relationship_stage_label=stage.label,
        quiz_affinity_gained_today=character.quiz_affinity_gained_today,
        quiz_affinity_daily_limit=0,
        quiz_affinity_remaining_today=0,
        checkin_available=character.last_checkin_date != date.today(),
        checkin_reward_delta=CHECKIN_REWARD_DELTA,
    )


@app.post("/affinity/checkin", response_model=AffinityResponse)
def apply_checkin_affinity(
    request: CharacterIdRequest,
    user_id: str = Depends(current_user_id),
) -> AffinityResponse:
    character = get_user_character_or_404(user_id, request.character_id)
    today = date.today()
    _reset_daily_affinity_if_needed(character, today)
    if character.last_checkin_date == today:
        stage = affinity_service.stage_for(character.affinity_score)
        return _affinity_response(
            character=character,
            score=character.affinity_score,
            relationship_stage=stage.key,
            relationship_stage_label=stage.label,
            unlocked_costume_ids=[],
            affinity_applied=False,
            applied_delta=0,
        )
    result = affinity_service.apply_event(
        current_score=character.affinity_score,
        event_type="daily_checkin",
        delta=CHECKIN_REWARD_DELTA,
    )
    character.affinity_score = result.new_score
    character.relationship_stage = result.current_stage.key
    character.last_checkin_date = today
    store.save_character(character)
    return _affinity_response(
        character=character,
        score=result.new_score,
        relationship_stage=result.current_stage.key,
        relationship_stage_label=result.current_stage.label,
        unlocked_costume_ids=_costume_ids_for_unlock_scores(
            character.id,
            result.unlocked_costume_scores,
        ),
        affinity_applied=True,
        applied_delta=result.new_score - result.previous_score,
    )


@app.get("/wardrobe/costumes", response_model=list[CostumeResponse])
def list_costumes(
    character_id: str,
    user_id: str = Depends(current_user_id),
) -> list[CostumeResponse]:
    character = get_user_character_or_404(user_id, character_id)
    return [
        _costume_response(costume, character)
        for costume in store.list_costumes(character_id)
    ]


@app.post(
    "/wardrobe/costumes/{costume_id}/equip",
    response_model=CharacterResponse,
)
def equip_costume(
    costume_id: str,
    request: EquipCostumeRequest,
    user_id: str = Depends(current_user_id),
) -> CharacterResponse:
    try:
        costume = store.get_costume(costume_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Costume not found.") from exc
    character = get_user_character_or_404(user_id, request.character_id)
    if costume.character_id != character.id:
        raise HTTPException(status_code=404, detail="Costume not found.")
    if (
        character.affinity_score < costume.unlock_score
        and not _unlock_all_costumes_for_test()
    ):
        raise HTTPException(status_code=403, detail="Costume is still locked.")
    if (
        costume.generation_status != "ready"
        or not costume.image_url
        or not _has_all_expression_images(costume.expression_image_urls)
    ):
        raise HTTPException(status_code=409, detail="Costume image is not ready.")
    character.base_image_url = costume.image_url
    character.current_outfit_id = costume.id
    character.expression_image_urls = dict(costume.expression_image_urls)
    store.save_character(character)
    return character_response(character)


def _parse_json_value(text: str):
    import json

    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.strip("`")
        if stripped.startswith("json"):
            stripped = stripped[4:].strip()
    object_start = stripped.find("{")
    array_start = stripped.find("[")
    if array_start >= 0 and (object_start < 0 or array_start < object_start):
        array_end = stripped.rfind("]")
        if array_end >= array_start:
            stripped = stripped[array_start : array_end + 1]
    elif object_start >= 0:
        object_end = stripped.rfind("}")
        if object_end >= object_start:
            stripped = stripped[object_start : object_end + 1]
    try:
        return json.loads(stripped)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=502, detail="Text model returned invalid JSON.") from exc


def _parse_json_object(text: str) -> dict:
    value = _parse_json_value(text)
    if not isinstance(value, dict):
        raise HTTPException(status_code=502, detail="Text model JSON output was not an object.")
    return value


def _should_retry_quiz_without_schema(error_message: str) -> bool:
    lowered = error_message.lower()
    return (
        "gemini api returned http 500" in lowered
        or "gemini api returned http 503" in lowered
        or "internal error encountered" in lowered
        or "unavailable" in lowered
    )


def _should_retry_image_with_simple_prompt(error_message: str) -> bool:
    lowered = error_message.lower()
    return (
        "did not include inline image data" in lowered
        or "did not include b64_json" in lowered
    )


def _friendly_text_provider_error(error_message: str) -> str:
    lowered = error_message.lower()
    if "gemini api returned http 500" in lowered or "internal error encountered" in lowered:
        return "Gemini가 요청을 처리하는 중 일시적인 내부 오류를 냈어요. 잠시 후 다시 시도해 주세요."
    if "gemini api returned http 503" in lowered or "unavailable" in lowered:
        return "Gemini 모델이 지금 혼잡해서 응답하지 못했어요. 잠시 후 다시 시도해 주세요."
    return error_message


def _normalize_chat_mode(mode: str, *, has_material: bool) -> str:
    allowed = {
        "daily_chat",
        "daily_long_chat",
        "study_rag_chat",
        "study_rag_short_chat",
        "study_rag_long_chat",
    }
    normalized = mode if mode in allowed else "daily_chat"
    if has_material:
        if normalized == "daily_long_chat":
            return "study_rag_long_chat"
        if normalized == "daily_chat":
            return "study_rag_chat"
        return normalized
    if normalized.startswith("study_rag"):
        return "daily_long_chat" if normalized.endswith("long_chat") else "daily_chat"
    return normalized


def _chat_max_output_tokens(chat_mode: str) -> int:
    if chat_mode == "daily_long_chat":
        return 850
    if chat_mode == "study_rag_short_chat":
        return 650
    if chat_mode in {"study_rag_chat", "study_rag_long_chat"}:
        return 1100
    return 380


def _parse_quiz_questions(text: str) -> list[dict]:
    payload = _parse_json_value(text)
    if isinstance(payload, list):
        questions = payload
    elif isinstance(payload, dict):
        questions = payload.get("questions")
    else:
        questions = None
    if not isinstance(questions, list) or not questions:
        raise HTTPException(status_code=502, detail="Text model quiz output did not include questions.")
    normalized = [
        _normalize_quiz_question(question)
        for question in questions
        if isinstance(question, dict)
    ]
    if not normalized:
        raise HTTPException(status_code=502, detail="Text model quiz output had no valid questions.")
    return normalized


def _parse_chat_environment_response(text: str) -> tuple[str, str, str | None]:
    import re

    expression = _normalize_expression(_extract_tagged_section(text, "EXPRESSION"))
    environment_box = _extract_tagged_section(text, "ENVIRONMENT_BOX")
    reply = _extract_tagged_section(text, "CHARACTER_REPLY")
    if not reply:
        reply = _remove_known_chat_tags(text)
        if environment_box:
            reply = reply.replace(environment_box, "").strip()
    if not reply:
        reply = "...잠깐, 방금 흐름 이상했지. 다시 말해봐."
    return environment_box, reply, expression


def _extract_tagged_section(text: str, tag: str) -> str:
    import re

    start_match = re.search(rf"\[{tag}\]", text, flags=re.IGNORECASE)
    if not start_match:
        return ""
    content_start = start_match.end()
    close_match = re.search(rf"\[/{tag}\]", text[content_start:], flags=re.IGNORECASE)
    if close_match:
        return text[content_start : content_start + close_match.start()].strip()

    next_known_tag = re.search(
        r"\[/?(?:EXPRESSION|ENVIRONMENT_BOX|CHARACTER_REPLY)\]",
        text[content_start:],
        flags=re.IGNORECASE,
    )
    content_end = content_start + next_known_tag.start() if next_known_tag else len(text)
    return text[content_start:content_end].strip()


def _remove_known_chat_tags(text: str) -> str:
    import re

    return re.sub(
        r"\[/?(?:EXPRESSION|ENVIRONMENT_BOX|CHARACTER_REPLY)\]",
        "",
        text,
        flags=re.IGNORECASE,
    ).strip()


def _normalize_quiz_question(question: dict) -> dict:
    choices = [str(choice) for choice in question.get("choices", []) if str(choice).strip()]
    choices = choices[:4]
    while len(choices) < 4:
        choices.append(f"선지 {len(choices) + 1}")

    answer_index = question.get("answer_index", 0)
    if not isinstance(answer_index, int):
        try:
            answer_index = int(answer_index)
        except (TypeError, ValueError):
            answer_index = 0
    answer_index = max(0, min(3, answer_index))

    explanation = str(question.get("explanation") or "자료의 핵심 개념을 다시 확인해 보세요.").strip()
    difficulty = str(question.get("difficulty") or "medium").strip().lower()
    if difficulty not in {"easy", "medium", "hard"}:
        difficulty = "medium"

    choice_explanations = [
        str(item).strip()
        for item in question.get("choice_explanations", [])
        if str(item).strip()
    ]
    if len(choice_explanations) != 4:
        choice_explanations = [
            f"{'정답' if index == answer_index else '오답'}: {explanation}"
            for index in range(4)
        ]

    source_chunk_ids = [
        str(item).strip()
        for item in question.get("source_chunk_ids", [])
        if str(item).strip()
    ]

    return {
        "type": str(question.get("type") or "multiple_choice"),
        "difficulty": difficulty,
        "question": str(question.get("question") or "").strip(),
        "choices": choices,
        "answer_index": answer_index,
        "explanation": explanation,
        "choice_explanations": choice_explanations,
        "correct_reaction": str(
            question.get("correct_reaction") or "오, 맞았네. 핵심 잘 잡았어 ㅋㅋ"
        ).strip(),
        "wrong_reaction": str(
            question.get("wrong_reaction") or "아깝다. 이건 헷갈릴 만했어. 해설 보고 다시 잡자."
        ).strip(),
        "source_chunk_ids": source_chunk_ids,
    }


def _reset_daily_affinity_if_needed(character, today: date) -> None:
    if character.quiz_affinity_date != today:
        character.quiz_affinity_date = today
        character.quiz_affinity_gained_today = 0
        store.save_character(character)


def _affinity_response(
    *,
    character,
    score: int,
    relationship_stage: str,
    relationship_stage_label: str,
    unlocked_costume_ids: list[str],
    affinity_applied: bool,
    applied_delta: int,
) -> AffinityResponse:
    return AffinityResponse(
        score=score,
        relationship_stage=relationship_stage,
        relationship_stage_label=relationship_stage_label,
        unlocked_costume_ids=unlocked_costume_ids,
        affinity_applied=affinity_applied,
        applied_delta=applied_delta,
        quiz_affinity_gained_today=character.quiz_affinity_gained_today,
        quiz_affinity_daily_limit=0,
        quiz_affinity_remaining_today=0,
        checkin_available=character.last_checkin_date != date.today(),
    )


def _costume_ids_for_unlock_scores(
    character_id: str,
    unlock_scores: tuple[int, ...],
) -> list[str]:
    scores = set(unlock_scores)
    return [
        costume.id
        for costume in store.list_costumes(character_id)
        if costume.unlock_score in scores
    ]


def _costume_response(costume: CostumeRecord, character) -> CostumeResponse:
    is_unlocked = (
        character.affinity_score >= costume.unlock_score
        or _unlock_all_costumes_for_test()
    )
    return CostumeResponse(
        id=costume.id,
        name=costume.name,
        unlock_score=costume.unlock_score,
        is_unlocked=is_unlocked,
        is_equipped=character.current_outfit_id == costume.id,
        generation_status=costume.generation_status,
        image_url=costume.image_url if is_unlocked else None,
        expression_image_urls=costume.expression_image_urls if is_unlocked else {},
    )


def _selected_material_ids(material_id: str | None, material_ids: list[str]) -> list[str]:
    selected: list[str] = []
    if material_id:
        selected.append(material_id)
    selected.extend(material_ids)
    return list(dict.fromkeys(item for item in selected if item))


def _get_materials_or_404(user_id: str, material_ids: list[str]):
    materials = []
    for material_id in material_ids:
        try:
            material = store.get_material(material_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=f"Material not found: {material_id}") from exc
        if material.user_id != user_id:
            raise HTTPException(status_code=404, detail=f"Material not found: {material_id}")
        materials.append(material)
    return materials


def _recommended_quiz_question_count(chunk_count: int) -> int:
    if chunk_count <= 1:
        return 3
    return max(3, min(5, chunk_count * 2))


def _quiz_max_output_tokens(question_count: int) -> int:
    return max(4000, min(12000, question_count * 1200))


def _extract_question_count(input_text: str) -> int:
    import re

    match = re.search(r"Question count:\s*(\d+)", input_text)
    if not match:
        return 3
    return max(1, min(10, int(match.group(1))))


def _quiz_response_text_format() -> dict:
    question_schema = {
        "type": "object",
        "properties": {
            "type": {"type": "string"},
            "difficulty": {
                "type": "string",
                "enum": ["easy", "medium", "hard"],
            },
            "question": {"type": "string"},
            "choices": {
                "type": "array",
                "items": {"type": "string"},
            },
            "answer_index": {"type": "integer"},
            "explanation": {"type": "string"},
            "choice_explanations": {
                "type": "array",
                "items": {"type": "string"},
            },
            "correct_reaction": {"type": "string"},
            "wrong_reaction": {"type": "string"},
            "source_chunk_ids": {
                "type": "array",
                "items": {"type": "string"},
            },
        },
        "required": [
            "type",
            "difficulty",
            "question",
            "choices",
            "answer_index",
            "explanation",
            "choice_explanations",
            "correct_reaction",
            "wrong_reaction",
            "source_chunk_ids",
        ],
        "additionalProperties": False,
    }
    return {
        "type": "json_schema",
        "name": "quiz_response",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "questions": {
                    "type": "array",
                    "items": question_schema,
                }
            },
            "required": ["questions"],
            "additionalProperties": False,
        },
    }


def _generate_character_profile_image(character) -> str:
    if _image_generation_disabled():
        return _test_profile_image_url()

    output_path = generated_dir / character.id / "profile.png"
    prompt = (
        "Create a single original 2D webtoon / manga style character portrait for a mobile app. "
        "High-quality anime key visual, polished commercial illustration, detailed linework and soft cinematic lighting. "
        "Design it as a landscape 1920x1080 mobile home hero frame that fills a wide rounded card. "
        "Near full upper-body composition, showing the character from head to around mid-thigh when possible, "
        "with delicate, carefully designed clothing details that reveal personality. "
        "No text, no logo. "
        f"Character persona: {character.persona_text}\n"
        f"Character appearance: {character.appearance_text}\n"
        f"{_anatomy_quality_prompt()} "
        "Composition: full head fully visible with generous top margin, face and hair not cropped, "
        "upper body visible, centered character, clean background, enough side margin for a horizontal mobile frame."
    )
    try:
        openai_image_client.generate_image(
            model=_image_model_for(),
            prompt=prompt,
            output_path=output_path,
            size="1920x1080",
            quality=get_env("OPENAI_IMAGE_QUALITY", "high") or "high",
        )
        return f"/generated/{character.id}/profile.png"
    except OpenAIProviderError as exc:
        raise HTTPException(status_code=502, detail=f"Character image generation failed: {exc}") from exc


def _generate_character_visual_novel_image(character) -> str:
    if _image_generation_disabled():
        return _test_visual_novel_image_url()

    output_path = generated_dir / character.id / "visual_novel.png"
    prompt = (
        "Create a separate original 2D webtoon / manga style character scene for a mobile visual novel chat screen. "
        "This must be a tall portrait mobile composition, approximately 9:16, not a landscape image. "
        "High-quality anime key visual, polished commercial illustration, detailed linework and soft cinematic lighting. "
        "Show the character clearly from head to at least knees, preferably near full body, standing naturally in the scene. "
        "The full head, hair, face, hands, and outfit must be visible without cropping. "
        "Use the full image as a clean illustration, with natural background details continuing behind the character. "
        "Do not draw blank reserved UI areas, translucent panels, dialogue boxes, bottom boxes, captions, or overlay frames. "
        "Keep the face in the upper-middle area, not near the bottom. "
        "Use a calm study-room, library, bedroom desk, or soft indoor background that matches the character. "
        "No text, no logo, no UI elements, no panels, no boxes, no speech bubbles, no extra characters. "
        f"Character persona: {character.persona_text}\n"
        f"Character appearance: {character.appearance_text}\n"
        f"{_anatomy_quality_prompt()} "
        "Composition: vertical mobile visual novel background, centered character, full body spacing, clean background, "
        "complete background from top to bottom with no artificial empty UI zone."
    )
    try:
        openai_image_client.generate_image(
            model=_image_model_for(),
            prompt=prompt,
            output_path=output_path,
            size=get_env("VISUAL_NOVEL_IMAGE_SIZE", "1024x1536") or "1024x1536",
            quality=get_env("OPENAI_IMAGE_QUALITY", "high") or "high",
        )
        return f"/generated/{character.id}/visual_novel.png"
    except OpenAIProviderError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Visual novel character image generation failed: {exc}",
        ) from exc


def _generate_character_expression_images(character) -> dict[str, str]:
    return _generate_expression_images_for_reference(
        character=character,
        reference_image_url=_current_character_image_url(character),
        source_key=_expression_source_key(character),
    )


def _generate_expression_images_for_reference(
    *,
    character,
    reference_image_url: str,
    source_key: str,
    strict: bool = False,
) -> dict[str, str]:
    fallback_urls = _expression_urls_for_image(reference_image_url)
    if _image_generation_disabled():
        if _test_generated_image_character_id():
            return _test_expression_image_urls(source_key, reference_image_url)
        return fallback_urls
    if not reference_image_url.startswith("/generated/"):
        return fallback_urls

    reference_image_path = _local_image_path(reference_image_url)
    expression_urls: dict[str, str] = {"neutral": reference_image_url}
    expression_jobs = [
        (key, direction)
        for key, direction in EXPRESSION_DEFINITIONS
        if key != "neutral"
    ]
    max_workers = min(_image_generation_parallelism(), len(expression_jobs))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(
                _generate_single_expression_image,
                character,
                source_key,
                key,
                direction,
                reference_image_path,
            ): key
            for key, direction in expression_jobs
        }
        for future in as_completed(futures):
            key = futures[future]
            try:
                expression_urls[key] = future.result()
            except OpenAIProviderError:
                if strict:
                    raise
                expression_urls[key] = reference_image_url
    return expression_urls


def _generate_single_expression_image(
    character,
    source_key: str,
    key: str,
    direction: str,
    reference_image_path: Path,
) -> str:
    output_path = generated_dir / character.id / f"expression_{source_key}_{key}.png"
    prompt = _expression_image_prompt(character, direction)
    _generate_costume_image_edit(
        prompt=prompt,
        reference_image_path=reference_image_path,
        output_path=output_path,
    )
    return f"/generated/{character.id}/{output_path.name}"


def _image_generation_parallelism() -> int:
    raw_value = get_env("IMAGE_GENERATION_PARALLELISM", "3") or "3"
    try:
        value = int(raw_value)
    except ValueError:
        value = 3
    return max(1, min(value, 6))


def _expression_urls_for_image(image_url: str) -> dict[str, str]:
    return {key: image_url for key, _ in EXPRESSION_DEFINITIONS}


def _has_all_expression_images(expression_image_urls: dict[str, str]) -> bool:
    return all(
        expression_image_urls.get(key)
        for key, _ in EXPRESSION_DEFINITIONS
    )


def _expression_fallback_images(character) -> dict[str, str]:
    fallback_url = _current_character_image_url(character)
    return _expression_urls_for_image(fallback_url)


def _current_character_image_url(character) -> str:
    return (
        character.base_image_url
        or character.visual_novel_image_url
        or character.profile_image_url
        or "/assets/default-character.png"
    )


def _current_expression_image_urls(character) -> dict[str, str]:
    fallback_url = _current_character_image_url(character)
    expression_urls = character.expression_image_urls or {}
    return {
        key: _current_expression_image_url_or_fallback(
            character,
            expression_urls.get(key),
            fallback_url,
        )
        for key, _ in EXPRESSION_DEFINITIONS
    }


def _current_expression_image_url_or_fallback(
    character,
    image_url: str | None,
    fallback_url: str,
) -> str:
    if not image_url:
        return fallback_url
    if image_url == fallback_url:
        return image_url
    expression_prefixes = [f"/generated/{character.id}/expression_"]
    test_character_id = _test_generated_image_character_id()
    if test_character_id:
        expression_prefixes.append(f"/generated/{test_character_id}/expression_")
    if not any(image_url.startswith(prefix) for prefix in expression_prefixes):
        return fallback_url
    source_key = _expression_source_key(character)
    current_expression_prefixes = [
        f"/generated/{character.id}/expression_{source_key}_",
    ]
    if test_character_id:
        current_expression_prefixes.append(
            f"/generated/{test_character_id}/expression_{source_key}_"
        )
    if any(image_url.startswith(prefix) for prefix in current_expression_prefixes):
        return image_url
    return fallback_url


def _refresh_character_expression_images(
    character_id: str,
    expected_outfit_id: str | None,
    expected_base_image_url: str | None,
) -> None:
    try:
        character = store.get_character(character_id)
    except KeyError:
        return
    if (
        character.current_outfit_id != expected_outfit_id
        or character.base_image_url != expected_base_image_url
    ):
        return
    character.expression_image_urls = _generate_character_expression_images(character)
    store.save_character(character)


def _expression_source_key(character) -> str:
    if character.current_outfit_id:
        for index, costume in enumerate(store.list_costumes(character.id), start=1):
            if costume.id == character.current_outfit_id:
                return f"costume{index}"
    return "default"


def _expression_image_prompt(character, expression_direction: str) -> str:
    return (
        "Using the provided reference image, create an expression-only edit for the same 2D webtoon / manga visual novel character. "
        "Preserve the exact same character identity, face structure, hairstyle, hair color, eye color, outfit, pose, body, lighting, background, camera framing, and art style. "
        "Change only the facial expression and tiny expression marks when requested. "
        "Do not change clothes, body pose, hands, arms, background, composition, or add extra characters. "
        "No text, logo, UI, speech bubble, dialogue box, caption, or panel. "
        f"{_anatomy_quality_prompt()} "
        f"Character appearance notes: {character.appearance_text}. "
        f"Expression direction: {expression_direction}."
    )


def _create_character_costume_records(character_id: str) -> list[CostumeRecord]:
    costumes = []
    for index, (name, unlock_score, prompt) in enumerate(
        COSTUME_DEFINITIONS,
        start=1,
    ):
        costumes.append(
            store.add_costume(
                CostumeRecord(
                    id=f"costume_{uuid4().hex[:12]}",
                    character_id=character_id,
                    name=name,
                    prompt=prompt,
                    unlock_score=unlock_score,
                )
            )
        )
    return costumes


def _generate_character_costumes(character_id: str) -> None:
    try:
        character = store.get_character(character_id)
    except KeyError:
        return
    for index, costume in enumerate(store.list_costumes(character_id), start=1):
        output_path = generated_dir / character_id / f"costume_{index}.png"
        try:
            costume.image_url = _generate_costume_image(
                character=character,
                costume=costume,
                output_path=output_path,
            )
            costume.expression_image_urls = _generate_expression_images_for_reference(
                character=character,
                reference_image_url=costume.image_url,
                source_key=f"costume{index}",
                strict=True,
            )
            costume.generation_status = "ready"
        except OpenAIProviderError:
            costume.generation_status = "failed"
            costume.image_url = None
            costume.expression_image_urls = {}
        store.save_costume(costume)


def _generate_costume_image(
    *,
    character,
    costume: CostumeRecord,
    output_path: Path,
) -> str:
    reference_image_path = _local_image_path(
        character.visual_novel_image_url
        or character.profile_image_url
        or character.base_image_url
    )
    prompt = _costume_image_prompt(character=character, costume=costume)
    try:
        _generate_costume_image_edit(
            prompt=prompt,
            reference_image_path=reference_image_path,
            output_path=output_path,
        )
    except OpenAIProviderError as exc:
        if not _should_retry_image_with_simple_prompt(str(exc)):
            raise
        _generate_costume_image_edit(
            prompt=_costume_image_simple_fallback_prompt(
                character=character,
                costume=costume,
            ),
            reference_image_path=reference_image_path,
            output_path=output_path,
        )
    return f"/generated/{character.id}/{output_path.name}"


def _costume_image_prompt(*, character, costume: CostumeRecord) -> str:
    return (
        "Using the provided reference image, create a new polished 2D webtoon / manga style mobile visual novel key visual. "
        "Preserve the exact same character identity, face, hairstyle, hair color, eye color, apparent age, body proportions, "
        "and illustration style. The result must unmistakably be the same person. "
        f"Character appearance notes: {character.appearance_text}. "
        "Change the clothing, small accessories, pose, lighting, and background only. "
        "Do not redesign the face, hair, eye color, or overall silhouette. "
        "Create a tall portrait mobile composition, approximately 9:16. "
        "Keep the full head, hair, face, hands, and clothing visible without cropping. "
        "Use the full image as one complete illustration with no reserved UI space. "
        "No text, logo, UI, panels, boxes, translucent overlays, speech bubbles, or extra characters. "
        f"{_anatomy_quality_prompt()}\n"
        f"Costume name: {costume.name}\n"
        f"Costume and scene direction: {costume.prompt}"
    )


def _costume_image_simple_fallback_prompt(
    *,
    character,
    costume: CostumeRecord,
) -> str:
    return (
        "Simple fallback image edit. Keep the exact same character identity and art style from the reference image. "
        "Change only the outfit and matching background. "
        "Tall 9:16 mobile anime illustration, full head and clothing visible, no text, logo, UI, or extra characters. "
        f"{_anatomy_quality_prompt()}\n"
        f"Character appearance: {character.appearance_text}\n"
        f"New outfit: {costume.name}. {costume.prompt}"
    )


def _anatomy_quality_prompt() -> str:
    return (
        "Anatomy quality requirements: draw exactly one person with exactly two arms, two hands, and five fingers per hand when fingers are visible. "
        "Use a simple relaxed pose with hands resting naturally at the sides, lightly clasped, or partly hidden by clothing or a book. "
        "Avoid complex hand gestures, crossed arms that obscure anatomy, overlapping duplicate limbs, mirrored ghost hands, extra fingers, extra arms, extra hands, detached hands, fused fingers, malformed fingers, and distorted wrists. "
        "If a hand would be difficult to draw clearly, simplify it or hide it naturally behind the body, sleeve, bag, book, or desk rather than adding ambiguous fingers."
    )


def _generate_costume_image_edit(
    *,
    prompt: str,
    reference_image_path: Path,
    output_path: Path,
) -> None:
    openai_image_client.generate_image_edit(
        model=_image_model_for(),
        prompt=prompt,
        reference_image_path=reference_image_path,
        output_path=output_path,
        size=get_env("VISUAL_NOVEL_IMAGE_SIZE", "1024x1536") or "1024x1536",
        quality=get_env("OPENAI_IMAGE_QUALITY", "high") or "high",
        input_fidelity=get_env("OPENAI_IMAGE_INPUT_FIDELITY", "high") or "high",
    )


def _local_image_path(image_url: str | None) -> Path:
    if not image_url:
        raise OpenAIProviderError("Reference image URL is missing.")
    if image_url.startswith("/generated/"):
        relative_path = image_url.removeprefix("/generated/")
        image_path = generated_dir / relative_path
    else:
        raise OpenAIProviderError(
            "Reference image must be a locally generated image before creating outfit variants."
        )
    if not image_path.exists():
        raise OpenAIProviderError(f"Reference image file does not exist: {image_path}")
    return image_path


def _expression_for_chat(user_message: str, assistant_reply: str) -> str:
    text = f"{user_message} {assistant_reply}".lower()
    checks: tuple[tuple[str, tuple[str, ...]], ...] = (
        (
            "angry",
            (
                "화나",
                "짜증",
                "빡",
                "개빡",
                "열받",
                "싫어",
                "미워",
                "꺼져",
                "닥쳐",
                "바보",
                "멍청",
                "욕",
                "시발",
                "씨발",
                "좆",
            ),
        ),
        (
            "sad",
            (
                "슬퍼",
                "우울",
                "힘들",
                "속상",
                "외로",
                "울고",
                "눈물",
                "죽고",
                "포기",
                "망했",
            ),
        ),
        (
            "shy",
            (
                "부끄",
                "수줍",
                "설레",
                "귀엽",
                "예쁘",
                "좋아해",
                "사랑",
            ),
        ),
        (
            "surprised",
            (
                "헐",
                "대박",
                "진짜?",
                "뭐야",
                "놀랐",
                "말도 안",
                "어떻게",
            ),
        ),
        (
            "happy",
            (
                "좋아",
                "고마",
                "감사",
                "잘했",
                "기뻐",
                "행복",
                "ㅋㅋ",
                "ㅎㅎ",
            ),
        ),
    )
    for expression, keywords in checks:
        if any(keyword in text for keyword in keywords):
            return expression
    return "neutral"


def _normalize_expression(value: str | None) -> str | None:
    if not value:
        return None
    normalized = value.strip().lower()
    normalized = normalized.replace("`", "").replace('"', "").replace("'", "")
    normalized = normalized.split()[0] if normalized.split() else ""
    normalized = normalized.strip(".,:;[](){}")
    aliases = {
        "normal": "neutral",
        "calm": "neutral",
        "smile": "happy",
        "joy": "happy",
        "joyful": "happy",
        "embarrassed": "shy",
        "blush": "shy",
        "mad": "angry",
        "annoyed": "angry",
        "upset": "sad",
        "surprise": "surprised",
        "shocked": "surprised",
    }
    normalized = aliases.get(normalized, normalized)
    allowed = {key for key, _ in EXPRESSION_DEFINITIONS}
    return normalized if normalized in allowed else None


def _expression_image_url(character, expression: str) -> str | None:
    expression_urls = _current_expression_image_urls(character)
    return (
        expression_urls.get(expression)
        or expression_urls.get("neutral")
        or character.base_image_url
        or character.visual_novel_image_url
        or character.profile_image_url
    )


def _compact_interaction_summary(previous_summary: str, messages) -> str:
    previous_summary = (previous_summary or "").strip()
    if previous_summary == "No prior interaction yet.":
        previous_summary = ""
    compact_lines = [
        f"{message.role}: {_compact_message_text(message.text)}"
        for message in messages
        if message.text.strip()
    ]
    parts = []
    if previous_summary:
        parts.append(previous_summary)
    if compact_lines:
        parts.append("[Compacted older chat]\n" + "\n".join(compact_lines))
    summary = "\n".join(parts).strip()
    if not summary:
        return "No prior interaction yet."
    return summary[-2400:]


def _compact_message_text(text: str) -> str:
    normalized = " ".join(text.split())
    if len(normalized) <= 180:
        return normalized
    return normalized[:177] + "..."
