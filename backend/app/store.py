from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
import json
import os
from pathlib import Path
import sqlite3
from threading import RLock
from typing import Dict, List, Optional
from uuid import uuid4

from .config import backend_root, load_backend_env
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
class SessionRecord:
    token: str
    user_id: str


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
    expression_image_urls: Dict[str, str] = field(default_factory=dict)
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
    expression_image_urls: Dict[str, str] = field(default_factory=dict)
    generation_status: str = "generating"


class SQLiteStore:
    max_characters_per_user = 3
    max_chat_messages_per_character = 20

    def __init__(self, db_path: str | Path | None = None):
        load_backend_env()
        configured_path = db_path or os.environ.get("SQLITE_DB_PATH")
        self.db_path = Path(configured_path) if configured_path else backend_root() / "app_data.sqlite3"
        if not self.db_path.is_absolute():
            self.db_path = backend_root() / self.db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = RLock()
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        self._migrate()
        self.demo_user_id = self._seed_demo_user()

    def _migrate(self) -> None:
        with self.conn:
            self.conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    external_auth_id TEXT NOT NULL,
                    display_name TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS profiles (
                    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                    department TEXT NOT NULL,
                    study_goal TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sessions (
                    token TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS characters (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    persona_text TEXT NOT NULL,
                    appearance_text TEXT NOT NULL,
                    relationship_stage TEXT NOT NULL,
                    affinity_score INTEGER NOT NULL,
                    base_image_url TEXT,
                    profile_image_url TEXT,
                    visual_novel_image_url TEXT,
                    expression_image_urls TEXT NOT NULL,
                    current_outfit_id TEXT,
                    interaction_summary TEXT NOT NULL,
                    claimed_affinity_reward_keys TEXT NOT NULL,
                    quiz_affinity_date TEXT,
                    quiz_affinity_gained_today INTEGER NOT NULL,
                    last_checkin_date TEXT
                );
                CREATE TABLE IF NOT EXISTS current_characters (
                    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                    character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS materials (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    chunks TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS chat_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    text TEXT NOT NULL,
                    created_order INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS costumes (
                    id TEXT PRIMARY KEY,
                    character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    prompt TEXT NOT NULL,
                    unlock_score INTEGER NOT NULL,
                    image_url TEXT,
                    expression_image_urls TEXT NOT NULL,
                    generation_status TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_characters_user_id ON characters(user_id);
                CREATE INDEX IF NOT EXISTS idx_materials_user_id ON materials(user_id);
                CREATE INDEX IF NOT EXISTS idx_chat_messages_character_id ON chat_messages(character_id, created_order);
                CREATE INDEX IF NOT EXISTS idx_costumes_character_id ON costumes(character_id, unlock_score);
                """
            )

    @property
    def users(self) -> Dict[str, UserRecord]:
        return {user.id: user for user in self.list_users()}

    @property
    def profiles(self) -> Dict[str, ProfileRecord]:
        rows = self.conn.execute("SELECT * FROM profiles").fetchall()
        return {row["user_id"]: self._row_to_profile(row) for row in rows}

    @property
    def characters(self) -> Dict[str, CharacterRecord]:
        rows = self.conn.execute("SELECT * FROM characters").fetchall()
        return {row["id"]: self._row_to_character(row) for row in rows}

    @property
    def current_character_by_user(self) -> Dict[str, str]:
        rows = self.conn.execute("SELECT * FROM current_characters").fetchall()
        return {row["user_id"]: row["character_id"] for row in rows}

    @property
    def materials(self) -> Dict[str, MaterialRecord]:
        rows = self.conn.execute("SELECT * FROM materials").fetchall()
        return {row["id"]: self._row_to_material(row) for row in rows}

    @property
    def chat_messages(self) -> List[ChatMessageRecord]:
        rows = self.conn.execute(
            "SELECT * FROM chat_messages ORDER BY created_order ASC, id ASC"
        ).fetchall()
        return [self._row_to_chat_message(row) for row in rows]

    @chat_messages.setter
    def chat_messages(self, messages: List[ChatMessageRecord]) -> None:
        with self._lock, self.conn:
            self.conn.execute("DELETE FROM chat_messages")
            self._insert_chat_messages(messages)

    @property
    def costumes(self) -> Dict[str, CostumeRecord]:
        rows = self.conn.execute("SELECT * FROM costumes").fetchall()
        return {row["id"]: self._row_to_costume(row) for row in rows}

    def _seed_demo_user(self) -> str:
        user_id = "demo_user"
        user = UserRecord(
            id=user_id,
            external_auth_id="demo",
            display_name="Demo Student",
        )
        self.save_user(user)
        return user_id

    def list_users(self) -> List[UserRecord]:
        rows = self.conn.execute("SELECT * FROM users").fetchall()
        return [self._row_to_user(row) for row in rows]

    def create_user_from_external_token(self, token: str) -> UserRecord:
        existing = self.get_user_by_external_auth_id(f"external_{abs(hash(token))}")
        if existing is not None:
            return existing
        user_id = f"user_{uuid4().hex[:12]}"
        user = UserRecord(
            id=user_id,
            external_auth_id=f"external_{abs(hash(token))}",
            display_name="External User",
        )
        self.save_user(user)
        return user

    def get_user(self, user_id: str) -> UserRecord:
        row = self.conn.execute(
            "SELECT * FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise KeyError(user_id)
        return self._row_to_user(row)

    def get_user_by_external_auth_id(self, external_auth_id: str) -> Optional[UserRecord]:
        row = self.conn.execute(
            "SELECT * FROM users WHERE external_auth_id = ?",
            (external_auth_id,),
        ).fetchone()
        return self._row_to_user(row) if row else None

    def save_user(self, user: UserRecord) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO users (id, external_auth_id, display_name)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    external_auth_id = excluded.external_auth_id,
                    display_name = excluded.display_name
                """,
                (user.id, user.external_auth_id, user.display_name),
            )

    def create_session(self, user_id: str, token: Optional[str] = None) -> SessionRecord:
        self.get_user(user_id)
        session = SessionRecord(
            token=token or f"session_{uuid4().hex}",
            user_id=user_id,
        )
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO sessions (token, user_id)
                VALUES (?, ?)
                ON CONFLICT(token) DO UPDATE SET
                    user_id = excluded.user_id
                """,
                (session.token, session.user_id),
            )
        return session

    def get_user_id_for_session(self, token: str) -> Optional[str]:
        row = self.conn.execute(
            "SELECT user_id FROM sessions WHERE token = ?",
            (token,),
        ).fetchone()
        return row["user_id"] if row else None

    def upsert_profile(self, user_id: str, department: str, study_goal: str) -> ProfileRecord:
        profile = ProfileRecord(user_id=user_id, department=department, study_goal=study_goal)
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO profiles (user_id, department, study_goal)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET
                    department = excluded.department,
                    study_goal = excluded.study_goal
                """,
                (profile.user_id, profile.department, profile.study_goal),
            )
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
            expression_image_urls={
                "neutral": "/assets/default-character.png",
            },
        )
        self.save_character(character)
        self._set_current_character(user_id, character.id)
        return character

    def get_character(self, character_id: str) -> CharacterRecord:
        row = self.conn.execute(
            "SELECT * FROM characters WHERE id = ?",
            (character_id,),
        ).fetchone()
        if row is None:
            raise KeyError(character_id)
        return self._row_to_character(row)

    def list_characters(self, user_id: str) -> List[CharacterRecord]:
        rows = self.conn.execute(
            "SELECT * FROM characters WHERE user_id = ? ORDER BY rowid ASC",
            (user_id,),
        ).fetchall()
        return [self._row_to_character(row) for row in rows]

    def get_current_character(self, user_id: str) -> Optional[CharacterRecord]:
        row = self.conn.execute(
            "SELECT character_id FROM current_characters WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        current_id = row["character_id"] if row else None
        if current_id:
            try:
                return self.get_character(current_id)
            except KeyError:
                pass
        characters = self.list_characters(user_id)
        return characters[0] if characters else None

    def select_character(self, user_id: str, character_id: str) -> CharacterRecord:
        character = self.get_character(character_id)
        if character.user_id != user_id:
            raise KeyError(character_id)
        self._set_current_character(user_id, character_id)
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
        self.save_character(character)
        return character

    def delete_character(self, user_id: str, character_id: str) -> CharacterRecord:
        character = self.get_character(character_id)
        if character.user_id != user_id:
            raise KeyError(character_id)
        with self._lock, self.conn:
            current_row = self.conn.execute(
                "SELECT character_id FROM current_characters WHERE user_id = ?",
                (user_id,),
            ).fetchone()
            was_current = current_row is not None and current_row["character_id"] == character_id
            self.conn.execute("DELETE FROM characters WHERE id = ?", (character_id,))
            if was_current:
                remaining = self.list_characters(user_id)
                if remaining:
                    self._set_current_character(user_id, remaining[0].id)
                else:
                    self.conn.execute(
                        "DELETE FROM current_characters WHERE user_id = ?",
                        (user_id,),
                    )
        return character

    def save_character(self, character: CharacterRecord) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO characters (
                    id, user_id, name, persona_text, appearance_text,
                    relationship_stage, affinity_score, base_image_url,
                    profile_image_url, visual_novel_image_url, expression_image_urls,
                    current_outfit_id, interaction_summary,
                    claimed_affinity_reward_keys, quiz_affinity_date,
                    quiz_affinity_gained_today, last_checkin_date
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    user_id = excluded.user_id,
                    name = excluded.name,
                    persona_text = excluded.persona_text,
                    appearance_text = excluded.appearance_text,
                    relationship_stage = excluded.relationship_stage,
                    affinity_score = excluded.affinity_score,
                    base_image_url = excluded.base_image_url,
                    profile_image_url = excluded.profile_image_url,
                    visual_novel_image_url = excluded.visual_novel_image_url,
                    expression_image_urls = excluded.expression_image_urls,
                    current_outfit_id = excluded.current_outfit_id,
                    interaction_summary = excluded.interaction_summary,
                    claimed_affinity_reward_keys = excluded.claimed_affinity_reward_keys,
                    quiz_affinity_date = excluded.quiz_affinity_date,
                    quiz_affinity_gained_today = excluded.quiz_affinity_gained_today,
                    last_checkin_date = excluded.last_checkin_date
                """,
                (
                    character.id,
                    character.user_id,
                    character.name,
                    character.persona_text,
                    character.appearance_text,
                    character.relationship_stage,
                    character.affinity_score,
                    character.base_image_url,
                    character.profile_image_url,
                    character.visual_novel_image_url,
                    _json_dumps(character.expression_image_urls),
                    character.current_outfit_id,
                    character.interaction_summary,
                    _json_dumps(sorted(character.claimed_affinity_reward_keys)),
                    _date_to_text(character.quiz_affinity_date),
                    character.quiz_affinity_gained_today,
                    _date_to_text(character.last_checkin_date),
                ),
            )

    def _set_current_character(self, user_id: str, character_id: str) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO current_characters (user_id, character_id)
                VALUES (?, ?)
                ON CONFLICT(user_id) DO UPDATE SET
                    character_id = excluded.character_id
                """,
                (user_id, character_id),
            )

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
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO materials (id, user_id, title, status, chunks)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    user_id = excluded.user_id,
                    title = excluded.title,
                    status = excluded.status,
                    chunks = excluded.chunks
                """,
                (
                    material.id,
                    material.user_id,
                    material.title,
                    material.status,
                    _json_dumps([chunk.__dict__ for chunk in material.chunks]),
                ),
            )
        return material

    def get_material(self, material_id: str) -> MaterialRecord:
        row = self.conn.execute(
            "SELECT * FROM materials WHERE id = ?",
            (material_id,),
        ).fetchone()
        if row is None:
            raise KeyError(material_id)
        return self._row_to_material(row)

    def list_materials(self, user_id: str) -> List[MaterialRecord]:
        rows = self.conn.execute(
            "SELECT * FROM materials WHERE user_id = ? ORDER BY rowid ASC",
            (user_id,),
        ).fetchall()
        return [self._row_to_material(row) for row in rows]

    def delete_material(self, user_id: str, material_id: str) -> MaterialRecord:
        material = self.get_material(material_id)
        if material.user_id != user_id:
            raise KeyError(material_id)
        with self._lock, self.conn:
            self.conn.execute("DELETE FROM materials WHERE id = ?", (material_id,))
        return material

    def add_chat_message(self, character_id: str, role: str, text: str) -> ChatMessageRecord:
        message = ChatMessageRecord(character_id=character_id, role=role, text=text)
        with self._lock, self.conn:
            next_order = self._next_chat_order(character_id)
            self.conn.execute(
                """
                INSERT INTO chat_messages (character_id, role, text, created_order)
                VALUES (?, ?, ?, ?)
                """,
                (message.character_id, message.role, message.text, next_order),
            )
        return message

    def replace_chat_messages(self, character_id: str, messages: List[ChatMessageRecord]) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                "DELETE FROM chat_messages WHERE character_id = ?",
                (character_id,),
            )
            self._insert_chat_messages(messages)

    def compact_chat_messages(self, character_id: str) -> List[ChatMessageRecord]:
        messages = self.list_chat_messages(character_id)
        overflow_count = len(messages) - self.max_chat_messages_per_character
        if overflow_count <= 0:
            return []
        return self.compact_first_chat_messages(character_id, overflow_count)

    def compact_first_chat_messages(self, character_id: str, count: int) -> List[ChatMessageRecord]:
        if count <= 0:
            return []
        messages = self.list_chat_messages(character_id)
        compacted = messages[:count]
        rows = self.conn.execute(
            """
            SELECT id FROM chat_messages
            WHERE character_id = ?
            ORDER BY created_order ASC, id ASC
            LIMIT ?
            """,
            (character_id, count),
        ).fetchall()
        ids = [row["id"] for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            with self._lock, self.conn:
                self.conn.execute(
                    f"DELETE FROM chat_messages WHERE id IN ({placeholders})",
                    ids,
                )
        return compacted

    def list_chat_messages(self, character_id: str, limit: Optional[int] = None) -> List[ChatMessageRecord]:
        if limit is None:
            rows = self.conn.execute(
                """
                SELECT * FROM chat_messages
                WHERE character_id = ?
                ORDER BY created_order ASC, id ASC
                """,
                (character_id,),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT * FROM (
                    SELECT * FROM chat_messages
                    WHERE character_id = ?
                    ORDER BY created_order DESC, id DESC
                    LIMIT ?
                )
                ORDER BY created_order ASC, id ASC
                """,
                (character_id, limit),
            ).fetchall()
        return [self._row_to_chat_message(row) for row in rows]

    def add_costume(self, costume: CostumeRecord) -> CostumeRecord:
        self.save_costume(costume)
        return costume

    def get_costume(self, costume_id: str) -> CostumeRecord:
        row = self.conn.execute(
            "SELECT * FROM costumes WHERE id = ?",
            (costume_id,),
        ).fetchone()
        if row is None:
            raise KeyError(costume_id)
        return self._row_to_costume(row)

    def list_costumes(self, character_id: str) -> List[CostumeRecord]:
        rows = self.conn.execute(
            """
            SELECT * FROM costumes
            WHERE character_id = ?
            ORDER BY unlock_score ASC, rowid ASC
            """,
            (character_id,),
        ).fetchall()
        return [self._row_to_costume(row) for row in rows]

    def save_costume(self, costume: CostumeRecord) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                """
                INSERT INTO costumes (
                    id, character_id, name, prompt, unlock_score,
                    image_url, expression_image_urls, generation_status
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    character_id = excluded.character_id,
                    name = excluded.name,
                    prompt = excluded.prompt,
                    unlock_score = excluded.unlock_score,
                    image_url = excluded.image_url,
                    expression_image_urls = excluded.expression_image_urls,
                    generation_status = excluded.generation_status
                """,
                (
                    costume.id,
                    costume.character_id,
                    costume.name,
                    costume.prompt,
                    costume.unlock_score,
                    costume.image_url,
                    _json_dumps(costume.expression_image_urls),
                    costume.generation_status,
                ),
            )

    def _next_chat_order(self, character_id: str) -> int:
        row = self.conn.execute(
            "SELECT COALESCE(MAX(created_order), -1) + 1 AS next_order FROM chat_messages WHERE character_id = ?",
            (character_id,),
        ).fetchone()
        return int(row["next_order"])

    def _insert_chat_messages(self, messages: List[ChatMessageRecord]) -> None:
        order_by_character: dict[str, int] = {}
        for message in messages:
            next_order = order_by_character.setdefault(
                message.character_id,
                self._next_chat_order(message.character_id),
            )
            self.conn.execute(
                """
                INSERT INTO chat_messages (character_id, role, text, created_order)
                VALUES (?, ?, ?, ?)
                """,
                (message.character_id, message.role, message.text, next_order),
            )
            order_by_character[message.character_id] = next_order + 1

    def _row_to_user(self, row: sqlite3.Row) -> UserRecord:
        return UserRecord(
            id=row["id"],
            external_auth_id=row["external_auth_id"],
            display_name=row["display_name"],
        )

    def _row_to_profile(self, row: sqlite3.Row) -> ProfileRecord:
        return ProfileRecord(
            user_id=row["user_id"],
            department=row["department"],
            study_goal=row["study_goal"],
        )

    def _row_to_character(self, row: sqlite3.Row) -> CharacterRecord:
        return CharacterRecord(
            id=row["id"],
            user_id=row["user_id"],
            name=row["name"],
            persona_text=row["persona_text"],
            appearance_text=row["appearance_text"],
            relationship_stage=row["relationship_stage"],
            affinity_score=row["affinity_score"],
            base_image_url=row["base_image_url"],
            profile_image_url=row["profile_image_url"],
            visual_novel_image_url=row["visual_novel_image_url"],
            expression_image_urls=_json_loads(row["expression_image_urls"], {}),
            current_outfit_id=row["current_outfit_id"],
            interaction_summary=row["interaction_summary"],
            claimed_affinity_reward_keys=set(
                _json_loads(row["claimed_affinity_reward_keys"], [])
            ),
            quiz_affinity_date=_text_to_date(row["quiz_affinity_date"]),
            quiz_affinity_gained_today=row["quiz_affinity_gained_today"],
            last_checkin_date=_text_to_date(row["last_checkin_date"]),
        )

    def _row_to_material(self, row: sqlite3.Row) -> MaterialRecord:
        chunks = [
            PdfChunk(
                id=chunk["id"],
                material_id=chunk["material_id"],
                page_number=chunk["page_number"],
                chunk_index=chunk["chunk_index"],
                text=chunk["text"],
            )
            for chunk in _json_loads(row["chunks"], [])
        ]
        return MaterialRecord(
            id=row["id"],
            user_id=row["user_id"],
            title=row["title"],
            status=row["status"],
            chunks=chunks,
        )

    def _row_to_chat_message(self, row: sqlite3.Row) -> ChatMessageRecord:
        return ChatMessageRecord(
            character_id=row["character_id"],
            role=row["role"],
            text=row["text"],
        )

    def _row_to_costume(self, row: sqlite3.Row) -> CostumeRecord:
        return CostumeRecord(
            id=row["id"],
            character_id=row["character_id"],
            name=row["name"],
            prompt=row["prompt"],
            unlock_score=row["unlock_score"],
            image_url=row["image_url"],
            expression_image_urls=_json_loads(row["expression_image_urls"], {}),
            generation_status=row["generation_status"],
        )


def _json_dumps(value) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _json_loads(value: str | None, fallback):
    if not value:
        return fallback
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return fallback


def _date_to_text(value: Optional[date]) -> Optional[str]:
    return value.isoformat() if value else None


def _text_to_date(value: str | None) -> Optional[date]:
    if not value:
        return None
    return date.fromisoformat(value)


store = SQLiteStore()
