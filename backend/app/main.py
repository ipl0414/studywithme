from __future__ import annotations

from datetime import date
from pathlib import Path
from uuid import uuid4

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
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
)
from .store import CostumeRecord, store


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
QUIZ_AFFINITY_DAILY_LIMIT = 24
CHECKIN_REWARD_DELTA = 3
COSTUME_DEFINITIONS: tuple[tuple[str, int, str], ...] = (
    (
        "캠퍼스 카디건",
        25,
        "a refined campus cardigan outfit with layered shirt and subtle accessories, calm university library background",
    ),
    (
        "포근한 홈웨어",
        50,
        "a cozy premium knit home outfit with soft textures, warm evening bedroom desk background",
    ),
    (
        "특별한 외출복",
        75,
        "an elegant special-day outing outfit with detailed tailoring and tasteful accessories, luminous city evening background",
    ),
)


def demo_user_id() -> str:
    return store.demo_user_id


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


def _image_generation_disabled() -> bool:
    return (get_env("TEST_NO_IMAGE", "no") or "no").strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


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


@app.post("/auth/external", response_model=AuthResponse)
def login_with_external_provider(request: ExternalLoginRequest) -> AuthResponse:
    user = store.create_user_from_external_token(request.access_token)
    return AuthResponse(access_token=f"demo-token-{user.id}", user_id=user.id)


@app.patch("/profile")
def update_profile(request: ProfileUpdateRequest) -> dict[str, str]:
    profile = store.upsert_profile(demo_user_id(), request.department, request.study_goal)
    return {
        "user_id": profile.user_id,
        "department": profile.department,
        "study_goal": profile.study_goal,
    }


@app.post("/characters", response_model=CharacterResponse)
def create_character(
    request: CharacterCreateRequest,
    background_tasks: BackgroundTasks,
) -> CharacterResponse:
    try:
        character = store.create_character(
            demo_user_id(),
            request.name,
            request.persona_text,
            request.appearance_text,
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    character.profile_image_url = _generate_character_profile_image(character)
    character.visual_novel_image_url = _generate_character_visual_novel_image(character)
    character.base_image_url = character.visual_novel_image_url
    costumes = _create_character_costume_records(character.id)
    if _image_generation_disabled():
        for costume in costumes:
            costume.image_url = "/assets/default-outfit.png"
            costume.generation_status = "ready"
    else:
        background_tasks.add_task(_generate_character_costumes, character.id)
    return character_response(character)


@app.get("/characters", response_model=list[CharacterResponse])
def list_characters() -> list[CharacterResponse]:
    return [character_response(character) for character in store.list_characters(demo_user_id())]


@app.get("/characters/current", response_model=CharacterResponse)
def get_current_character() -> CharacterResponse:
    character = store.get_current_character(demo_user_id())
    if character is None:
        raise HTTPException(status_code=404, detail="No character has been created.")
    return character_response(character)


@app.post("/characters/{character_id}/select", response_model=CharacterResponse)
def select_character(character_id: str) -> CharacterResponse:
    try:
        character = store.select_character(demo_user_id(), character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    return character_response(character)


@app.post("/characters/{character_id}/equip-default", response_model=CharacterResponse)
def equip_default_character_image(character_id: str) -> CharacterResponse:
    try:
        character = store.get_character(character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    character.base_image_url = (
        character.visual_novel_image_url
        or character.profile_image_url
        or "/assets/default-character.png"
    )
    character.current_outfit_id = None
    return character_response(character)


@app.post("/characters/{character_id}/visual-novel-image", response_model=CharacterResponse)
def generate_visual_novel_character_image(character_id: str) -> CharacterResponse:
    try:
        character = store.get_character(character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
    character.visual_novel_image_url = _generate_character_visual_novel_image(character)
    if character.current_outfit_id is None:
        character.base_image_url = character.visual_novel_image_url
    return character_response(character)


@app.post("/materials", response_model=MaterialResponse)
def create_material(request: MaterialCreateRequest) -> MaterialResponse:
    temp_material_id = f"mat_{uuid4().hex[:12]}"
    chunks = PdfChunker().chunk_pages(temp_material_id, request.pages)
    material = store.create_material(demo_user_id(), request.title, chunks, temp_material_id)
    return material_response(material)


@app.get("/materials", response_model=list[MaterialResponse])
def list_materials() -> list[MaterialResponse]:
    return [material_response(material) for material in store.list_materials(demo_user_id())]


@app.delete("/materials/{material_id}")
def delete_material(material_id: str) -> dict[str, str]:
    try:
        store.delete_material(demo_user_id(), material_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Material not found.") from exc
    return {"status": "deleted", "id": material_id}


@app.post("/materials/upload", response_model=MaterialResponse)
async def upload_material(file: UploadFile = File(...)) -> MaterialResponse:
    filename = file.filename or "uploaded.pdf"
    if not filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF uploads are supported.")
    pdf_bytes = await file.read()
    try:
        pages = pdf_text_extractor.extract_pages(pdf_bytes)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Could not read text from the PDF.") from exc
    if not pages:
        raise HTTPException(status_code=400, detail="No extractable text was found in the PDF.")

    material_id = f"mat_{uuid4().hex[:12]}"
    chunks = PdfChunker().chunk_pages(material_id, pages)
    material = store.create_material(demo_user_id(), filename, chunks, material_id)
    return material_response(material)


@app.post("/chat/messages", response_model=ChatMessageResponse)
def send_chat_message(request: ChatMessageRequest) -> ChatMessageResponse:
    character = store.get_character(request.character_id)
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
        materials = _get_materials_or_404(selected_material_ids)
        all_chunks = [chunk for material in materials for chunk in material.chunks]
        source_chunks = rag_retriever.search(all_chunks, request.message, limit=6)
        source_chunk_ids = [chunk.id for chunk in source_chunks]
        material_context = "\n\n".join(
            f"[{chunk.id} page {chunk.page_number}]\n{chunk.text}" for chunk in source_chunks
        )
    recent_history = store.list_chat_messages(request.character_id, limit=8)
    conversation_history = "\n".join(
        f"{message.role}: {message.text}" for message in recent_history
    )

    input_text = (
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

    environment_box, reply = _parse_chat_environment_response(raw_reply)
    store.add_chat_message(request.character_id, "user", request.message)
    if environment_box:
        store.add_chat_message(request.character_id, "environment", environment_box)
    store.add_chat_message(request.character_id, "assistant", reply)
    character.interaction_summary = _summarize_chat_history(store.list_chat_messages(request.character_id, limit=10))
    return ChatMessageResponse(
        reply=reply,
        environment_box=environment_box,
        model=model,
        system_prompt_preview=system_prompt[:800],
        source_chunk_ids=source_chunk_ids,
    )


@app.get("/chat/messages", response_model=list[ChatHistoryMessageResponse])
def list_chat_messages(character_id: str) -> list[ChatHistoryMessageResponse]:
    return [
        ChatHistoryMessageResponse(role=message.role, text=message.text)
        for message in store.list_chat_messages(character_id)
    ]


@app.post("/quizzes/generate", response_model=QuizResponse)
def generate_quiz(request: QuizGenerateRequest) -> QuizResponse:
    selected_material_ids = _selected_material_ids(request.material_id, request.material_ids)
    if not selected_material_ids:
        raise HTTPException(status_code=400, detail="At least one material is required.")
    materials = _get_materials_or_404(selected_material_ids)
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
        character = store.get_character(request.character_id)
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
def apply_affinity_event(request: AffinityEventRequest) -> AffinityResponse:
    character = store.get_character(request.character_id)
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
        remaining = max(0, QUIZ_AFFINITY_DAILY_LIMIT - character.quiz_affinity_gained_today)
        delta = min(delta, remaining)
        if request.reward_key:
            character.claimed_affinity_reward_keys.add(request.reward_key)
        if delta <= 0:
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
        event_type=request.event_type,
        delta=delta,
    )
    character.affinity_score = result.new_score
    character.relationship_stage = result.current_stage.key
    if request.event_type.startswith("quiz_"):
        character.quiz_affinity_gained_today += result.new_score - result.previous_score
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
def get_affinity_status(character_id: str) -> AffinityStatusResponse:
    character = store.get_character(character_id)
    _reset_daily_affinity_if_needed(character, date.today())
    stage = affinity_service.stage_for(character.affinity_score)
    return AffinityStatusResponse(
        score=character.affinity_score,
        relationship_stage=stage.key,
        relationship_stage_label=stage.label,
        quiz_affinity_gained_today=character.quiz_affinity_gained_today,
        quiz_affinity_daily_limit=QUIZ_AFFINITY_DAILY_LIMIT,
        quiz_affinity_remaining_today=max(
            0, QUIZ_AFFINITY_DAILY_LIMIT - character.quiz_affinity_gained_today
        ),
        checkin_available=character.last_checkin_date != date.today(),
        checkin_reward_delta=CHECKIN_REWARD_DELTA,
    )


@app.post("/affinity/checkin", response_model=AffinityResponse)
def apply_checkin_affinity(request: CharacterIdRequest) -> AffinityResponse:
    character = store.get_character(request.character_id)
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
def list_costumes(character_id: str) -> list[CostumeResponse]:
    try:
        character = store.get_character(character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Character not found.") from exc
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
) -> CharacterResponse:
    try:
        costume = store.get_costume(costume_id)
        character = store.get_character(request.character_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Costume not found.") from exc
    if costume.character_id != character.id:
        raise HTTPException(status_code=404, detail="Costume not found.")
    if character.affinity_score < costume.unlock_score:
        raise HTTPException(status_code=403, detail="Costume is still locked.")
    if costume.generation_status != "ready" or not costume.image_url:
        raise HTTPException(status_code=409, detail="Costume image is not ready.")
    character.base_image_url = costume.image_url
    character.current_outfit_id = costume.id
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


def _parse_chat_environment_response(text: str) -> tuple[str, str]:
    import re

    environment_box = _extract_tagged_section(text, "ENVIRONMENT_BOX")
    reply = _extract_tagged_section(text, "CHARACTER_REPLY")
    if not reply:
        reply = _remove_known_chat_tags(text)
        if environment_box:
            reply = reply.replace(environment_box, "").strip()
    if not reply:
        reply = "...잠깐, 방금 흐름 이상했지. 다시 말해봐."
    return environment_box, reply


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
        r"\[/?(?:ENVIRONMENT_BOX|CHARACTER_REPLY)\]",
        text[content_start:],
        flags=re.IGNORECASE,
    )
    content_end = content_start + next_known_tag.start() if next_known_tag else len(text)
    return text[content_start:content_end].strip()


def _remove_known_chat_tags(text: str) -> str:
    import re

    return re.sub(
        r"\[/?(?:ENVIRONMENT_BOX|CHARACTER_REPLY)\]",
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
        quiz_affinity_daily_limit=QUIZ_AFFINITY_DAILY_LIMIT,
        quiz_affinity_remaining_today=max(
            0, QUIZ_AFFINITY_DAILY_LIMIT - character.quiz_affinity_gained_today
        ),
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
    is_unlocked = character.affinity_score >= costume.unlock_score
    return CostumeResponse(
        id=costume.id,
        name=costume.name,
        unlock_score=costume.unlock_score,
        is_unlocked=is_unlocked,
        is_equipped=character.current_outfit_id == costume.id,
        generation_status=costume.generation_status,
        image_url=costume.image_url if is_unlocked else None,
    )


def _selected_material_ids(material_id: str | None, material_ids: list[str]) -> list[str]:
    selected: list[str] = []
    if material_id:
        selected.append(material_id)
    selected.extend(material_ids)
    return list(dict.fromkeys(item for item in selected if item))


def _get_materials_or_404(material_ids: list[str]):
    materials = []
    for material_id in material_ids:
        try:
            material = store.get_material(material_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=f"Material not found: {material_id}") from exc
        if material.user_id != demo_user_id():
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
        return "/assets/default-character.png"

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
        return "/assets/default-character.png"

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
            costume.generation_status = "ready"
        except OpenAIProviderError:
            costume.generation_status = "failed"
            costume.image_url = None


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
        "No text, logo, UI, panels, boxes, translucent overlays, speech bubbles, or extra characters.\n"
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
        "Tall 9:16 mobile anime illustration, full head and clothing visible, no text, logo, UI, or extra characters.\n"
        f"Character appearance: {character.appearance_text}\n"
        f"New outfit: {costume.name}. {costume.prompt}"
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


def _summarize_chat_history(messages) -> str:
    if not messages:
        return "No prior interaction yet."
    return "Recent conversation:\n" + "\n".join(
        f"{message.role}: {message.text[:240]}" for message in messages
    )
