import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../shared/rounded_section.dart';
import 'explanation_panel.dart';

class QuizSessionState {
  const QuizSessionState({
    required this.quiz,
    this.questionIndex = 0,
    this.selectedChoice,
    this.answerAffinityDelta,
    this.rewardAlreadyClaimed = false,
  });

  final QuizDto quiz;
  final int questionIndex;
  final int? selectedChoice;
  final int? answerAffinityDelta;
  final bool rewardAlreadyClaimed;

  QuizSessionState moveToNextQuestion() {
    return QuizSessionState(
      quiz: quiz,
      questionIndex: questionIndex + 1,
    );
  }

  QuizSessionState selectChoice(int choiceIndex) {
    return QuizSessionState(
      quiz: quiz,
      questionIndex: questionIndex,
      selectedChoice: choiceIndex,
    );
  }

  QuizSessionState withAffinityResult(AffinityDto affinity) {
    return QuizSessionState(
      quiz: quiz,
      questionIndex: questionIndex,
      selectedChoice: selectedChoice,
      answerAffinityDelta: affinity.appliedDelta,
      rewardAlreadyClaimed: !affinity.affinityApplied,
    );
  }
}

class StudyScreen extends StatefulWidget {
  const StudyScreen({
    super.key,
    required this.api,
    required this.character,
    required this.materials,
    required this.selectedMaterialIds,
    required this.quizSession,
    required this.onMaterialUploaded,
    required this.onMaterialSelectionChanged,
    required this.onMaterialDeleted,
    required this.onQuizGenerated,
    required this.onQuizProgressChanged,
    required this.onQuizCompleted,
    required this.onAffinityChanged,
  });

  final ApiClient api;
  final CharacterDto character;
  final List<MaterialDto> materials;
  final Set<String> selectedMaterialIds;
  final QuizSessionState? quizSession;
  final ValueChanged<MaterialDto> onMaterialUploaded;
  final ValueChanged<Set<String>> onMaterialSelectionChanged;
  final ValueChanged<String> onMaterialDeleted;
  final ValueChanged<QuizDto> onQuizGenerated;
  final ValueChanged<QuizSessionState> onQuizProgressChanged;
  final VoidCallback onQuizCompleted;
  final ValueChanged<AffinityDto> onAffinityChanged;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final _scrollController = ScrollController();
  bool _uploading = false;
  bool _generatingQuiz = false;
  String? _error;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(MetaSpacing.xl),
      children: [
        Text('Study', style: textTheme.headlineMedium),
        const SizedBox(height: MetaSpacing.xl),
        RoundedSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PDF 자료', style: textTheme.titleLarge),
              const SizedBox(height: MetaSpacing.xs),
              Text(
                widget.materials.isEmpty
                    ? 'PDF를 업로드하면 자료함에 저장하고, 포함할 자료를 체크해 RAG와 퀴즈에 사용합니다.'
                    : '${widget.materials.length}개 자료 · ${widget.selectedMaterialIds.length}개 포함 중',
                style: textTheme.bodyLarge,
              ),
              if (widget.materials.isNotEmpty) ...[
                const SizedBox(height: MetaSpacing.md),
                ...widget.materials.map(
                  (material) => _MaterialRow(
                    material: material,
                    selected: widget.selectedMaterialIds.contains(material.id),
                    onChanged: (selected) =>
                        _setMaterialSelected(material.id, selected),
                    onDelete: () => _deleteMaterial(material.id),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: MetaSpacing.md),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: MetaSpacing.xl),
              Wrap(
                spacing: MetaSpacing.md,
                runSpacing: MetaSpacing.md,
                children: [
                  FilledButton.icon(
                    onPressed: _uploading ? null : _pickAndUploadPdf,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_uploading ? '업로드 중...' : 'PDF 업로드'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.selectedMaterialIds.isEmpty || _generatingQuiz
                            ? null
                            : _generateQuiz,
                    icon: const Icon(Icons.quiz_outlined),
                    label: Text(_generatingQuiz ? '생성 중...' : '퀴즈 생성'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: MetaSpacing.xl),
        RoundedSection(
          radius: MetaRadii.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('생성된 퀴즈', style: textTheme.titleLarge),
              const SizedBox(height: MetaSpacing.md),
              if (_generatingQuiz)
                const _GeneratingQuizNotice()
              else if (widget.quizSession == null)
                Text('아직 생성된 퀴즈가 없습니다.', style: textTheme.bodyLarge)
              else
                _QuizRunner(
                  api: widget.api,
                  character: widget.character,
                  quiz: widget.quizSession!.quiz,
                  questionIndex: widget.quizSession!.questionIndex,
                  selectedChoice: widget.quizSession!.selectedChoice,
                  answerAffinityDelta: widget.quizSession!.answerAffinityDelta,
                  rewardAlreadyClaimed:
                      widget.quizSession!.rewardAlreadyClaimed,
                  onChoiceSelected: _selectChoice,
                  onExplanationExpanded: _scrollToBottom,
                  onNext: _nextQuestion,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadPdf() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        return;
      }
      final file = result.files.single;
      final material = await widget.api.uploadPdf(
        fileName: file.name,
        bytes: file.bytes!,
      );
      widget.onMaterialUploaded(material);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _setMaterialSelected(String materialId, bool selected) {
    final next = {...widget.selectedMaterialIds};
    if (selected) {
      next.add(materialId);
    } else {
      next.remove(materialId);
    }
    widget.onMaterialSelectionChanged(next);
  }

  Future<void> _deleteMaterial(String materialId) async {
    setState(() => _error = null);
    try {
      await widget.api.deleteMaterial(materialId);
      widget.onMaterialDeleted(materialId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _generateQuiz() async {
    final materialIds = widget.selectedMaterialIds.toList(growable: false);
    if (materialIds.isEmpty) {
      return;
    }
    setState(() {
      _generatingQuiz = true;
      _error = null;
    });
    try {
      final quiz = await widget.api.generateQuiz(
        materialIds: materialIds,
        characterId: widget.character.id,
      );
      widget.onQuizGenerated(quiz);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _generatingQuiz = false);
      }
    }
  }

  Future<void> _selectChoice(int choiceIndex) async {
    final quizSession = widget.quizSession;
    if (quizSession == null || quizSession.selectedChoice != null) {
      return;
    }
    final quiz = quizSession.quiz;
    final question = quiz.questions[quizSession.questionIndex];
    final correct = choiceIndex == question.answerIndex;
    final selectedSession = quizSession.selectChoice(choiceIndex);
    widget.onQuizProgressChanged(selectedSession);
    _scrollToBottom();
    setState(() => _error = null);
    try {
      final affinity = await widget.api.applyAffinityEvent(
        characterId: widget.character.id,
        eventType: correct ? 'quiz_correct' : 'quiz_attempt',
        delta: correct ? 8 : 0,
        rewardKey: '${quiz.id}:q${quizSession.questionIndex}',
      );
      widget.onAffinityChanged(affinity);
      widget
          .onQuizProgressChanged(selectedSession.withAffinityResult(affinity));
      _scrollToBottom();
      if (affinity.unlockedCostumeIds.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('새로운 의상이 공개되었습니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _nextQuestion() {
    final quizSession = widget.quizSession;
    if (quizSession == null) {
      return;
    }
    if (quizSession.questionIndex < quizSession.quiz.questions.length - 1) {
      widget.onQuizProgressChanged(quizSession.moveToNextQuestion());
    } else {
      widget.onQuizCompleted();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _GeneratingQuizNotice extends StatelessWidget {
  const _GeneratingQuizNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: MetaSpacing.md),
        Expanded(
          child: Text(
            '퀴즈를 생성하는 중입니다.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _QuizRunner extends StatelessWidget {
  const _QuizRunner({
    required this.api,
    required this.character,
    required this.quiz,
    required this.questionIndex,
    required this.selectedChoice,
    required this.answerAffinityDelta,
    required this.rewardAlreadyClaimed,
    required this.onChoiceSelected,
    required this.onExplanationExpanded,
    required this.onNext,
  });

  final ApiClient api;
  final CharacterDto character;
  final QuizDto quiz;
  final int questionIndex;
  final int? selectedChoice;
  final int? answerAffinityDelta;
  final bool rewardAlreadyClaimed;
  final ValueChanged<int> onChoiceSelected;
  final VoidCallback onExplanationExpanded;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final question = quiz.questions[questionIndex];
    final answered = selectedChoice != null;
    final correct = selectedChoice == question.answerIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${questionIndex + 1}/${quiz.questions.length}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: MetaSpacing.xs),
        _DifficultyChip(difficulty: question.difficulty),
        const SizedBox(height: MetaSpacing.md),
        Row(
          children: [
            const Icon(Icons.quiz_outlined),
            const SizedBox(width: MetaSpacing.md),
            Expanded(
              child: Text(
                question.question,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        if (question.choices.isNotEmpty) ...[
          const SizedBox(height: MetaSpacing.md),
          ...question.choices.asMap().entries.map(
                (entry) => _ChoiceButton(
                  index: entry.key,
                  label: entry.value,
                  correctIndex: question.answerIndex,
                  selectedIndex: selectedChoice,
                  onTap: () => onChoiceSelected(entry.key),
                ),
              ),
        ],
        if (answered) ...[
          const SizedBox(height: MetaSpacing.md),
          _TutorReactionBubble(
            avatarUrl: api.assetUrl(character.baseImageUrl),
            text: correct ? question.correctReaction : question.wrongReaction,
          ),
          const SizedBox(height: MetaSpacing.md),
          _AffinityGainBar(
            scoreAfter: character.affinityScore,
            delta: answerAffinityDelta,
          ),
          const SizedBox(height: MetaSpacing.md),
          QuizExplanationPanel(
            explanation: question.explanation,
            choices: question.choices,
            explanations: question.choiceExplanations,
            answerIndex: question.answerIndex,
            selectedIndex: selectedChoice!,
            onExpanded: onExplanationExpanded,
          ),
          if (rewardAlreadyClaimed) ...[
            const SizedBox(height: MetaSpacing.md),
            Text(
              '이 문제의 호감도 보상은 이미 반영됐습니다.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: MetaSpacing.lg),
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward),
            label: Text(questionIndex == quiz.questions.length - 1
                ? '퀴즈 끝내기'
                : '다음 문제'),
          ),
        ],
      ],
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final normalized = difficulty.toLowerCase();
    final label = switch (normalized) {
      'easy' => '쉬움',
      'hard' => '어려움',
      _ => '보통',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MetaColors.surfaceSoft,
          borderRadius: BorderRadius.circular(MetaRadii.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MetaSpacing.base,
            vertical: MetaSpacing.xs,
          ),
          child:
              Text('난이도 $label', style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}

class _AffinityGainBar extends StatefulWidget {
  const _AffinityGainBar({
    required this.scoreAfter,
    required this.delta,
  });

  final int scoreAfter;
  final int? delta;

  @override
  State<_AffinityGainBar> createState() => _AffinityGainBarState();
}

class _AffinityGainBarState extends State<_AffinityGainBar> {
  bool _showDelta = false;

  @override
  void didUpdateWidget(covariant _AffinityGainBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delta != widget.delta ||
        oldWidget.scoreAfter != widget.scoreAfter) {
      _showDelta = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final delta = widget.delta;
    final scoreAfter = widget.scoreAfter.clamp(0, 100).toInt();
    final scoreBefore =
        delta == null ? scoreAfter : (scoreAfter - delta).clamp(0, 100).toInt();
    final begin = scoreBefore / 100;
    final end = scoreAfter / 100;

    return Container(
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: MetaColors.surfaceSoft,
        borderRadius: BorderRadius.circular(MetaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('호감도', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              Text(
                '$scoreAfter / 100',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: MetaSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(MetaRadii.full),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('$scoreBefore-$scoreAfter-$delta'),
              tween: Tween(begin: begin, end: end),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              onEnd: () {
                if (mounted && delta != null) {
                  setState(() => _showDelta = true);
                }
              },
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  minHeight: 12,
                  value: value,
                  backgroundColor: MetaColors.hairlineSoft,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(MetaColors.primary),
                );
              },
            ),
          ),
          const SizedBox(height: MetaSpacing.xs),
          AnimatedOpacity(
            opacity: _showDelta || delta == null ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Text(
              delta == null ? '호감도 반영 중...' : '호감도 +$delta',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: MetaColors.primaryDeep,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.selected,
    required this.onChanged,
    required this.onDelete,
  });

  final MaterialDto material;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MetaSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: MetaSpacing.xs,
        vertical: MetaSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: MetaColors.hairlineSoft),
        borderRadius: BorderRadius.circular(MetaRadii.lg),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onChanged(value ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(material.title,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  '${material.chunkCount}개 청크',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '삭제',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _TutorReactionBubble extends StatelessWidget {
  const _TutorReactionBubble({
    required this.avatarUrl,
    required this.text,
  });

  final String avatarUrl;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: Image.network(
            avatarUrl,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: MetaColors.surfaceSoft,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.person, size: 18),
              ),
            ),
          ),
        ),
        const SizedBox(width: MetaSpacing.xs),
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MetaColors.surfaceSoft,
              borderRadius: BorderRadius.circular(MetaRadii.xxl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(MetaSpacing.base),
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.index,
    required this.label,
    required this.correctIndex,
    required this.selectedIndex,
    required this.onTap,
  });

  final int index;
  final String label;
  final int correctIndex;
  final int? selectedIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final answered = selectedIndex != null;
    final isSelected = selectedIndex == index;
    final isCorrect = correctIndex == index;
    final Color borderColor;
    if (!answered) {
      borderColor = MetaColors.hairlineSoft;
    } else if (isCorrect) {
      borderColor = MetaColors.success;
    } else if (isSelected) {
      borderColor = MetaColors.critical;
    } else {
      borderColor = MetaColors.hairlineSoft;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: MetaSpacing.xs),
      child: OutlinedButton(
        onPressed: answered ? null : onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          side: BorderSide(color: borderColor, width: answered ? 2 : 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MetaRadii.xl),
          ),
        ),
        child: Text('${index + 1}. $label'),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: MetaColors.critical.withValues(alpha: 0.08),
        border: Border.all(color: MetaColors.critical),
        borderRadius: BorderRadius.circular(MetaRadii.xl),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: MetaColors.critical),
      ),
    );
  }
}
