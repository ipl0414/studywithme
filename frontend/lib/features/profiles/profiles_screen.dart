import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../onboarding/onboarding_screen.dart';
import '../shared/rounded_section.dart';
import 'character_edit_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({
    super.key,
    required this.api,
    required this.characters,
    required this.currentCharacter,
    required this.loading,
    required this.onRefresh,
    required this.onSelected,
    required this.onCreated,
    required this.onEdited,
    required this.onDeleted,
  });

  final ApiClient api;
  final List<CharacterDto> characters;
  final CharacterDto currentCharacter;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<CharacterDto> onSelected;
  final ValueChanged<CharacterDto> onCreated;
  final ValueChanged<CharacterDto> onEdited;
  final ValueChanged<String> onDeleted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canCreate = characters.length < 3;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(MetaSpacing.xl),
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Profiles', style: textTheme.headlineMedium)),
              Text('${characters.length}/3', style: textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: MetaSpacing.xl),
          ...characters.map(
            (character) => Padding(
              padding: const EdgeInsets.only(bottom: MetaSpacing.md),
              child: _ProfileCard(
                api: api,
                character: character,
                selected: character.id == currentCharacter.id,
                onTap: () async {
                  final selected = await api.selectCharacter(character.id);
                  onSelected(selected);
                },
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CharacterEditScreen(
                      api: api,
                      character: character,
                      onEdited: onEdited,
                    ),
                  ),
                ),
                onDelete: () => _confirmDelete(context, character),
              ),
            ),
          ),
          RoundedSection(
            radius: MetaRadii.xl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('새 캐릭터 프로필', style: textTheme.titleLarge),
                const SizedBox(height: MetaSpacing.xs),
                Text(
                  canCreate
                      ? '프롬프트로 새 튜터와 프로필 이미지를 생성합니다.'
                      : '최대 3개까지 만들 수 있어요.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: MetaSpacing.lg),
                FilledButton.icon(
                  onPressed: canCreate
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OnboardingScreen(
                                api: api,
                                title: 'Create another tutor',
                                submitLabel: '프로필 생성',
                                onCreated: (character) {
                                  onCreated(character);
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('프로필 추가'),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: MetaSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CharacterDto character,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로필 삭제'),
        content: Text('${character.name} 프로필과 대화 기록을 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: MetaColors.critical),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await api.deleteCharacter(character.id);
      onDeleted(character.id);
    } on ApiException catch (error) {
      // 서버에 이미 없는 캐릭터(예: 서버 재시작으로 캐시 만료)면
      // 로컬 목록에서도 제거해 상태를 맞춘다.
      if (error.statusCode == 404) {
        onDeleted(character.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('이미 삭제된 프로필이라 목록에서 정리했어요.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('삭제 실패: ${error.message}')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('삭제 실패: $error')),
      );
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.api,
    required this.character,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ApiClient api;
  final CharacterDto character;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(MetaRadii.xxl),
      onTap: onTap,
      child: RoundedSection(
        radius: MetaRadii.xxl,
        padding: const EdgeInsets.all(MetaSpacing.base),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MetaRadii.xl),
              child: Image.network(
                api.assetUrl(character.baseImageUrl),
                width: 92,
                height: 92,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: MetaColors.surfaceSoft,
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Icon(Icons.person),
                  ),
                ),
              ),
            ),
            const SizedBox(width: MetaSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(character.name,
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle,
                            color: MetaColors.success),
                    ],
                  ),
                  const SizedBox(height: MetaSpacing.xs),
                  Text(
                    '관계 ${character.relationshipStage} · 호감도 ${character.affinityScore}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: MetaSpacing.xs),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('편집'),
                        style: TextButton.styleFrom(
                          foregroundColor: MetaColors.inkDeep,
                          padding: const EdgeInsets.symmetric(
                            horizontal: MetaSpacing.xs,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('삭제'),
                        style: TextButton.styleFrom(
                          foregroundColor: MetaColors.critical,
                          padding: const EdgeInsets.symmetric(
                            horizontal: MetaSpacing.xs,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
