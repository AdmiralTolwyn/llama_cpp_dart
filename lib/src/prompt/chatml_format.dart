import 'prompt_format.dart';

/// Implementation of the ChatML prompt format (used by Qwen, Yi, etc.).
/// Structure:
/// <|im_start|>system
/// {content}<|im_end|>
/// <|im_start|>user
/// {content}<|im_end|>
/// <|im_start|>assistant
///
/// When [noThink] is `true`, an empty thinking block (`<think>\n\n</think>\n\n`)
/// is appended after every assistant turn opener. This is the canonical Qwen 3
/// "thinking off" trick — equivalent to passing `enable_thinking=False` to the
/// Jinja chat template. Pre-filling an empty thought stops the model from
/// emitting any further `<think>` content and forces it to answer directly.
/// Use for Qwen 3 / Qwen 3.5 / QwQ / DeepSeek-R1 distills when you want fast
/// non-reasoning output.
class ChatMLFormat extends PromptFormat {
  final bool noThink;

  ChatMLFormat({this.noThink = false})
      : super(PromptFormatType.chatml,
            inputSequence: '<|im_start|>user\n',
            outputSequence: '<|im_start|>assistant\n',
            systemSequence: '<|im_start|>system\n',
            stopSequence: '<|im_end|>\n');

  String get _assistantOpener =>
      noThink ? '$outputSequence<think>\n\n</think>\n\n' : outputSequence;

  @override
  String formatPrompt(String prompt) {
    return '$inputSequence$prompt$stopSequence$_assistantOpener';
  }

  @override
  String formatMessages(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();

    for (var message in messages) {
      final role = message['role'];
      final content = message['content'];

      if (role == 'system') {
        buffer.write('$systemSequence$content$stopSequence');
      } else if (role == 'user') {
        buffer.write('$inputSequence$content$stopSequence');
      } else if (role == 'assistant') {
        if (content != null && content.toString().isNotEmpty) {
          buffer.write('$_assistantOpener$content$stopSequence');
        }
      }
    }

    if (messages.isNotEmpty && messages.last['role'] != 'assistant') {
      buffer.write(_assistantOpener);
    } else if (messages.isNotEmpty && messages.last['role'] == 'assistant') {
      final lastContent = messages.last['content'];
      if (lastContent == null || lastContent.toString().isEmpty) {
        buffer.write(_assistantOpener);
      }
    }

    return buffer.toString();
  }
}
