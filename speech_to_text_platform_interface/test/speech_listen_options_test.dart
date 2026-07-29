import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  group('copyWith', () {
    test('modifies expected properties', () async {
      final options = SpeechListenOptions(
        onDevice: true,
        partialResults: true,
        listenMode: ListenMode.search,
        sampleRate: 16000,
        cancelOnError: true,
        autoPunctuation: true,
        enableHapticFeedback: true,
        biasingStrings: ['aorta'],
      );
      final modifiedOptions = options.copyWith(
        onDevice: false,
        partialResults: false,
        listenMode: ListenMode.confirmation,
        sampleRate: 8000,
        cancelOnError: false,
        autoPunctuation: false,
        enableHapticFeedback: false,
        biasingStrings: ['TAPSE', 'PSAP'],
      );
      expect(modifiedOptions.onDevice, false);
      expect(modifiedOptions.partialResults, false);
      expect(modifiedOptions.listenMode, ListenMode.confirmation);
      expect(modifiedOptions.sampleRate, 8000);
      expect(modifiedOptions.cancelOnError, false);
      expect(modifiedOptions.autoPunctuation, false);
      expect(modifiedOptions.enableHapticFeedback, false);
      expect(modifiedOptions.biasingStrings, ['TAPSE', 'PSAP']);
    });
    test('retains biasingStrings when not overridden', () async {
      final options = SpeechListenOptions(biasingStrings: ['aorta']);
      expect(options.copyWith(onDevice: true).biasingStrings, ['aorta']);
    });
    test('defaults biasingStrings to null', () async {
      expect(SpeechListenOptions().biasingStrings, isNull);
    });
  });
}
