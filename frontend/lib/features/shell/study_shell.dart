import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../onboarding/onboarding_screen.dart';
import '../play/play_screen.dart';
import '../profiles/profiles_screen.dart';
import '../study/study_screen.dart';
import '../wardrobe/wardrobe_screen.dart';

/// 우측 메뉴로 열 수 있는 전체화면 패널. [none]이면 메인 비주얼노벨 화면만 보인다.
enum _Panel { none, study, wardrobe, profiles }

class StudyShell extends StatefulWidget {
  const StudyShell({super.key});

  @override
  State<StudyShell> createState() => _StudyShellState();
}

class _StudyShellState extends State<StudyShell> {
  final _api = ApiClient();
  _Panel _panel = _Panel.none;
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
    AffinityDto? checkin;
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
      // 하루에 한 번, 접속 시 출석을 자동으로 달성한다.
      if (mounted &&
          character != null &&
          (affinityStatus?.checkinAvailable ?? false)) {
        checkin = await _claimCheckin();
      }
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
    // 출석 보상이 실제로 반영됐으면 메인 화면이 그려진 뒤 알림을 띄운다.
    final reward = checkin;
    if (mounted && reward != null && reward.affinityApplied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showCheckinDialog(reward);
        }
      });
    }
  }

  Future<void> _showCheckinDialog(AffinityDto reward) {
    final name = _character?.name ?? '튜터';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.favorite, color: MetaColors.primary),
            SizedBox(width: MetaSpacing.xs),
            Text('출석 체크 완료'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name와의 오늘 출석이 기록됐어요.'),
            const SizedBox(height: MetaSpacing.xs),
            Text(
              '호감도 +${reward.appliedDelta}',
              style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                    color: MetaColors.primaryDeep,
                  ),
            ),
            Text('현재 호감도 ${reward.score.clamp(0, 100)} / 100'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
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
        _panel = _Panel.none;
      });
    }
  }

  void _handleCharacterCreated(CharacterDto character) {
    setState(() {
      _character = character;
      _characters = [..._characters, character];
      _costumes = const [];
      _panel = _Panel.none;
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
        checkinRewardDelta: _affinityStatus?.checkinRewardDelta ?? 1,
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

  void _handleCharacterEdited(CharacterDto character) {
    setState(() {
      _characters = _characters
          .map((item) => item.id == character.id ? character : item)
          .toList();
      if (_character?.id == character.id) {
        _character = character;
      }
    });
  }

  Future<void> _handleCharacterDeleted(String characterId) async {
    final wasCurrent = _character?.id == characterId;
    final remaining =
        _characters.where((item) => item.id != characterId).toList();
    final current =
        wasCurrent ? await _api.getCurrentCharacter() : _character;
    final costumes = current == null
        ? <CostumeDto>[]
        : await _api.listCostumes(characterId: current.id);
    final affinityStatus = current == null
        ? null
        : await _api.getAffinityStatus(characterId: current.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _characters = remaining;
      _character = current;
      _costumes = costumes;
      _affinityStatus = affinityStatus;
      _quizSessions.remove(characterId);
    });
  }

  Future<AffinityDto?> _claimCheckin() async {
    final current = _character;
    if (current == null) {
      return null;
    }
    final affinity = await _api.claimCheckin(characterId: current.id);
    _handleAffinityChanged(affinity);
    return affinity;
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

    final character = _character!;

    return Scaffold(
      backgroundColor: MetaColors.inkDeep,
      body: SafeArea(
        child: Stack(
          children: [
            PlayScreen(
              api: _api,
              character: character,
              materials: _materials,
              selectedMaterialIds: _selectedMaterialIds,
              affinityStatus: _affinityStatus,
            ),
            _SideMenu(
              onStudy: () => setState(() => _panel = _Panel.study),
              onWardrobe: () {
                setState(() => _panel = _Panel.wardrobe);
                _refreshCostumes();
              },
              onProfiles: () => setState(() => _panel = _Panel.profiles),
            ),
            if (_panel != _Panel.none)
              Positioned.fill(
                child: ColoredBox(
                  color: MetaColors.canvas,
                  child: _buildPanel(character),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(CharacterDto character) {
    void close() => setState(() => _panel = _Panel.none);
    switch (_panel) {
      case _Panel.study:
        final session = _quizSessions[character.id];
        final study = StudyScreen(
          api: _api,
          character: character,
          materials: _materials,
          selectedMaterialIds: _selectedMaterialIds,
          quizSession: session,
          onClose: close,
          onMaterialUploaded: _handleMaterialUploaded,
          onMaterialSelectionChanged: _handleMaterialSelectionChanged,
          onMaterialDeleted: _handleMaterialDeleted,
          onQuizGenerated: _handleQuizGenerated,
          onQuizProgressChanged: _handleQuizProgressChanged,
          onQuizCompleted: _handleQuizCompleted,
          onAffinityChanged: _handleAffinityChanged,
        );
        // 퀴즈 진행 중에는 비주얼노벨 전체화면이므로 패널 상단 바 없이 그대로 띄운다.
        if (session != null) {
          return study;
        }
        return _PanelScaffold(title: 'Study', onClose: close, child: study);
      case _Panel.wardrobe:
        return _PanelScaffold(
          title: '의상',
          onClose: close,
          child: WardrobeScreen(
            api: _api,
            character: character,
            costumes: _costumes,
            onCharacterChanged: _handleCharacterChanged,
            onRefresh: _refreshCostumes,
          ),
        );
      case _Panel.profiles:
        return _PanelScaffold(
          title: '프로필',
          onClose: close,
          child: ProfilesScreen(
            api: _api,
            characters: _characters,
            currentCharacter: character,
            loading: _loadingProfiles,
            onRefresh: _refreshProfiles,
            onSelected: _selectCharacter,
            onCreated: _handleCharacterCreated,
            onEdited: _handleCharacterEdited,
            onDeleted: _handleCharacterDeleted,
          ),
        );
      case _Panel.none:
        return const SizedBox.shrink();
    }
  }
}

/// 우측 가장자리에 세로로 떠 있는 반투명 아이콘 메뉴.
class _SideMenu extends StatelessWidget {
  const _SideMenu({
    required this.onStudy,
    required this.onWardrobe,
    required this.onProfiles,
  });

  final VoidCallback onStudy;
  final VoidCallback onWardrobe;
  final VoidCallback onProfiles;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: MetaSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SideButton(
              icon: Icons.menu_book,
              label: 'Study',
              onTap: onStudy,
            ),
            const SizedBox(height: MetaSpacing.md),
            _SideButton(
              icon: Icons.checkroom,
              label: '의상',
              onTap: onWardrobe,
            ),
            const SizedBox(height: MetaSpacing.md),
            _SideButton(
              icon: Icons.people,
              label: '프로필',
              onTap: onProfiles,
            ),
          ],
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: MetaColors.inkDeep.withValues(alpha: 0.5),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x3DFFFFFF)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: MetaColors.canvas, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 11,
                color: MetaColors.canvas,
                shadows: const [
                  Shadow(color: Color(0xCC000000), blurRadius: 4),
                ],
              ),
        ),
      ],
    );
  }
}

/// 패널(의상/프로필)을 닫기 버튼이 있는 상단 바와 함께 감싼다.
class _PanelScaffold extends StatelessWidget {
  const _PanelScaffold({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MetaColors.canvas,
      appBar: AppBar(
        backgroundColor: MetaColors.canvas,
        surfaceTintColor: MetaColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose,
        ),
        title: Text(title),
      ),
      body: child,
    );
  }
}
