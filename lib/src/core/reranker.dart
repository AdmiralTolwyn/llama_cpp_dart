/// Reranking API for document relevance scoring.
///
/// Requires a reranker model (e.g., jina-reranker, bge-reranker) loaded
/// with `embedding: true` and `pooling_type: 'rank'`.
///
/// Usage:
/// ```dart
/// final results = await reranker.rerank(
///   'What is artificial intelligence?',
///   ['AI is a branch of CS.', 'The weather is nice.', 'ML is a subset of AI.'],
/// );
/// // Results sorted by relevance score (highest first)
/// ```
///
/// Mirrors llama.rn's `context.rerank(query, documents, params)` API.
class RerankResult {
  final int index;
  final double score;
  final String document;

  const RerankResult({
    required this.index,
    required this.score,
    required this.document,
  });

  @override
  String toString() => 'RerankResult(idx=$index, score=${score.toStringAsFixed(4)}, doc=${document.substring(0, document.length.clamp(0, 50))})';
}

/// High-level rerank interface.
///
/// Note: This is a protocol definition. The actual implementation requires
/// a model loaded in embedding+rank mode, which uses `llama_encode` + 
/// `llama_get_embeddings_seq` from the FFI layer. The LlamaService needs
/// to expose this flow.
///
/// For now, this defines the API surface matching llama.rn so that
/// consuming code can program against it.
abstract class Reranker {
  /// Rank documents by relevance to a query.
  /// Returns results sorted by score descending (most relevant first).
  Future<List<RerankResult>> rerank(
    String query,
    List<String> documents, {
    bool normalize = true,
  });
}

/// Stub implementation that returns documents in original order with
/// uniform scores. Used when no reranker model is available.
class NoOpReranker implements Reranker {
  @override
  Future<List<RerankResult>> rerank(
    String query,
    List<String> documents, {
    bool normalize = true,
  }) async {
    return List.generate(
      documents.length,
      (i) => RerankResult(
        index: i,
        score: 1.0 / (i + 1),
        document: documents[i],
      ),
    );
  }
}
