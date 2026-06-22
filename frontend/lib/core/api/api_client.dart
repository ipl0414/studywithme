import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_models.dart';

class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8000',
            );

  final String baseUrl;
  String? _authToken;

  String assetUrl(String? path) {
    if (path == null || path.isEmpty) {
      return '$baseUrl/assets/default-character.png';
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  Future<void> updateProfile({
    required String department,
    required String studyGoal,
  }) async {
    await _patchJson('/profile', {
      'department': department,
      'study_goal': studyGoal,
    });
  }

  Future<AuthDto> loginWithTestAccount(String userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    final auth = AuthDto.fromJson(decoded as Map<String, dynamic>);
    _authToken = auth.accessToken;
    return auth;
  }

  Future<CharacterDto?> getCurrentCharacter() async {
    final response = await http.get(
      Uri.parse('$baseUrl/characters/current'),
      headers: await _headers(),
    );
    if (response.statusCode == 404) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return CharacterDto.fromJson(decoded as Map<String, dynamic>);
  }

  Future<List<CharacterDto>> listCharacters() async {
    final response = await http.get(
      Uri.parse('$baseUrl/characters'),
      headers: await _headers(),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return (decoded as List)
        .map((item) => CharacterDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CharacterDto> createCharacter({
    required String name,
    required String personaText,
    required String appearanceText,
  }) async {
    final body = await _postJson('/characters', {
      'name': name,
      'persona_text': personaText,
      'appearance_text': appearanceText,
    });
    return CharacterDto.fromJson(body);
  }

  Future<CharacterDto> selectCharacter(String characterId) async {
    final body = await _postJson('/characters/$characterId/select', {});
    return CharacterDto.fromJson(body);
  }

  Future<CharacterDto> updateCharacter({
    required String characterId,
    required String name,
    required String personaText,
    required String appearanceText,
  }) async {
    final body = await _patchJson('/characters/$characterId', {
      'name': name,
      'persona_text': personaText,
      'appearance_text': appearanceText,
    });
    return CharacterDto.fromJson(body);
  }

  Future<void> deleteCharacter(String characterId) async {
    final response = await http.delete(
        Uri.parse('$baseUrl/characters/$characterId'),
        headers: await _headers());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
  }

  Future<CharacterDto> equipDefaultImage(String characterId) async {
    final body = await _postJson('/characters/$characterId/equip-default', {});
    return CharacterDto.fromJson(body);
  }

  Future<CharacterDto> generateVisualNovelImage(String characterId) async {
    final body =
        await _postJson('/characters/$characterId/visual-novel-image', {});
    return CharacterDto.fromJson(body);
  }

  Future<MaterialDto> createMaterial({
    required String title,
    required List<String> pages,
  }) async {
    final body = await _postJson('/materials', {
      'title': title,
      'pages': pages,
    });
    return MaterialDto.fromJson(body);
  }

  Future<List<MaterialDto>> listMaterials() async {
    final response = await http.get(
      Uri.parse('$baseUrl/materials'),
      headers: await _headers(),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return (decoded as List)
        .map((item) => MaterialDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteMaterial(String materialId) async {
    final response = await http.delete(
        Uri.parse('$baseUrl/materials/$materialId'),
        headers: await _headers());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
  }

  Future<MaterialDto> uploadPdf({
    required String fileName,
    required List<int> bytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/materials/upload'),
    );
    request.headers.addAll(await _headers());
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return MaterialDto.fromJson(decoded as Map<String, dynamic>);
  }

  Future<QuizDto> generateQuiz({
    required List<String> materialIds,
    required String characterId,
    int questionCount = 0,
  }) async {
    final body = await _postJson('/quizzes/generate', {
      'material_ids': materialIds,
      'question_count': questionCount,
      'character_id': characterId,
    });
    return QuizDto.fromJson(body);
  }

  Future<ChatMessageDto> sendChatMessage({
    required String characterId,
    required String message,
    String mode = 'daily_chat',
    List<String> materialIds = const [],
  }) async {
    final body = await _postJson('/chat/messages', {
      'character_id': characterId,
      'mode': mode,
      'message': message,
      if (materialIds.isNotEmpty) 'material_ids': materialIds,
    });
    return ChatMessageDto.fromJson(body);
  }

  Future<List<ChatHistoryMessageDto>> listChatMessages({
    required String characterId,
  }) async {
    final response = await http.get(
        Uri.parse('$baseUrl/chat/messages?character_id=$characterId'),
        headers: await _headers());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return (decoded as List)
        .map((item) =>
            ChatHistoryMessageDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AffinityDto> applyAffinityEvent({
    required String characterId,
    required String eventType,
    required int delta,
    String? rewardKey,
  }) async {
    final body = await _postJson('/affinity/events', {
      'character_id': characterId,
      'event_type': eventType,
      'delta': delta,
      if (rewardKey != null) 'reward_key': rewardKey,
    });
    return AffinityDto.fromJson(body);
  }

  Future<AffinityStatusDto> getAffinityStatus({
    required String characterId,
  }) async {
    final response = await http.get(
        Uri.parse('$baseUrl/affinity/status?character_id=$characterId'),
        headers: await _headers());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return AffinityStatusDto.fromJson(decoded as Map<String, dynamic>);
  }

  Future<AffinityDto> claimCheckin({
    required String characterId,
  }) async {
    final body = await _postJson('/affinity/checkin', {
      'character_id': characterId,
    });
    return AffinityDto.fromJson(body);
  }

  Future<List<CostumeDto>> listCostumes({
    required String characterId,
  }) async {
    final response = await http.get(
        Uri.parse('$baseUrl/wardrobe/costumes?character_id=$characterId'),
        headers: await _headers());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return (decoded as List)
        .map((item) => CostumeDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CharacterDto> equipCostume({
    required String costumeId,
    required String characterId,
  }) async {
    final body = await _postJson(
      '/wardrobe/costumes/$costumeId/equip',
      {'character_id': characterId},
    );
    return CharacterDto.fromJson(body);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return decoded as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patchJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(contentTypeJson: true),
      body: jsonEncode(payload),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
          response.statusCode, detail?.toString() ?? response.body);
    }
    return decoded as Map<String, dynamic>;
  }

  Future<Map<String, String>> _headers({bool contentTypeJson = false}) async {
    if (_authToken == null) {
      throw const ApiException(401, '로그인이 필요합니다.');
    }
    return {
      if (contentTypeJson) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $_authToken',
    };
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
