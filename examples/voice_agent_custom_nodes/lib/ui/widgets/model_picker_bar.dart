import 'package:flutter/material.dart';

import '../../backend/settings_model.dart';

// ============================================================================
// FRONTEND — compact model pickers (iOS inset grouped style)
// ============================================================================
class ModelPickerBar extends StatelessWidget {
  const ModelPickerBar({
    super.key,
    required this.settings,
    this.enabled = true,
  });

  final VoiceAgentSettings settings;
  final bool enabled;

  String _short(String id) {
    final slash = id.lastIndexOf('/');
    return slash >= 0 ? id.substring(slash + 1) : id;
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final scheme = Theme.of(context).colorScheme;

    final llmValue = s.useLocalBundles ? s.localLlmBundle : s.llmModel;
    final llmOptions = s.useLocalBundles
        ? VoiceAgentSettings.availableLocalLlms
        : VoiceAgentSettings.availableHfLlms;

    final asrValue = s.useLocalBundles ? s.localSttBundle : s.sttRepo;
    final asrOptions = s.useLocalBundles
        ? VoiceAgentSettings.availableLocalAsr
        : VoiceAgentSettings.availableHfAsr;

    final ttsValue = s.useLocalBundles ? s.localTtsBundle : s.ttsRepo;
    final ttsOptions = s.useLocalBundles
        ? VoiceAgentSettings.availableLocalTts
        : VoiceAgentSettings.availableHfTts;

    final rows = <Widget>[
      if (s.llmProvider == 'local')
        _PickerRow(
          label: 'LLM',
          value: llmValue,
          options: llmOptions,
          enabled: enabled,
          shortLabel: true,
          short: _short,
          onChanged: (v) => s.update((x) {
            if (x.useLocalBundles) {
              x.localLlmBundle = v;
            } else {
              x.llmModel = v;
            }
          }),
        ),
      _PickerRow(
        label: 'ASR',
        value: asrValue,
        options: asrOptions,
        enabled: enabled,
        shortLabel: true,
        short: _short,
        onChanged: (v) => s.update((x) {
          if (x.useLocalBundles) {
            x.localSttBundle = v;
          } else {
            x.sttRepo = v;
          }
        }),
      ),
      _PickerRow(
        label: 'TTS',
        value: ttsValue,
        options: ttsOptions,
        enabled: enabled,
        shortLabel: true,
        short: _short,
        onChanged: (v) => s.update((x) {
          if (x.useLocalBundles) {
            x.selectLocalTtsBundle(v);
          } else {
            x.selectTtsRepo(v);
          }
        }),
      ),
      _PickerRow(
        label: 'Voice',
        value: s.ttsVoice,
        options: s.voicesForSelectedTts,
        enabled: enabled,
        shortLabel: false,
        short: _short,
        onChanged: (v) => s.update((x) => x.ttsVoice = v),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Text(
              enabled ? 'MODELS' : 'MODELS · STOP TO CHANGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.08,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1)
                    Divider(
                      height: 0.33,
                      thickness: 0.33,
                      indent: 16,
                      color: scheme.outline.withValues(alpha: 0.55),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    required this.shortLabel,
    required this.short,
  });

  final String label;
  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool shortLabel;
  final String Function(String) short;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = options.contains(value)
        ? value
        : (options.isEmpty ? value : options.first);
    final display = shortLabel ? short(effective) : effective;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => _showPicker(context, effective) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  display,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: -0.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context, String effective) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.08,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final o in options)
                ListTile(
                  title: Text(
                    shortLabel ? short(o) : o,
                    style: const TextStyle(
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                  trailing: o == effective
                      ? Icon(Icons.check_rounded,
                          color: scheme.primary, size: 22)
                      : null,
                  onTap: () => Navigator.pop(ctx, o),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null) onChanged(chosen);
  }
}
