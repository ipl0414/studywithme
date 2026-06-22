import '../text/generated_text.dart';

class AuthDto {
  const AuthDto({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
  });

  final String accessToken;
  final String tokenType;
  final String userId;

  factory AuthDto.fromJson(Map<String, dynamic> json) {
    return AuthDto(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      userId: json['user_id'] as String,
    );
  }
}

class CharacterDto {
  const CharacterDto({
    required this.id,
    required this.name,
    required this.personaText,
    required this.appearanceText,
    required this.relationshipStage,
    required this.affinityScore,
    this.baseImageUrl,
    this.profileImageUrl,
    this.visualNovelImageUrl,
    this.expressionImageUrls = const {},
    this.currentOutfitId,
  });

  final String id;
  final String name;
  final String personaText;
  final String appearanceText;
  final String relationshipStage;
  final int affinityScore;
  final String? baseImageUrl;
  final String? profileImageUrl;
  final String? visualNovelImageUrl;
  final Map<String, String> expressionImageUrls;
  final String? currentOutfitId;

  factory CharacterDto.fromJson(Map<String, dynamic> json) {
    return CharacterDto(
      id: json['id'] as String,
      name: json['name'] as String,
      personaText: json['persona_text'] as String,
      appearanceText: json['appearance_text'] as String,
      relationshipStage: json['relationship_stage'] as String,
      affinityScore: (json['affinity_score'] as num?)?.toInt() ?? 0,
      baseImageUrl: json['base_image_url'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      visualNovelImageUrl: json['visual_novel_image_url'] as String?,
      expressionImageUrls: Map<String, String>.from(
        (json['expression_image_urls'] as Map?) ?? const {},
      ),
      currentOutfitId: json['current_outfit_id'] as String?,
    );
  }
}

class AffinityDto {
  const AffinityDto({
    required this.score,
    required this.relationshipStage,
    required this.relationshipStageLabel,
    required this.unlockedCostumeIds,
    required this.affinityApplied,
    required this.appliedDelta,
    required this.quizAffinityGainedToday,
    required this.quizAffinityDailyLimit,
    required this.quizAffinityRemainingToday,
    required this.checkinAvailable,
  });

  final int score;
  final String relationshipStage;
  final String relationshipStageLabel;
  final List<String> unlockedCostumeIds;
  final bool affinityApplied;
  final int appliedDelta;
  final int quizAffinityGainedToday;
  final int quizAffinityDailyLimit;
  final int quizAffinityRemainingToday;
  final bool checkinAvailable;

  factory AffinityDto.fromJson(Map<String, dynamic> json) {
    return AffinityDto(
      score: (json['score'] as num).toInt(),
      relationshipStage: json['relationship_stage'] as String,
      relationshipStageLabel: json['relationship_stage_label'] as String,
      unlockedCostumeIds: ((json['unlocked_costume_ids'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      affinityApplied: json['affinity_applied'] as bool? ?? true,
      appliedDelta: (json['applied_delta'] as num?)?.toInt() ?? 0,
      quizAffinityGainedToday:
          (json['quiz_affinity_gained_today'] as num?)?.toInt() ?? 0,
      quizAffinityDailyLimit:
          (json['quiz_affinity_daily_limit'] as num?)?.toInt() ?? 0,
      quizAffinityRemainingToday:
          (json['quiz_affinity_remaining_today'] as num?)?.toInt() ?? 0,
      checkinAvailable: json['checkin_available'] as bool? ?? true,
    );
  }
}

class AffinityStatusDto {
  const AffinityStatusDto({
    required this.score,
    required this.relationshipStage,
    required this.relationshipStageLabel,
    required this.quizAffinityGainedToday,
    required this.quizAffinityDailyLimit,
    required this.quizAffinityRemainingToday,
    required this.checkinAvailable,
    required this.checkinRewardDelta,
  });

  final int score;
  final String relationshipStage;
  final String relationshipStageLabel;
  final int quizAffinityGainedToday;
  final int quizAffinityDailyLimit;
  final int quizAffinityRemainingToday;
  final bool checkinAvailable;
  final int checkinRewardDelta;

  factory AffinityStatusDto.fromJson(Map<String, dynamic> json) {
    return AffinityStatusDto(
      score: (json['score'] as num).toInt(),
      relationshipStage: json['relationship_stage'] as String,
      relationshipStageLabel: json['relationship_stage_label'] as String,
      quizAffinityGainedToday:
          (json['quiz_affinity_gained_today'] as num?)?.toInt() ?? 0,
      quizAffinityDailyLimit:
          (json['quiz_affinity_daily_limit'] as num?)?.toInt() ?? 0,
      quizAffinityRemainingToday:
          (json['quiz_affinity_remaining_today'] as num?)?.toInt() ?? 0,
      checkinAvailable: json['checkin_available'] as bool? ?? true,
      checkinRewardDelta: (json['checkin_reward_delta'] as num?)?.toInt() ?? 0,
    );
  }
}

class CostumeDto {
  const CostumeDto({
    required this.id,
    required this.name,
    required this.unlockScore,
    required this.isUnlocked,
    required this.isEquipped,
    required this.generationStatus,
    this.imageUrl,
  });

  final String id;
  final String name;
  final int unlockScore;
  final bool isUnlocked;
  final bool isEquipped;
  final String generationStatus;
  final String? imageUrl;

  factory CostumeDto.fromJson(Map<String, dynamic> json) {
    return CostumeDto(
      id: json['id'] as String,
      name: json['name'] as String,
      unlockScore: (json['unlock_score'] as num).toInt(),
      isUnlocked: json['is_unlocked'] as bool? ?? false,
      isEquipped: json['is_equipped'] as bool? ?? false,
      generationStatus: json['generation_status'] as String? ?? 'generating',
      imageUrl: json['image_url'] as String?,
    );
  }
}

class MaterialDto {
  const MaterialDto({
    required this.id,
    required this.title,
    required this.status,
    required this.chunkCount,
  });

  final String id;
  final String title;
  final String status;
  final int chunkCount;

  factory MaterialDto.fromJson(Map<String, dynamic> json) {
    return MaterialDto(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      chunkCount: json['chunk_count'] as int,
    );
  }
}

class QuizDto {
  const QuizDto({
    required this.id,
    required this.materialId,
    required this.materialIds,
    required this.title,
    required this.questions,
    required this.model,
  });

  final String id;
  final String materialId;
  final List<String> materialIds;
  final String title;
  final List<QuizQuestionDto> questions;
  final String model;

  factory QuizDto.fromJson(Map<String, dynamic> json) {
    final materialId = json['material_id'] as String;
    return QuizDto(
      id: json['id'] as String,
      materialId: materialId,
      materialIds: List<String>.from(
        (json['material_ids'] as List?) ?? [materialId],
      ),
      title: json['title'] as String,
      questions: (json['questions'] as List)
          .map((item) => QuizQuestionDto.fromJson(item as Map<String, dynamic>))
          .toList(),
      model: json['model'] as String,
    );
  }
}

class QuizQuestionDto {
  const QuizQuestionDto({
    required this.type,
    required this.difficulty,
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
    required this.choiceExplanations,
    required this.correctReaction,
    required this.wrongReaction,
    required this.sourceChunkIds,
  });

  final String type;
  final String difficulty;
  final String question;
  final List<String> choices;
  final int answerIndex;
  final String explanation;
  final List<String> choiceExplanations;
  final String correctReaction;
  final String wrongReaction;
  final List<String> sourceChunkIds;

  factory QuizQuestionDto.fromJson(Map<String, dynamic> json) {
    final choices = List<String>.from((json['choices'] as List?) ?? const []);
    final explanation = json['explanation']?.toString() ?? '';
    final choiceExplanations = List<String>.from(
      (json['choice_explanations'] as List?) ??
          List<String>.filled(choices.length, explanation),
    );
    return QuizQuestionDto(
      type: json['type']?.toString() ?? 'multiple_choice',
      difficulty: json['difficulty']?.toString() ?? 'medium',
      question: cleanGeneratedText(json['question']?.toString() ?? ''),
      choices: choices.map(cleanGeneratedText).toList(),
      answerIndex: (json['answer_index'] as num?)?.toInt() ?? 0,
      explanation: cleanGeneratedText(explanation),
      choiceExplanations: choiceExplanations.map(cleanGeneratedText).toList(),
      correctReaction: cleanGeneratedText(
          json['correct_reaction']?.toString() ?? '오, 맞았네. 핵심 잘 잡았어 ㅋㅋ'),
      wrongReaction: cleanGeneratedText(json['wrong_reaction']?.toString() ??
          '아깝다. 이건 헷갈릴 만했어. 해설 보고 다시 잡자.'),
      sourceChunkIds:
          List<String>.from((json['source_chunk_ids'] as List?) ?? const []),
    );
  }
}

class ChatMessageDto {
  const ChatMessageDto({
    required this.reply,
    required this.environmentBox,
    required this.expression,
    required this.model,
    required this.sourceChunkIds,
    this.expressionImageUrl,
  });

  final String reply;
  final String environmentBox;
  final String expression;
  final String? expressionImageUrl;
  final String model;
  final List<String> sourceChunkIds;

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageDto(
      reply: cleanGeneratedText(json['reply']?.toString() ?? ''),
      environmentBox:
          cleanGeneratedText(json['environment_box']?.toString() ?? ''),
      expression: json['expression']?.toString() ?? 'neutral',
      expressionImageUrl: json['expression_image_url'] as String?,
      model: json['model'] as String,
      sourceChunkIds:
          List<String>.from((json['source_chunk_ids'] as List?) ?? const []),
    );
  }
}

class ChatHistoryMessageDto {
  const ChatHistoryMessageDto({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  factory ChatHistoryMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatHistoryMessageDto(
      role: json['role'] as String,
      text: cleanGeneratedText(json['text']?.toString() ?? ''),
    );
  }
}
