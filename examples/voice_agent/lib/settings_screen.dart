import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import 'settings_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.agent,
  });
  final VoiceAgentSettings settings;
  final TheStageVoiceAgentFlutter agent;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  VoiceAgentSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    s.addListener(_refresh);
  }

  @override
  void dispose() {
    s.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _sectionHeader('Voice & Language'),
          _dropdown('TTS Voice', s.ttsVoice,
              VoiceAgentSettings.availableVoices, (v) {
            s.update((s) => s.ttsVoice = v);
          }),
          _dropdown('STT Language', s.sttLanguage,
              VoiceAgentSettings.availableLanguages, (v) {
            s.update((s) => s.sttLanguage = v);
          }),
          _textField('System Prompt', s.systemPrompt, (v) {
            s.update((s) => s.systemPrompt = v);
          }, maxLines: 3),

          _sectionHeader('LLM Provider'),
          _dropdown('Provider', s.llmProvider, ['openai_compatible'], (v) {
            s.update((s) => s.llmProvider = v);
          }),
          _textField('Model', s.llmModel, (v) {
            s.update((s) => s.llmModel = v);
          }),
          _textField('Endpoint', s.llmEndpoint, (v) {
            s.update((s) => s.llmEndpoint = v);
          }),
          _slider('Max Tokens', s.maxTokens.toDouble(), 64, 1024, (v) {
            s.update((s) => s.maxTokens = v.round());
          }),
          _slider('Temperature', s.temperature, 0.0, 1.5, (v) {
            s.update((s) => s.temperature = v);
          }, decimals: 2),

          _sectionHeader('Endpointing'),
          _slider('Silence Timeout (ms)', s.silenceTimeoutMs.toDouble(), 300,
              2000, (v) {
            s.update((s) => s.silenceTimeoutMs = v.round());
          }),
          _slider('VAD Threshold', s.vadThreshold, 0.3, 0.8, (v) {
            s.update((s) => s.vadThreshold = v);
          }, decimals: 2),

          _sectionHeader('Wake Word'),
          _toggle('Wake Word Enabled', s.wakeWordEnabled, (v) {
            s.update((s) => s.wakeWordEnabled = v);
          }),
          if (s.wakeWordEnabled) ...[
            _slider('WW Threshold', s.wwThreshold, 0.5, 0.9, (v) {
              s.update((s) => s.wwThreshold = v);
            }, decimals: 2),
            _slider('Conversation Timeout (s)',
                s.conversationTimeoutSec.toDouble(), 0, 120, (v) {
              s.update((s) => s.conversationTimeoutSec = v.round());
            }),
          ],

          _sectionHeader('Interruption'),
          _toggle('Allow Interruptions', s.allowInterruptions, (v) {
            s.update((s) => s.allowInterruptions = v);
          }),
          if (s.allowInterruptions) ...[
            _dropdown(
                'Interrupt Mode', s.interruptMode, ['speech_only', 'wake_word'],
                (v) {
              s.update((s) => s.interruptMode = v);
              widget.agent.updateInterruptConfig(interruptMode: v);
            }),
            _slider('Min Speech to Interrupt (ms)',
                s.interruptMinSpeechMs.toDouble(), 100, 1500, (v) {
              final ms = v.round();
              s.update((s) => s.interruptMinSpeechMs = ms);
              widget.agent
                  .updateInterruptConfig(interruptMinSpeechMs: ms);
            }),
          ],

          _sectionHeader('Audio'),
          _slider('Pre-roll (ms)', s.preRollMs.toDouble(), 0, 500, (v) {
            s.update((s) => s.preRollMs = v.round());
          }),
          _toggle('AEC Enabled', s.aecEnabled, (v) {
            s.update((s) => s.aecEnabled = v);
          }),

          _sectionHeader('Debug'),
          _toggle('Show Metrics', s.showMetrics, (v) {
            s.update((s) => s.showMetrics = v);
          }),
          _toggle('Show Partial Transcript', s.showPartialTranscript, (v) {
            s.update((s) => s.showPartialTranscript = v);
          }),
          _toggle('Speculative Whisper', s.speculativeWhisper, (v) {
            s.update((s) => s.speculativeWhisper = v);
          }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _dropdown(
      String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<String>(
            value: value,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {int decimals = 0}) {
    final displayValue = decimals > 0
        ? value.toStringAsFixed(decimals)
        : value.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(displayValue,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _textField(
      String label, String value, ValueChanged<String> onChanged,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: TextEditingController(text: value),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }
}
