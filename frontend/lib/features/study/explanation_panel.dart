import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';

class QuizExplanationPanel extends StatefulWidget {
  const QuizExplanationPanel({
    super.key,
    required this.explanation,
    required this.choices,
    required this.explanations,
    required this.answerIndex,
    required this.selectedIndex,
    this.onExpanded,
  });

  final String explanation;
  final List<String> choices;
  final List<String> explanations;
  final int answerIndex;
  final int selectedIndex;
  final VoidCallback? onExpanded;

  @override
  State<QuizExplanationPanel> createState() => _QuizExplanationPanelState();
}

class _QuizExplanationPanelState extends State<QuizExplanationPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            final shouldNotify = !_expanded;
            setState(() => _expanded = !_expanded);
            if (shouldNotify) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.onExpanded?.call();
                }
              });
            }
          },
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(_expanded ? '해설 접기' : '해설 보기'),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _expanded
              ? Padding(
                  key: const ValueKey('expanded-explanation'),
                  padding: const EdgeInsets.only(top: MetaSpacing.md),
                  child: _ExplanationBody(
                    explanation: widget.explanation,
                    choices: widget.choices,
                    explanations: widget.explanations,
                    answerIndex: widget.answerIndex,
                    selectedIndex: widget.selectedIndex,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('collapsed-explanation')),
        ),
      ],
    );
  }
}

class _ExplanationBody extends StatelessWidget {
  const _ExplanationBody({
    required this.explanation,
    required this.choices,
    required this.explanations,
    required this.answerIndex,
    required this.selectedIndex,
  });

  final String explanation;
  final List<String> choices;
  final List<String> explanations;
  final int answerIndex;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final itemCount = choices.length;

    return Container(
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: MetaColors.surfaceSoft,
        borderRadius: BorderRadius.circular(MetaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('해설: $explanation',
              style: Theme.of(context).textTheme.bodyLarge),
          if (itemCount > 0) ...[
            const SizedBox(height: MetaSpacing.md),
            Text('선지 해설', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: MetaSpacing.xs),
            ...List.generate(itemCount, (index) {
              final isCorrect = index == answerIndex;
              final isSelected = index == selectedIndex;
              final itemExplanation = index < explanations.length
                  ? explanations[index]
                  : '이 선지는 자료와 다시 비교해 보세요.';
              final color = isCorrect
                  ? MetaColors.success
                  : isSelected
                      ? MetaColors.critical
                      : MetaColors.steel;

              return Padding(
                padding: const EdgeInsets.only(top: MetaSpacing.xs),
                child: Text(
                  '${index + 1}. ${choices[index]}\n$itemExplanation',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color,
                      ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
