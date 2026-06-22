import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';

/// 홈 + 채팅을 통합한 비주얼노벨 전체화면.
///
/// 캐릭터 전신 이미지를 배경으로 깔고, 상단에는 관계/호감도 HUD,
/// 하단에는 대화창과 입력창을 띄운다. 별도 홈 탭 없이 이 화면이 메인이다.
class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.api,
    required this.character,
    required this.materials,
    required this.selectedMaterialIds,
    required this.affinityStatus,
  });

  final ApiClient api;
  final CharacterDto character;
  final List<MaterialDto> materials;
  final Set<String> selectedMaterialIds;
  final AffinityStatusDto? affinityStatus;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  static const _dialogueOpacity = 0.82;
  static const _maxChatHistoryMessages = 20;

  final _controller = TextEditingController();
  List<_ChatEntry> _messages = _initialMessages();
  bool _pdfMode = false;
  bool _longReplyMode = false;
  bool _loadingHistory = false;
  bool _sending = false;
  bool _hudCollapsed = false;
  String? _error;
  String? _currentExpressionImageUrl;
  String _currentExpression = 'neutral';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant PlayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _currentExpressionImageUrl = null;
      _currentExpression = 'neutral';
      _loadHistory();
    }
    if (oldWidget.character.baseImageUrl != widget.character.baseImageUrl ||
        oldWidget.character.currentOutfitId !=
            widget.character.currentOutfitId ||
        oldWidget.character.expressionImageUrls !=
            widget.character.expressionImageUrls) {
      _currentExpressionImageUrl = null;
      _currentExpression = 'neutral';
    }
    // 포함된 자료가 모두 사라지면 PDF 모드를 자동으로 해제한다.
    if (_pdfMode && !_hasMaterial) {
      _pdfMode = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final history = await widget.api.listChatMessages(
        characterId: widget.character.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = history.isEmpty
            ? _initialMessages()
            : history
                .map(
                  (message) => _ChatEntry(
                    text: message.text,
                    role: _ChatRole.fromApiRole(message.role),
                  ),
                )
                .toList();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.api.assetUrl(
      _currentExpressionImageUrl ??
          widget.character.baseImageUrl ??
          widget.character.visualNovelImageUrl,
    );
    final lastAssistant = _loadingHistory
        ? '이전 대화를 불러오는 중...'
        : (_latestText(_ChatRole.assistant) ??
            // '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.'
            '안녕, 오늘 하루는 어땠어?');
    final lastUser = _latestText(_ChatRole.user);

    return Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: MetaColors.inkDeep,
              child: Center(
                child: Icon(Icons.person, size: 120, color: MetaColors.canvas),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MetaColors.inkDeep.withValues(alpha: 0.42),
                  MetaColors.inkDeep.withValues(alpha: 0.04),
                  MetaColors.inkDeep.withValues(alpha: 0.78),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
        Positioned(
          right: MetaSpacing.base,
          top: MetaSpacing.xs,
          child: _HudHandle(
            collapsed: _hudCollapsed,
            onPressed: () => setState(() => _hudCollapsed = !_hudCollapsed),
          ),
        ),
        if (!_hudCollapsed)
          Positioned(
            left: MetaSpacing.base,
            right: MetaSpacing.base,
            top: MetaSpacing.xl,
            child: _HudBar(
              character: widget.character,
              affinityStatus: widget.affinityStatus,
              toggles: _buildToggles(),
              onCollapse: () => setState(() => _hudCollapsed = true),
            ),
          ),
        Positioned(
          left: MetaSpacing.base,
          top: _hudCollapsed ? MetaSpacing.xs : 132,
          child: _ExpressionBadge(expression: _currentExpression),
        ),
        Positioned(
          left: MetaSpacing.base,
          right: MetaSpacing.base,
          bottom: MetaSpacing.base,
          child: _DialoguePanel(
            opacity: _dialogueOpacity,
            reply: _sending ? '(생각 중..)' : lastAssistant,
            userText: lastUser,
            error: _error,
            pdfCaption: _pdfMode ? _selectedMaterialTitles() : null,
            onHistory: _showHistory,
            composer: _buildComposer(),
          ),
        ),
      ],
    );
  }

  bool get _hasMaterial =>
      widget.materials.any((m) => widget.selectedMaterialIds.contains(m.id));

  String _selectedMaterialTitles() {
    return widget.materials
        .where((m) => widget.selectedMaterialIds.contains(m.id))
        .map((m) => m.title)
        .join(', ');
  }

  Widget _buildToggles() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _PillToggle(
          offLabel: 'Daily',
          onLabel: 'PDF',
          value: _pdfMode,
          disabled: _sending || !_hasMaterial,
          onChanged: (value) => setState(() => _pdfMode = value),
        ),
        const SizedBox(height: MetaSpacing.xs),
        _PillToggle(
          offLabel: '짧게',
          onLabel: '길게',
          value: _longReplyMode,
          disabled: _sending,
          onChanged: (value) => setState(() => _longReplyMode = value),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !_sending,
            decoration: InputDecoration(
              hintText: _pdfMode ? 'PDF 내용에 대해 질문하기' : '캐릭터에게 말하기',
            ),
            onSubmitted: (_) {
              if (!_sending) {
                _send();
              }
            },
          ),
        ),
        const SizedBox(width: MetaSpacing.md),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send),
          label: const Text('보내기'),
        ),
      ],
    );
  }

  Future<void> _showHistory() async {
    final historyScrollController = ScrollController();
    await _loadHistory();
    if (!mounted) {
      historyScrollController.dispose();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MetaColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(MetaRadii.xxl)),
      ),
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (historyScrollController.hasClients) {
            historyScrollController.jumpTo(
              historyScrollController.position.maxScrollExtent,
            );
          }
        });
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(MetaSpacing.base),
                  child: Row(
                    children: [
                      Text('채팅 기록', style: textTheme.titleLarge),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: _messages.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(MetaSpacing.xl),
                          child: Text('아직 대화 기록이 없어요.',
                              style: textTheme.bodyLarge),
                        )
                      : ListView.builder(
                          controller: historyScrollController,
                          padding: const EdgeInsets.all(MetaSpacing.base),
                          itemCount: _messages.length,
                          itemBuilder: (_, index) => _HistoryRow(
                            entry: _messages[index],
                            characterName: widget.character.name,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(historyScrollController.dispose);
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(_ChatEntry(text: text, role: _ChatRole.user));
      _sending = true;
      _error = null;
    });
    try {
      final response = await widget.api.sendChatMessage(
        characterId: widget.character.id,
        message: text,
        mode: _chatMode(),
        materialIds: _pdfMode
            ? widget.selectedMaterialIds.toList(growable: false)
            : const [],
      );
      setState(() {
        _currentExpression = response.expression;
        _currentExpressionImageUrl = _safeExpressionImageUrl(
              response.expressionImageUrl ??
                  widget.character.expressionImageUrls[response.expression],
            ) ??
            widget.character.baseImageUrl;
        if (response.environmentBox.trim().isNotEmpty) {
          _messages.add(_ChatEntry(
            text: response.environmentBox,
            role: _ChatRole.environment,
          ));
        }
        _messages.add(_ChatEntry(
          text: response.reply,
          role: _ChatRole.assistant,
        ));
        _trimLocalHistory();
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _trimLocalHistory() {
    if (_messages.length <= _maxChatHistoryMessages) {
      return;
    }
    _messages = _messages.sublist(_messages.length - _maxChatHistoryMessages);
  }

  String? _safeExpressionImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return null;
    }
    final baseImageUrl = widget.character.baseImageUrl;
    if (imageUrl == baseImageUrl) {
      return imageUrl;
    }
    if (!imageUrl.contains('/expression_')) {
      return baseImageUrl;
    }
    return imageUrl;
  }

  String? _latestText(_ChatRole role) {
    for (final message in _messages.reversed) {
      if (message.role == role && message.text.trim().isNotEmpty) {
        return message.text;
      }
    }
    return null;
  }

  String _chatMode() {
    if (_pdfMode) {
      return _longReplyMode ? 'study_rag_chat' : 'study_rag_short_chat';
    }
    return _longReplyMode ? 'daily_long_chat' : 'daily_chat';
  }
}

List<_ChatEntry> _initialMessages() {
  return [
    const _ChatEntry(
      // text: '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.',
      text: '안녕, 오늘 하루는 어땠어?',
      role: _ChatRole.assistant,
    ),
  ];
}

class _ChatEntry {
  const _ChatEntry({required this.text, required this.role});

  final String text;
  final _ChatRole role;
}

class _ExpressionBadge extends StatelessWidget {
  const _ExpressionBadge({required this.expression});

  final String expression;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MetaRadii.full),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MetaColors.inkDeep.withValues(alpha: 0.54),
            border: Border.all(
              color: MetaColors.surface.withValues(alpha: 0.28),
            ),
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MetaSpacing.md,
              vertical: MetaSpacing.xs,
            ),
            child: Text(
              '감정: $expression',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: MetaColors.canvas,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChatRole {
  user,
  assistant,
  environment;

  static _ChatRole fromApiRole(String role) {
    return switch (role) {
      'user' => _ChatRole.user,
      'environment' => _ChatRole.environment,
      _ => _ChatRole.assistant,
    };
  }
}

class _HudBar extends StatelessWidget {
  const _HudBar({
    required this.character,
    required this.affinityStatus,
    required this.toggles,
    required this.onCollapse,
  });

  final CharacterDto character;
  final AffinityStatusDto? affinityStatus;
  final Widget toggles;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final score = (affinityStatus?.score ?? character.affinityScore)
        .clamp(0, 100)
        .toInt();
    final stage =
        affinityStatus?.relationshipStageLabel ?? character.relationshipStage;

    return ClipRRect(
      borderRadius: BorderRadius.circular(MetaRadii.xxl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MetaColors.inkDeep.withValues(alpha: 0.46),
            border: Border.all(
              color: MetaColors.surface.withValues(alpha: 0.26),
            ),
            borderRadius: BorderRadius.circular(MetaRadii.xxl),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MetaSpacing.base,
              vertical: MetaSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        style: textTheme.titleLarge?.copyWith(
                          color: MetaColors.canvas,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '관계: $stage · 호감도 $score',
                        style: textTheme.bodyMedium?.copyWith(
                          color: MetaColors.canvas.withValues(alpha: 0.86),
                        ),
                      ),
                      const SizedBox(height: MetaSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(MetaRadii.full),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: score / 100,
                          backgroundColor:
                              MetaColors.surface.withValues(alpha: 0.26),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            MetaColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MetaSpacing.md),
                toggles,
                const SizedBox(width: MetaSpacing.xs),
                IconButton(
                  tooltip: '상단 정보 숨기기',
                  onPressed: onCollapse,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  color: MetaColors.canvas,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HudHandle extends StatelessWidget {
  const _HudHandle({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MetaRadii.full),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MetaColors.inkDeep.withValues(alpha: 0.5),
            border: Border.all(
              color: MetaColors.surface.withValues(alpha: 0.28),
            ),
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
          child: IconButton(
            tooltip: collapsed ? '상단 정보 보이기' : '상단 정보 숨기기',
            onPressed: onPressed,
            icon: Icon(
              collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            ),
            color: MetaColors.canvas,
          ),
        ),
      ),
    );
  }
}

/// 업로드된 ON/OFF 이미지 형태의 토글 스위치.
/// value=false → OFF(흰 배경, 노브 왼쪽, 우측에 offLabel)
/// value=true  → ON(검은 배경, 노브 오른쪽, 좌측에 onLabel)
class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.offLabel,
    required this.onLabel,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final String offLabel;
  final String onLabel;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  static const double _width = 88;
  static const double _height = 38;
  static const double _knob = 28;

  @override
  Widget build(BuildContext context) {
    final label = value ? onLabel : offLabel;
    final labelColor = value ? MetaColors.surface : MetaColors.primaryDeep;

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: value ? MetaColors.primary : MetaColors.surface,
              border: Border.all(
                color: value ? MetaColors.primary : MetaColors.hairline,
              ),
              borderRadius: BorderRadius.circular(MetaRadii.full),
            ),
            child: Stack(
              children: [
                // 노브 반대편에 라벨 표시 (ON/OFF 이미지와 동일한 배치).
                Align(
                  alignment:
                      value ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: labelColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: BoxDecoration(
                        color:
                            value ? MetaColors.surface : MetaColors.primarySoft,
                        border: Border.all(color: MetaColors.hairline),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.characterName});

  final _ChatEntry entry;
  final String characterName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (entry.role == _ChatRole.environment) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: MetaSpacing.xs),
        child: Text(
          entry.text,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: MetaColors.steel,
            fontStyle: FontStyle.italic,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      );
    }

    final isUser = entry.role == _ChatRole.user;
    final label = isUser ? '나' : characterName;
    final labelColor = isUser ? MetaColors.primaryDeep : MetaColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MetaSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelLarge?.copyWith(
              color: labelColor,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.text,
            style: textTheme.bodyLarge?.copyWith(
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialoguePanel extends StatelessWidget {
  const _DialoguePanel({
    required this.opacity,
    required this.reply,
    required this.composer,
    required this.onHistory,
    this.pdfCaption,
    this.userText,
    this.error,
  });

  final double opacity;
  final String reply;
  final String? userText;
  final String? error;
  final String? pdfCaption;
  final VoidCallback onHistory;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(MetaRadii.xxl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MetaColors.surface.withValues(alpha: opacity),
            border:
                Border.all(color: MetaColors.hairline.withValues(alpha: 0.8)),
            borderRadius: BorderRadius.circular(MetaRadii.xxl),
            boxShadow: [
              BoxShadow(
                color: MetaColors.primaryDeep.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(MetaSpacing.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 왼쪽: 직전 내 발화 / 오른쪽: 채팅 기록 버튼.
                Row(
                  children: [
                    Expanded(
                      child: userText == null
                          ? const SizedBox.shrink()
                          : Text(
                              '나: $userText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium,
                            ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onHistory,
                      icon: const Icon(Icons.history, size: 16),
                      label: const Text('채팅 기록'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MetaColors.steel,
                        side: const BorderSide(color: MetaColors.hairline),
                        backgroundColor:
                            MetaColors.surface.withValues(alpha: 0.8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: MetaSpacing.md,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                if (pdfCaption != null && pdfCaption!.isNotEmpty) ...[
                  const SizedBox(height: MetaSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 16,
                        color: MetaColors.steel,
                      ),
                      const SizedBox(width: MetaSpacing.xs),
                      Expanded(
                        child: Text(
                          pdfCaption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: MetaSpacing.xs),
                  Text(
                    error!,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: MetaColors.critical),
                  ),
                ],
                const SizedBox(height: MetaSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(
                      reply,
                      style: textTheme.bodyLarge?.copyWith(
                        color: MetaColors.inkDeep,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MetaSpacing.base),
                composer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
