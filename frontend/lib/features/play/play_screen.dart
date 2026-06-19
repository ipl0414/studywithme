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

  final _controller = TextEditingController();
  List<_ChatEntry> _messages = _initialMessages();
  bool _pdfMode = false;
  bool _longReplyMode = false;
  bool _loadingHistory = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant PlayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _loadHistory();
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
      widget.character.baseImageUrl ?? widget.character.visualNovelImageUrl,
    );
    final lastAssistant = _loadingHistory
        ? '이전 대화를 불러오는 중...'
        : (_latestText(_ChatRole.assistant) ??
            '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.');
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
          left: MetaSpacing.base,
          right: MetaSpacing.base,
          top: MetaSpacing.base,
          child: _HudBar(
            character: widget.character,
            affinityStatus: widget.affinityStatus,
          ),
        ),
        Positioned(
          left: MetaSpacing.base,
          right: MetaSpacing.base,
          bottom: MetaSpacing.base,
          child: _DialoguePanel(
            characterName: widget.character.name,
            opacity: _dialogueOpacity,
            reply: _sending ? '(생각 중..)' : lastAssistant,
            userText: lastUser,
            error: _error,
            pdfCaption: _pdfMode ? _selectedMaterialTitles() : null,
            toggles: _buildToggles(),
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
    return Wrap(
      spacing: MetaSpacing.xs,
      runSpacing: MetaSpacing.xs,
      children: [
        _PillToggle(
          offLabel: 'Daily',
          onLabel: 'PDF',
          value: _pdfMode,
          disabled: _sending || !_hasMaterial,
          onChanged: (value) => setState(() => _pdfMode = value),
        ),
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
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
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
      text: '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.',
      role: _ChatRole.assistant,
    ),
  ];
}

class _ChatEntry {
  const _ChatEntry({required this.text, required this.role});

  final String text;
  final _ChatRole role;
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
  });

  final CharacterDto character;
  final AffinityStatusDto? affinityStatus;

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
              color: MetaColors.canvas.withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(MetaRadii.xxl),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MetaSpacing.base,
              vertical: MetaSpacing.md,
            ),
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
                    backgroundColor: MetaColors.canvas.withValues(alpha: 0.26),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(MetaColors.primary),
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
    final labelColor = value ? MetaColors.canvas : MetaColors.inkDeep;

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
              color: value ? MetaColors.inkDeep : MetaColors.canvas,
              border: Border.all(color: MetaColors.inkDeep, width: 2.5),
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
                        color: value ? MetaColors.canvas : MetaColors.inkDeep,
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

class _DialoguePanel extends StatelessWidget {
  const _DialoguePanel({
    required this.characterName,
    required this.opacity,
    required this.reply,
    required this.composer,
    required this.toggles,
    this.pdfCaption,
    this.userText,
    this.error,
  });

  final String characterName;
  final double opacity;
  final String reply;
  final String? userText;
  final String? error;
  final String? pdfCaption;
  final Widget toggles;
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
            color: MetaColors.canvas.withValues(alpha: opacity),
            border:
                Border.all(color: MetaColors.canvas.withValues(alpha: 0.42)),
            borderRadius: BorderRadius.circular(MetaRadii.xxl),
            boxShadow: [
              BoxShadow(
                color: MetaColors.inkDeep.withValues(alpha: 0.18),
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
                // 직전 내 발화는 채팅창 오른쪽 위에 표시.
                if (userText != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '나: $userText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                // Tutor 이름 배지 옆에 모드 토글 (Daily/PDF · 짧게/길게).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DecoratedBox(
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
                          characterName,
                          style: textTheme.labelLarge?.copyWith(
                            color: MetaColors.canvas,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: MetaSpacing.xs),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: toggles,
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
                const SizedBox(height: MetaSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(
                      reply,
                      style: textTheme.bodyLarge?.copyWith(
                        color: MetaColors.inkDeep,
                        height: 1.55,
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
