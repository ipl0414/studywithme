from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Dict, List, Optional
from uuid import uuid4

from .domain import PdfChunk


@dataclass
class UserRecord:
    id: str
    external_auth_id: str
    display_name: str


@dataclass
class ProfileRecord:
    user_id: str
    department: str
    study_goal: str


@dataclass
class CharacterRecord:
    id: str
    user_id: str
    name: str
    persona_text: str
    appearance_text: str
    relationship_stage: str = "shy"
    affinity_score: int = 0
    base_image_url: Optional[str] = None
    profile_image_url: Optional[str] = None
    visual_novel_image_url: Optional[str] = None
    current_outfit_id: Optional[str] = None
    interaction_summary: str = "No prior interaction yet."
    claimed_affinity_reward_keys: set[str] = field(default_factory=set)
    quiz_affinity_date: Optional[date] = None
    quiz_affinity_gained_today: int = 0
    last_checkin_date: Optional[date] = None


@dataclass
class MaterialRecord:
    id: str
    user_id: str
    title: str
    status: str
    chunks: List[PdfChunk] = field(default_factory=list)


@dataclass
class ChatMessageRecord:
    character_id: str
    role: str
    text: str


@dataclass
class CostumeRecord:
    id: str
    character_id: str
    name: str
    prompt: str
    unlock_score: int
    image_url: Optional[str] = None
    generation_status: str = "generating"


class InMemoryStore:
    max_characters_per_user = 3

    def __init__(self):
        self.users: Dict[str, UserRecord] = {}
        self.profiles: Dict[str, ProfileRecord] = {}
        self.characters: Dict[str, CharacterRecord] = {}
        self.current_character_by_user: Dict[str, str] = {}
        self.materials: Dict[str, MaterialRecord] = {}
        self.chat_messages: List[ChatMessageRecord] = []
        self.costumes: Dict[str, CostumeRecord] = {}
        self.demo_user_id = self._seed_demo_user()

    def _seed_demo_user(self) -> str:
        user_id = "demo_user"
        self.users[user_id] = UserRecord(
            id=user_id,
            external_auth_id="demo",
            display_name="Demo Student",
        )
        return user_id

    def create_user_from_external_token(self, token: str) -> UserRecord:
        user_id = f"user_{uuid4().hex[:12]}"
        user = UserRecord(
            id=user_id,
            external_auth_id=f"external_{abs(hash(token))}",
            display_name="External User",
        )
        self.users[user_id] = user
        return user

    def upsert_profile(self, user_id: str, department: str, study_goal: str) -> ProfileRecord:
        profile = ProfileRecord(user_id=user_id, department=department, study_goal=study_goal)
        self.profiles[user_id] = profile
        return profile

    def create_character(self, user_id: str, name: str, persona_text: str, appearance_text: str) -> CharacterRecord:
        if len(self.list_characters(user_id)) >= self.max_characters_per_user:
            raise ValueError("Character profile limit reached.")
        character = CharacterRecord(
            id=f"char_{uuid4().hex[:12]}",
            user_id=user_id,
            name=name,
            persona_text=persona_text,
            appearance_text=appearance_text,
            base_image_url="/assets/default-character.png",
            profile_image_url="/assets/default-character.png",
            visual_novel_image_url="/assets/default-character.png",
        )
        self.characters[character.id] = character
        self.current_character_by_user[user_id] = character.id
        return character

    def get_character(self, character_id: str) -> CharacterRecord:
        return self.characters[character_id]

    def list_characters(self, user_id: str) -> List[CharacterRecord]:
        return [character for character in self.characters.values() if character.user_id == user_id]

    def get_current_character(self, user_id: str) -> Optional[CharacterRecord]:
        current_id = self.current_character_by_user.get(user_id)
        if current_id:
            return self.characters.get(current_id)
        characters = self.list_characters(user_id)
        return characters[0] if characters else None

    def select_character(self, user_id: str, character_id: str) -> CharacterRecord:
        character = self.get_character(character_id)
        if character.user_id != user_id:
            raise KeyError(character_id)
        self.current_character_by_user[user_id] = character_id
        return character

    def update_character(
        self,
        user_id: str,
        character_id: str,
        name: Optional[str] = None,
        persona_text: Optional[str] = None,
        appearance_text: Optional[str] = None,
    ) -> CharacterRecord:
        character = self.get_character(character_id)
        if character.user_id != user_id:
            raise KeyError(character_id)
        if name is not None:
            character.name = name
        if persona_text is not None:
            character.persona_text = persona_text
        if appearance_text is not None:
            character.appearance_text = appearance_text
        return character

    def delete_character(self, user_id: str, character_id: str) -> CharacterRecord:
        character = self.get_character(character_id)
        if character.user_id != user_id:
            raise KeyError(character_id)
        # Remove related costumes and chat history for this character.
        for costume_id in [
            costume.id
            for costume in self.costumes.values()
            if costume.character_id == character_id
        ]:
            self.costumes.pop(costume_id, None)
        self.chat_messages = [
            message
            for message in self.chat_messages
            if message.character_id != character_id
        ]
        removed = self.characters.pop(character_id)
        # Repoint the user's current character if it was the deleted one.
        if self.current_character_by_user.get(user_id) == character_id:
            remaining = self.list_characters(user_id)
            if remaining:
                self.current_character_by_user[user_id] = remaining[0].id
            else:
                self.current_character_by_user.pop(user_id, None)
        return removed

    def create_material(
        self,
        user_id: str,
        title: str,
        chunks: List[PdfChunk],
        material_id: Optional[str] = None,
    ) -> MaterialRecord:
        material = MaterialRecord(
            id=material_id or f"mat_{uuid4().hex[:12]}",
            user_id=user_id,
            title=title,
            status="ready",
            chunks=chunks,
        )
        self.materials[material.id] = material
        return material

    def get_material(self, material_id: str) -> MaterialRecord:
        return self.materials[material_id]

    def list_materials(self, user_id: str) -> List[MaterialRecord]:
        return [material for material in self.materials.values() if material.user_id == user_id]

    def delete_material(self, user_id: str, material_id: str) -> MaterialRecord:
        material = self.get_material(material_id)
        if material.user_id != user_id:
            raise KeyError(material_id)
        return self.materials.pop(material_id)

    def add_chat_message(self, character_id: str, role: str, text: str) -> ChatMessageRecord:
        message = ChatMessageRecord(character_id=character_id, role=role, text=text)
        self.chat_messages.append(message)
        return message

    def list_chat_messages(self, character_id: str, limit: Optional[int] = None) -> List[ChatMessageRecord]:
        messages = [message for message in self.chat_messages if message.character_id == character_id]
        if limit is None:
            return messages
        return messages[-limit:]

    def add_costume(self, costume: CostumeRecord) -> CostumeRecord:
        self.costumes[costume.id] = costume
        return costume

    def get_costume(self, costume_id: str) -> CostumeRecord:
        return self.costumes[costume_id]

    def list_costumes(self, character_id: str) -> List[CostumeRecord]:
        return sorted(
            (
                costume
                for costume in self.costumes.values()
                if costume.character_id == character_id
            ),
            key=lambda costume: costume.unlock_score,
        )


store = InMemoryStore()
