import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../shared/rounded_section.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    super.key,
    required this.api,
    required this.character,
    required this.costumes,
    required this.onCharacterChanged,
    required this.onEquipped,
    required this.onRefresh,
  });

  final ApiClient api;
  final CharacterDto character;
  final List<CostumeDto> costumes;
  final ValueChanged<CharacterDto> onCharacterChanged;
  final VoidCallback onEquipped;
  final Future<void> Function() onRefresh;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String? _equippingId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(MetaSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('의상', style: textTheme.headlineMedium),
          const SizedBox(height: MetaSpacing.xs),
          Text(
            '호감도를 쌓으면 ${widget.character.name}의 새로운 모습이 공개됩니다.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: MetaSpacing.xl),
          _DefaultCostumeCard(
            selected: widget.character.currentOutfitId == null,
            loading: _equippingId == 'default',
            onEquip: _equipDefault,
          ),
          if (_error != null) ...[
            const SizedBox(height: MetaSpacing.md),
            Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(
                color: MetaColors.critical,
              ),
            ),
          ],
          const SizedBox(height: MetaSpacing.xl),
          ...widget.costumes.map(
            (costume) => Padding(
              padding: const EdgeInsets.only(bottom: MetaSpacing.xl),
              child: _CostumeCard(
                api: widget.api,
                costume: costume,
                loading: _equippingId == costume.id,
                onEquip: () => _equipCostume(costume),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _equipDefault() async {
    setState(() {
      _equippingId = 'default';
      _error = null;
    });
    try {
      final updated = await widget.api.equipDefaultImage(widget.character.id);
      widget.onCharacterChanged(updated);
      widget.onEquipped();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _equippingId = null);
      }
    }
  }

  Future<void> _equipCostume(CostumeDto costume) async {
    setState(() {
      _equippingId = costume.id;
      _error = null;
    });
    try {
      final updated = await widget.api.equipCostume(
        costumeId: costume.id,
        characterId: widget.character.id,
      );
      widget.onCharacterChanged(updated);
      widget.onEquipped();
      await widget.onRefresh();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _equippingId = null);
      }
    }
  }
}

class _DefaultCostumeCard extends StatelessWidget {
  const _DefaultCostumeCard({
    required this.selected,
    required this.loading,
    required this.onEquip,
  });

  final bool selected;
  final bool loading;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return RoundedSection(
      radius: MetaRadii.xl,
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 32),
          const SizedBox(width: MetaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '기본 의상',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  selected ? '현재 착용 중' : '처음 모습으로 돌아가기',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: selected || loading ? null : onEquip,
            child: Text(loading
                ? '변경 중'
                : selected
                    ? '착용 중'
                    : '착용'),
          ),
        ],
      ),
    );
  }
}

class _CostumeCard extends StatelessWidget {
  const _CostumeCard({
    required this.api,
    required this.costume,
    required this.loading,
    required this.onEquip,
  });

  final ApiClient api;
  final CostumeDto costume;
  final bool loading;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ready = costume.generationStatus == 'ready';

    return RoundedSection(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: costume.isUnlocked
                ? _UnlockedCostumeImage(
                    api: api,
                    costume: costume,
                  )
                : _LockedCostumeSilhouette(
                    unlockScore: costume.unlockScore,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(MetaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(costume.name, style: textTheme.titleLarge),
                    ),
                    if (costume.isEquipped)
                      const Icon(Icons.check_circle, color: MetaColors.success),
                  ],
                ),
                const SizedBox(height: MetaSpacing.xs),
                if (!costume.isUnlocked)
                  Text(
                    '호감도 ${costume.unlockScore}에 공개',
                    style: textTheme.bodyLarge,
                  )
                else if (!ready)
                  Text(
                    costume.generationStatus == 'failed'
                        ? '이미지 생성에 실패했습니다.'
                        : '의상 이미지를 준비하는 중입니다.',
                    style: textTheme.bodyLarge,
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: costume.isEquipped || loading ? null : onEquip,
                      icon: const Icon(Icons.checkroom_outlined),
                      label: Text(
                        loading
                            ? '변경 중...'
                            : costume.isEquipped
                                ? '착용 중'
                                : '착용하기',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockedCostumeImage extends StatelessWidget {
  const _UnlockedCostumeImage({
    required this.api,
    required this.costume,
  });

  final ApiClient api;
  final CostumeDto costume;

  @override
  Widget build(BuildContext context) {
    if (costume.imageUrl == null) {
      return const ColoredBox(
        color: MetaColors.surfaceSoft,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Image.network(
      api.assetUrl(costume.imageUrl),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: MetaColors.surfaceSoft,
        child:
            Center(child: Icon(Icons.image_not_supported_outlined, size: 52)),
      ),
    );
  }
}

class _LockedCostumeSilhouette extends StatelessWidget {
  const _LockedCostumeSilhouette({required this.unlockScore});

  final int unlockScore;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MetaColors.primaryDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              color: MetaColors.surface,
              size: 48,
            ),
            const SizedBox(height: MetaSpacing.md),
            Text(
              '호감도 $unlockScore',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: MetaColors.surface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
