from __future__ import annotations

from datetime import date
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class ExternalLoginRequest(BaseModel):
    access_token: str = Field(..., min_length=1)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str


class ProfileUpdateRequest(BaseModel):
    department: str = Field(..., min_length=1)
    study_goal: str = Field(..., min_length=1)


class CharacterCreateRequest(BaseModel):
    name: str = Field(default="Tutor", min_length=1)
    persona_text: str = Field(..., min_length=1)
    appearance_text: str = Field(..., min_length=1)


class CharacterResponse(BaseModel):
    id: str
    name: str
    persona_text: str
    appearance_text: str
    relationship_stage: str
    affinity_score: int = 0
    base_image_url: Optional[str] = None
    profile_image_url: Optional[str] = None
    visual_novel_image_url: Optional[str] = None
    current_outfit_id: Optional[str] = None


class MaterialCreateRequest(BaseModel):
    title: str = Field(..., min_length=1)
    pages: List[str] = Field(..., min_length=1)


class MaterialResponse(BaseModel):
    id: str
    title: str
    status: str
    chunk_count: int


class ChatMessageRequest(BaseModel):
    character_id: str
    mode: str = "daily_chat"
    message: str = Field(..., min_length=1)
    material_id: Optional[str] = None
    material_ids: List[str] = Field(default_factory=list)


class ChatMessageResponse(BaseModel):
    reply: str
    environment_box: str = ""
    model: str
    system_prompt_preview: str
    source_chunk_ids: List[str] = []


class ChatHistoryMessageResponse(BaseModel):
    role: str
    text: str


class QuizGenerateRequest(BaseModel):
    material_id: Optional[str] = None
    material_ids: List[str] = Field(default_factory=list)
    question_count: int = Field(default=0, ge=0, le=10)
    character_id: Optional[str] = None


class QuizResponse(BaseModel):
    id: str
    material_id: str
    material_ids: List[str] = Field(default_factory=list)
    title: str
    questions: List[Dict[str, Any]]
    model: str


class AffinityEventRequest(BaseModel):
    character_id: str
    event_type: str
    delta: int = Field(..., ge=-100, le=100)
    event_date: Optional[date] = None
    reward_key: Optional[str] = None


class AffinityResponse(BaseModel):
    score: int
    relationship_stage: str
    relationship_stage_label: str
    unlocked_costume_ids: List[str] = Field(default_factory=list)
    affinity_applied: bool = True
    applied_delta: int = 0
    quiz_affinity_gained_today: int = 0
    quiz_affinity_daily_limit: int = 0
    quiz_affinity_remaining_today: int = 0
    checkin_available: bool = True


class AffinityStatusResponse(BaseModel):
    score: int
    relationship_stage: str
    relationship_stage_label: str
    quiz_affinity_gained_today: int
    quiz_affinity_daily_limit: int
    quiz_affinity_remaining_today: int
    checkin_available: bool
    checkin_reward_delta: int


class CharacterIdRequest(BaseModel):
    character_id: str


class CostumeResponse(BaseModel):
    id: str
    name: str
    unlock_score: int
    is_unlocked: bool
    is_equipped: bool
    generation_status: str
    image_url: Optional[str] = None


class EquipCostumeRequest(BaseModel):
    character_id: str
