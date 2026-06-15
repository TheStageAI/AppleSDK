import 'package:flutter/material.dart';
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

import '../backend/settings_model.dart';

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
          // Capture (endpointing) threshold. Applied at agent start.
          _slider('VAD Threshold (capture)', s.vadThreshold, 0.3, 0.8, (v) {
            s.update((s) => s.vadThreshold = v);
          }, decimals: 2),
          _slider('VAD Onset (ms)', s.vadOnsetMs.toDouble(), 32, 320, (v) {
            s.update((s) => s.vadOnsetMs = v.round());
          }),
          _slider('Max Turn Length (ms)', s.maxAccumulationMs.toDouble(), 5000,
              60000, (v) {
            s.update((s) => s.maxAccumulationMs = v.round());
          }),
          // Only used by the VAD endpointer (DNN owns end-of-turn otherwise).
          if (!s.useDnnTurn)
            _slider('Silence Timeout (ms)', s.silenceTimeoutMs.toDouble(), 300,
                2000, (v) {
              s.update((s) => s.silenceTimeoutMs = v.round());
            }),

          _sectionHeader('Turn Detection (end-of-turn)'),
          _toggle('DNN smart-turn (off = VAD silence)', s.useDnnTurn, (v) {
            s.update((s) => s.useDnnTurn = v);
          }),
          if (s.useDnnTurn) ...[
            _note('DNN turn knobs apply on next Start.'),
            _slider('EOT Threshold', s.turnEotThreshold, 0.3, 0.9, (v) {
              s.update((s) => s.turnEotThreshold = v);
            }, decimals: 2),
            _slider('EOT Confirm Count', s.turnEotConfirmCount.toDouble(), 1, 4,
                (v) {
              s.update((s) => s.turnEotConfirmCount = v.round());
            }),
            _note('Consecutive positive verdicts before ending the turn. '
                'Higher = fewer premature cut-offs, slightly more latency.'),
            _slider('EOT High-Confidence', s.turnEotHighConfidence, 0.6, 1.0,
                (v) {
              s.update((s) => s.turnEotHighConfidence = v);
            }, decimals: 2),
            _note('A verdict at/above this commits immediately, skipping '
                'confirmation. 1.0 = always confirm.'),
            _slider('Pause Trigger (ms)', s.turnPauseTriggerMs.toDouble(), 96,
                1000, (v) {
              s.update((s) => s.turnPauseTriggerMs = v.round());
            }),
            _slider('Re-eval Interval (ms, 0=off)',
                s.turnReevalIntervalMs.toDouble(), 0, 1000, (v) {
              s.update((s) => s.turnReevalIntervalMs = v.round());
            }),
            _slider('Max Silence Fallback (ms)',
                s.turnMaxSilenceMs.toDouble(), 1000, 7000, (v) {
              s.update((s) => s.turnMaxSilenceMs = v.round());
            }),
            _slider('Model Window (ms)', s.turnWindowMs.toDouble(), 4000, 8000,
                (v) {
              s.update((s) => s.turnWindowMs = v.round());
            }),
            _slider('Min Speech (ms)', s.turnMinSpeechMs.toDouble(), 0, 500,
                (v) {
              s.update((s) => s.turnMinSpeechMs = v.round());
            }),
            _slider('ASR Silence Hangover (ms)',
                s.turnAsrSilenceHangoverMs.toDouble(), 0, 800, (v) {
              s.update((s) => s.turnAsrSilenceHangoverMs = v.round());
            }),
          ],

          _sectionHeader('Streaming ASR'),
          _toggle('Live caption partials', s.asrStreaming, (v) {
            s.update((s) => s.asrStreaming = v);
          }),
          if (s.asrStreaming)
            _slider('Partial Interval (ms)',
                s.asrPartialIntervalMs.toDouble(), 200, 1500, (v) {
              s.update((s) => s.asrPartialIntervalMs = v.round());
            }),

          _sectionHeader('Diagnostics'),
          _toggle('Debug timeline log', s.debugTimeline, (v) {
            s.update((s) => s.debugTimeline = v);
          }),
          _note(
            'Emits a single cross-node event timeline. Stream on a Mac:\n'
            'log stream --info --predicate \'subsystem == "TheStageAI" '
            'AND category == "Timeline"\'',
          ),

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
            // Number of consecutive positive VAD frames (~32 ms each) to fire
            // a barge-in. 0 = use the ms value above. Higher + a high
            // interrupt threshold rejects noise so the agent won't
            // self-interrupt.
            _slider('Interrupt Onset (ms, 0=use min speech)',
                s.interruptOnsetMs.toDouble(), 0, 640, (v) {
              final ms = v.round();
              s.update((s) => s.interruptOnsetMs = ms);
              widget.agent.updateInterruptConfig(interruptOnsetMs: ms);
            }),
            // Strict barge-in threshold, separate from the capture threshold.
            _slider('Interrupt Threshold', s.interruptThreshold, 0.5, 0.96, (v) {
              s.update((s) => s.interruptThreshold = v);
              widget.agent.updateInterruptConfig(interruptThreshold: v);
            }, decimals: 2),
            _note('Lockouts below apply on next Start.'),
            // Per-message grace at TTS start so AEC can re-converge.
            _slider('Playback Lockout (ms)',
                s.interruptMinPlaybackMs.toDouble(), 0, 1000, (v) {
              s.update((s) => s.interruptMinPlaybackMs = v.round());
            }),
            // One-time longer lockout on the FIRST reply (VPIO cold start).
            // Raise this if the agent self-interrupts right after (re)starting.
            _slider('Initial Lockout (ms, 1st reply)',
                s.interruptInitialLockoutMs.toDouble(), 0, 3000, (v) {
              s.update((s) => s.interruptInitialLockoutMs = v.round());
            }),
            // Lockout while thinking (post end-of-turn, pre-TTS).
            _slider('Thinking Lockout (ms)',
                s.interruptThinkingLockoutMs.toDouble(), 0, 2000, (v) {
              s.update((s) => s.interruptThinkingLockoutMs = v.round());
            }),
          ],

          _sectionHeader('Audio'),
          _slider('Pre-roll (ms)', s.preRollMs.toDouble(), 0, 500, (v) {
            s.update((s) => s.preRollMs = v.round());
          }),
          _toggle('AEC Enabled', s.aecEnabled, (v) {
            s.update((s) => s.aecEnabled = v);
          }),
          if (s.aecEnabled) ...[
            // Silence pumped to the speaker at start so VPIO has echo reference
            // before the first TTS. Raise for more cold-start margin.
            _slider('AEC Warmup (ms)', s.aecWarmupMs.toDouble(), 0, 1000, (v) {
              s.update((s) => s.aecWarmupMs = v.round());
            }),
            _slider('Playback Gate Tail (ms)',
                s.aecPlaybackGateTailMs.toDouble(), 0, 500, (v) {
              s.update((s) => s.aecPlaybackGateTailMs = v.round());
            }),
          ],

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

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.outline,
        ),
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
