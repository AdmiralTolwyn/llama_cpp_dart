import 'dart:convert';

/// Defines a tool (function) that can be called by the model.
///
/// Compatible with OpenAI function calling schema, matching llama.rn's
/// tool calling API.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// A tool call parsed from model output.
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  @override
  String toString() => 'ToolCall($name, $arguments)';
}

/// Result of a tool execution to feed back to the model.
class ToolResult {
  final String toolCallId;
  final String content;

  const ToolResult({
    required this.toolCallId,
    required this.content,
  });
}

/// Parses tool calls from model output text.
///
/// Supports multiple formats:
/// 1. OpenAI-style: `{"name": "func", "arguments": {...}}`
/// 2. llama.cpp generic: `<tool_call>{"name": "func", "arguments": {...}}</tool_call>`
/// 3. Hermes/Qwen style: `<|tool_call|>{"name": "func", "arguments": {...}}<|/tool_call|>`
class ToolCallParser {
  static final _toolCallTagRegex = RegExp(
    r'<(?:\|)?tool_call(?:\|)?>(.*?)<(?:\|)?/tool_call(?:\|)?>',
    dotAll: true,
  );

  static final _functionCallRegex = RegExp(
    r'\{[^{}]*"name"\s*:\s*"([^"]+)"[^{}]*"arguments"\s*:\s*(\{[^{}]*\})',
    dotAll: true,
  );

  /// Parse tool calls from model output text.
  /// Returns empty list if no tool calls found.
  static List<ToolCall> parse(String text) {
    final calls = <ToolCall>[];
    var callId = 0;

    // Try tagged format first
    for (final match in _toolCallTagRegex.allMatches(text)) {
      final content = match.group(1)?.trim() ?? '';
      final call = _parseJsonToolCall(content, 'call_${callId++}');
      if (call != null) calls.add(call);
    }

    if (calls.isNotEmpty) return calls;

    // Try bare JSON format
    for (final match in _functionCallRegex.allMatches(text)) {
      final name = match.group(1) ?? '';
      final argsStr = match.group(2) ?? '{}';
      try {
        final args = jsonDecode(argsStr) as Map<String, dynamic>;
        calls.add(ToolCall(
          id: 'call_${callId++}',
          name: name,
          arguments: args,
        ));
      } catch (_) {}
    }

    return calls;
  }

  static ToolCall? _parseJsonToolCall(String json, String id) {
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final name = obj['name'] as String?;
      if (name == null) return null;

      var args = obj['arguments'];
      if (args is String) {
        args = jsonDecode(args);
      }

      return ToolCall(
        id: id,
        name: name,
        arguments: (args as Map<String, dynamic>?) ?? {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Build the tool definitions section for injection into the prompt.
  /// Uses the model's chat template if available, otherwise falls back
  /// to a generic XML-tagged format.
  static String buildToolsPrompt(List<ToolDefinition> tools) {
    if (tools.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('<|tools|>');
    buf.writeln(jsonEncode(tools.map((t) => t.toJson()).toList()));
    buf.writeln('<|/tools|>');
    return buf.toString();
  }

  /// Format a tool result for injection back into the conversation.
  static String formatToolResult(ToolResult result) {
    return '<tool_response>\n${result.content}\n</tool_response>';
  }
}
