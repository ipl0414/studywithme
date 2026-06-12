import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../shared/rounded_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.character,
    required this.materials,
    required this.selectedMaterialIds,
    required this.quiz,
    required this.affinityStatus,
    required this.onClaimCheckin,
    required this.onStartChat,
    required this.onUploadPdf,
  });

  final ApiClient api;
  final CharacterDto character;
  final List<MaterialDto> materials;
  final Set<String> selectedMaterialIds;
  final QuizDto? quiz;
  final AffinityStatusDto? affinityStatus;
  final Future<void> Function() onClaimCheckin;
  final VoidCallback onStartChat;
  final VoidCallback onUploadPdf;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(MetaSpacing.xl),
      children: [
        Text('AI Character Study', style: textTheme.headlineLarge),
        const SizedBox(height: MetaSpacing.md),
        Text(
          '캐릭터와 가까워지며 PDF 자료를 같이 공부하는 모바일 학습 앱',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: MetaSpacing.xxl),
        RoundedSection(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: Image.network(
                  api.assetUrl(
                    character.baseImageUrl ?? character.visualNovelImageUrl,
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => Container(
                    color: MetaColors.surfaceSoft,
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 92,
                        color: MetaColors.stone,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MetaSpacing.xl,
                  MetaSpacing.md,
                  MetaSpacing.xl,
                  MetaSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RelationshipPill(
                      label:
                          '관계: ${character.relationshipStage} · 호감도 ${character.affinityScore}',
                    ),
                    const SizedBox(height: MetaSpacing.base),
                    Text('${character.name}가 기다리는 중',
                        style: textTheme.titleLarge),
                    const SizedBox(height: MetaSpacing.xs),
                    Text(
                      materials.isEmpty
                          ? 'PDF를 올리면 자료 기반 대화와 퀴즈를 바로 시작할 수 있어요.'
                          : '${materials.length}개 자료 중 ${selectedMaterialIds.length}개를 대화와 퀴즈에 포함 중입니다.',
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: MetaSpacing.xl),
                    Wrap(
                      spacing: MetaSpacing.md,
                      runSpacing: MetaSpacing.md,
                      children: [
                        FilledButton(
                          onPressed: onStartChat,
                          child: const Text('대화 시작'),
                        ),
                        OutlinedButton(
                          onPressed: onUploadPdf,
                          child: const Text('PDF 업로드'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MetaSpacing.xxl),
        _TodayCards(
          affinityStatus: affinityStatus,
          onClaimCheckin: onClaimCheckin,
        ),
      ],
    );
  }
}

class _RelationshipPill extends StatelessWidget {
  const _RelationshipPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MetaColors.inkDeep,
        borderRadius: BorderRadius.circular(MetaRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MetaSpacing.base,
          vertical: MetaSpacing.xs,
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: MetaColors.canvas),
        ),
      ),
    );
  }
}

class _TodayCards extends StatelessWidget {
  const _TodayCards({
    required this.affinityStatus,
    required this.onClaimCheckin,
  });

  final AffinityStatusDto? affinityStatus;
  final Future<void> Function() onClaimCheckin;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _MetricCard(
            title: '출석 보상',
            value: affinityStatus?.checkinAvailable ?? true
                ? '+${affinityStatus?.checkinRewardDelta ?? 3} 가능'
                : '수령 완료',
            actionLabel: affinityStatus?.checkinAvailable ?? true ? '받기' : null,
            onAction: affinityStatus?.checkinAvailable ?? true
                ? onClaimCheckin
                : null,
          ),
        ),
        const SizedBox(width: MetaSpacing.md),
        Expanded(
          child: _QuizAffinityCard(
            affinityStatus: affinityStatus,
          ),
        ),
      ],
    );
  }
}

class _QuizAffinityCard extends StatelessWidget {
  const _QuizAffinityCard({required this.affinityStatus});

  final AffinityStatusDto? affinityStatus;

  @override
  Widget build(BuildContext context) {
    final gained = affinityStatus?.quizAffinityGainedToday ?? 0;
    final limit = affinityStatus?.quizAffinityDailyLimit ?? 0;
    final displayGained = limit <= 0 ? 0 : gained.clamp(0, limit).toInt();
    final progress = limit <= 0 ? 0.0 : displayGained / limit;

    return RoundedSection(
      radius: MetaRadii.xl,
      padding: const EdgeInsets.all(MetaSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘 퀴즈 호감도', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: MetaSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              affinityStatus == null ? '확인 중' : '$displayGained / $limit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: MetaSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(MetaRadii.full),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: MetaColors.hairlineSoft,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(MetaColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String value;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return RoundedSection(
      radius: MetaRadii.xl,
      padding: const EdgeInsets.all(MetaSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: MetaSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: MetaSpacing.md),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
