import 'ts_agent_node.dart';
import 'audio_player.dart';
import 'screen_recorder.dart';
import 'ts_voice_agent.dart';

// ---------------------------------------------------------------------------
// TheStage* compatibility aliases
// ---------------------------------------------------------------------------
// The classes were renamed `TheStage*` -> `TS*`. `TheStageFlutterSDK` keeps
// its name: it is the SDK handle and matches the `thestage_apple_sdk` package.
//
// `TheStageVoiceAgentFlutter` became `TSVoiceAgent` — the `Flutter` suffix
// existed only to avoid colliding with the Swift `TheStageVoiceAgent`, and
// with the `TS` prefix there is no collision left to avoid.
//
// These live in one file so removing the compatibility surface later is a
// single deletion.

@Deprecated('Use TSVoiceAgent')
typedef TheStageVoiceAgentFlutter = TSVoiceAgent;

@Deprecated('Use TSAgentNode')
typedef TheStageAgentNode = TSAgentNode;

@Deprecated('Use TSAgentState')
typedef TheStageAgentState = TSAgentState;

@Deprecated('Use TSAudioPlayer')
typedef TheStageAudioPlayer = TSAudioPlayer;

@Deprecated('Use TSScreenRecorder')
typedef TheStageScreenRecorder = TSScreenRecorder;
