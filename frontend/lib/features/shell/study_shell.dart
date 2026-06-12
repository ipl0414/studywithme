import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../chat/chat_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../profiles/profiles_screen.dart';
import '../study/study_screen.dart';
import '../wardrobe/wardrobe_screen.dart';

class StudyShell extends StatefulWidget {
  const StudyShell({super.key});

  @override
  State<StudyShell> createState() => _StudyShellState();
}

class _StudyShellState extends State<StudyShell> {
  final _api = ApiClient();
  int _index = 0;
  CharacterDto? _character;
  List<CharacterDto> _characters = const [];
  List<MaterialDto> _materials = const [];
  Set<String> _selectedMaterialIds = const {};
  final Map<String, QuizSessionState> _quizSessions = {};
  List<CostumeDto> _costumes = const [];
  AffinityStatusDto? _affinityStatus;
  bool _bootstrapping = true;
  bool _loadingProfiles = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentCharacter();
  }

  Future<void> _loadCurrentCharacter() async {
    try {
      final results = await Future.wait([
        _api.getCurrentCharacter(),
        _api.listCharacters(),
        _api.listMaterials(),
      ]);
      final character = results[0] as CharacterDto?;
      final characters = results[1] as List<CharacterDto>;
      final materials = results[2] as List<MaterialDto>;
      final costumes = character == null
          ? <CostumeDto>[]
          : await _api.listCostumes(characterId: character.id);
      final affinityStatus = character == null
          ? null
          : await _api.getAffinityStatus(characterId: character.id);
      if (mounted) {
        setState(() {
          _character = character;
          _characters = characters;
          _materials = materials;
          _selectedMaterialIds =
              materials.map((material) => material.id).toSet();
          _costumes = costumes;
          _affinityStatus = affinityStatus;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
  }

  Future<void> _refreshProfiles() async {
    setState(() => _loadingProfiles = true);
    try {
      final characters = await _api.listCharacters();
      final current = await _api.getCurrentCharacter();
      final costumes = current == null
          ? <CostumeDto>[]
          : await _api.listCostumes(characterId: current.id);
      if (mounted) {
        setState(() {
          _characters = characters;
          _character = current;
          _costumes = costumes;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  Future<void> _selectCharacter(CharacterDto character) async {
    final costumes = await _api.listCostumes(characterId: character.id);
    final affinityStatus =
        await _api.getAffinityStatus(characterId: character.id);
    if (mounted) {
      setState(() {
        _character = character;
        _costumes = costumes;
        _affinityStatus = affinityStatus;
        _index = 0;
      });
    }
  }

  void _handleCharacterCreated(CharacterDto character) {
    setState(() {
      _character = character;
      _characters = [..._characters, character];
      _costumes = const [];
      _index = 0;
    });
    _refreshCostumes();
  }

  void _handleAffinityChanged(AffinityDto affinity) {
    final current = _character;
    if (current == null) {
      return;
    }
    setState(() {
      _character = CharacterDto(
        id: current.id,
        name: current.name,
        personaText: current.personaText,
        appearanceText: current.appearanceText,
        relationshipStage: affinity.relationshipStageLabel,
        affinityScore: affinity.score,
        baseImageUrl: current.baseImageUrl,
        profileImageUrl: current.profileImageUrl,
        visualNovelImageUrl: current.visualNovelImageUrl,
        currentOutfitId: current.currentOutfitId,
      );
      _affinityStatus = AffinityStatusDto(
        score: affinity.score,
        relationshipStage: affinity.relationshipStage,
        relationshipStageLabel: affinity.relationshipStageLabel,
        quizAffinityGainedToday: affinity.quizAffinityGainedToday,
        quizAffinityDailyLimit: affinity.quizAffinityDailyLimit,
        quizAffinityRemainingToday: affinity.quizAffinityRemainingToday,
        checkinAvailable: affinity.checkinAvailable,
        checkinRewardDelta: _affinityStatus?.checkinRewardDelta ?? 3,
      );
    });
    if (affinity.unlockedCostumeIds.isNotEmpty) {
      _refreshCostumes();
    }
  }

  void _handleCharacterChanged(CharacterDto character) {
    setState(() {
      _character = character;
      _characters = _characters
          .map((item) => item.id == character.id ? character : item)
          .toList();
    });
  }

  Future<void> _claimCheckin() async {
    final current = _character;
    if (current == null) {
      return;
    }
    final affinity = await _api.claimCheckin(characterId: current.id);
    _handleAffinityChanged(affinity);
  }

  Future<void> _refreshCostumes() async {
    final current = _character;
    if (current == null) {
      return;
    }
    final costumes = await _api.listCostumes(characterId: current.id);
    if (mounted && _character?.id == current.id) {
      setState(() => _costumes = costumes);
    }
  }

  void _handleMaterialUploaded(MaterialDto material) {
    setState(() {
      _materials = [..._materials, material];
      _selectedMaterialIds = {..._selectedMaterialIds, material.id};
    });
  }

  void _handleMaterialSelectionChanged(Set<String> selectedMaterialIds) {
    setState(() => _selectedMaterialIds = selectedMaterialIds);
  }

  void _handleMaterialDeleted(String materialId) {
    setState(() {
      _materials =
          _materials.where((material) => material.id != materialId).toList();
      _selectedMaterialIds = {..._selectedMaterialIds}..remove(materialId);
      _quizSessions.removeWhere(
        (_, session) => session.quiz.materialIds.contains(materialId),
      );
    });
  }

  void _handleQuizGenerated(QuizDto quiz) {
    final current = _character;
    if (current == null) {
      return;
    }
    setState(() {
      _quizSessions[current.id] = QuizSessionState(quiz: quiz);
    });
  }

  void _handleQuizProgressChanged(QuizSessionState session) {
    final current = _character;
    if (current == null) {
      return;
    }
    setState(() => _quizSessions[current.id] = session);
  }

  void _handleQuizCompleted() {
    final current = _character;
    if (current == null) {
      return;
    }
    setState(() => _quizSessions.remove(current.id));
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_character == null) {
      return OnboardingScreen(
        api: _api,
        onCreated: _handleCharacterCreated,
      );
    }

    final screens = [
      HomeScreen(
        api: _api,
        character: _character!,
        materials: _materials,
        selectedMaterialIds: _selectedMaterialIds,
        quiz: _quizSessions[_character!.id]?.quiz,
        affinityStatus: _affinityStatus,
        onClaimCheckin: _claimCheckin,
        onStartChat: () => setState(() => _index = 1),
        onUploadPdf: () => setState(() => _index = 2),
      ),
      ChatScreen(
        api: _api,
        character: _character!,
        materials: _materials,
        selectedMaterialIds: _selectedMaterialIds,
      ),
      StudyScreen(
        api: _api,
        character: _character!,
        materials: _materials,
        selectedMaterialIds: _selectedMaterialIds,
        quizSession: _quizSessions[_character!.id],
        onMaterialUploaded: _handleMaterialUploaded,
        onMaterialSelectionChanged: _handleMaterialSelectionChanged,
        onMaterialDeleted: _handleMaterialDeleted,
        onQuizGenerated: _handleQuizGenerated,
        onQuizProgressChanged: _handleQuizProgressChanged,
        onQuizCompleted: _handleQuizCompleted,
        onAffinityChanged: _handleAffinityChanged,
      ),
      WardrobeScreen(
        api: _api,
        character: _character!,
        costumes: _costumes,
        onCharacterChanged: _handleCharacterChanged,
        onRefresh: _refreshCostumes,
      ),
      ProfilesScreen(
        api: _api,
        characters: _characters,
        currentCharacter: _character!,
        loading: _loadingProfiles,
        onRefresh: _refreshProfiles,
        onSelected: _selectCharacter,
        onCreated: _handleCharacterCreated,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: screens,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: MetaColors.canvas,
        indicatorColor: MetaColors.inkDeep,
        onDestinationSelected: (index) {
          setState(() => _index = index);
          if (index == 3) {
            _refreshCostumes();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: MetaColors.canvas),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: MetaColors.canvas),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: MetaColors.canvas),
            label: 'Study',
          ),
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom, color: MetaColors.canvas),
            label: '의상',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: MetaColors.canvas),
            label: 'Profiles',
          ),
        ],
      ),
    );
  }
}
