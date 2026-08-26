class SamplerParams {
  double temp = 0.80;
  double dynatempRange = 0.0;
  double dynatempExponent = 1.0;

  int topK = 40;
  double topP = 0.95;
  double minP = 0.05;

  double typical = 1.00;
  double topNSigma = -1.0;

  double xtcProbability = 0.0;
  double xtcThreshold = 0.1;
  
  int mirostat = 0; 
  double mirostatTau = 5.00;
  double mirostatEta = 0.10;
  int mirostatM = 100;

  int penaltyLastTokens = 64;
  double penaltyRepeat = 1.00;
  double penaltyFreq = 0.00;
  double penaltyPresent = 0.00;
  bool penaltyNewline = false;
  bool ignoreEOS = false;

  double dryMultiplier = 0.0;
  double dryBase = 1.75;
  int dryAllowedLen = 2;
  int dryPenaltyLastN = -1;
  List<String> dryBreakers = ["\n", ":", "\"", "*"];

  String grammarStr = "";
  String grammarRoot = "";

  bool greedy = false; 
  bool softmax = true;

  int seed = 0xFFFFFFFF;

  int topPKeep = 1;
  int minPKeep = 1;
  int typicalKeep = 1;
  int xtcKeep = 1;
  int xtcLength = 1;

  SamplerParams();

  /// Returns a deep copy of these params.
  ///
  /// Used by the per-prompt grammar override: the load-time [SamplerParams] are
  /// retained verbatim by [Llama], and each grammar swap rebuilds the sampler
  /// chain from a copy whose [grammarStr]/[grammarRoot] are replaced. Copying
  /// (rather than mutating) keeps the load-time configuration authoritative, so
  /// reverting to "no grammar" restores exactly the chain built at load.
  SamplerParams copy() {
    final c = SamplerParams();
    c.temp = temp;
    c.dynatempRange = dynatempRange;
    c.dynatempExponent = dynatempExponent;
    c.topK = topK;
    c.topP = topP;
    c.minP = minP;
    c.typical = typical;
    c.topNSigma = topNSigma;
    c.xtcProbability = xtcProbability;
    c.xtcThreshold = xtcThreshold;
    c.mirostat = mirostat;
    c.mirostatTau = mirostatTau;
    c.mirostatEta = mirostatEta;
    c.mirostatM = mirostatM;
    c.penaltyLastTokens = penaltyLastTokens;
    c.penaltyRepeat = penaltyRepeat;
    c.penaltyFreq = penaltyFreq;
    c.penaltyPresent = penaltyPresent;
    c.penaltyNewline = penaltyNewline;
    c.ignoreEOS = ignoreEOS;
    c.dryMultiplier = dryMultiplier;
    c.dryBase = dryBase;
    c.dryAllowedLen = dryAllowedLen;
    c.dryPenaltyLastN = dryPenaltyLastN;
    c.dryBreakers = List<String>.from(dryBreakers);
    c.grammarStr = grammarStr;
    c.grammarRoot = grammarRoot;
    c.greedy = greedy;
    c.softmax = softmax;
    c.seed = seed;
    c.topPKeep = topPKeep;
    c.minPKeep = minPKeep;
    c.typicalKeep = typicalKeep;
    c.xtcKeep = xtcKeep;
    c.xtcLength = xtcLength;
    return c;
  }

  SamplerParams.fromJson(Map<String, dynamic> json) {
    temp = (json['temp'] ?? 0.8).toDouble();
    dynatempRange = (json['dynatempRange'] ?? 0.0).toDouble();
    dynatempExponent = (json['dynatempExponent'] ?? 1.0).toDouble();
    
    topK = json['topK'] ?? 40;
    topP = (json['topP'] ?? 0.95).toDouble();
    minP = (json['minP'] ?? 0.05).toDouble();
    
    typical = (json['typical'] ?? 1.0).toDouble();
    topNSigma = (json['topNSigma'] ?? -1.0).toDouble();
    
    if (json['xtcTemperature'] != null) {
      xtcProbability = json['xtcTemperature'];
    } else {
      xtcProbability = (json['xtcProbability'] ?? 0.0).toDouble();
    }
    
    if (json['xtcStartValue'] != null) {
      xtcThreshold = json['xtcStartValue'];
    } else {
      xtcThreshold = (json['xtcThreshold'] ?? 0.1).toDouble();
    }
    
    mirostat = json['mirostat'] ?? 0;
    if (json['mirostat2Tau'] != null && mirostat == 2) {
       mirostatTau = json['mirostat2Tau'];
    } else {
       mirostatTau = (json['mirostatTau'] ?? 5.0).toDouble();
    }
    
    if (json['mirostat2Eta'] != null && mirostat == 2) {
       mirostatEta = json['mirostat2Eta'];
    } else {
       mirostatEta = (json['mirostatEta'] ?? 0.1).toDouble();
    }
    mirostatM = json['mirostatM'] ?? 100;
    
    penaltyLastTokens = json['penaltyLastTokens'] ?? 64;
    penaltyRepeat = (json['penaltyRepeat'] ?? 1.0).toDouble();
    penaltyFreq = (json['penaltyFreq'] ?? 0.0).toDouble();
    penaltyPresent = (json['penaltyPresent'] ?? 0.0).toDouble();
    penaltyNewline = json['penaltyNewline'] ?? false;
    ignoreEOS = json['ignoreEOS'] ?? false;
    
    dryMultiplier = (json['dryMultiplier'] ?? 0.0).toDouble();
    if (json['dryPenalty'] != null && dryMultiplier > 0) {
       dryBase = (json['dryPenalty'] ?? 1.75).toDouble(); 
    } else {
       dryBase = (json['dryBase'] ?? 1.75).toDouble();
    }
    dryAllowedLen = json['dryAllowedLen'] ?? 2;
    dryPenaltyLastN = json['dryPenaltyLastN'] ?? (json['dryLookback'] ?? -1);
    if (json['dryBreakers'] != null) {
      dryBreakers = List<String>.from(json['dryBreakers']);
    }

    grammarStr = json['grammarStr'] ?? "";
    grammarRoot = json['grammarRoot'] ?? "";
    
    greedy = json['greedy'] ?? false;
    seed = json['seed'] ?? 0xFFFFFFFF;
    
    topPKeep = json['topPKeep'] ?? 1;
    minPKeep = json['minPKeep'] ?? 1;
  }

  Map<String, dynamic> toJson() => {
    'temp': temp,
    'dynatempRange': dynatempRange,
    'dynatempExponent': dynatempExponent,
    'topK': topK,
    'topP': topP,
    'minP': minP,
    'typical': typical,
    'topNSigma': topNSigma,
    'xtcProbability': xtcProbability,
    'xtcThreshold': xtcThreshold,
    'mirostat': mirostat,
    'mirostatTau': mirostatTau,
    'mirostatEta': mirostatEta,
    'mirostatM': mirostatM,
    'penaltyLastTokens': penaltyLastTokens,
    'penaltyRepeat': penaltyRepeat,
    'penaltyFreq': penaltyFreq,
    'penaltyPresent': penaltyPresent,
    'penaltyNewline': penaltyNewline,
    'ignoreEOS': ignoreEOS,
    'dryMultiplier': dryMultiplier,
    'dryBase': dryBase,
    'dryAllowedLen': dryAllowedLen,
    'dryPenaltyLastN': dryPenaltyLastN,
    'dryBreakers': dryBreakers,
    'grammarStr': grammarStr,
    'grammarRoot': grammarRoot,
    'greedy': greedy,
    'seed': seed,
  };
}
