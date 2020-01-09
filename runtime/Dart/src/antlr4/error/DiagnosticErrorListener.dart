import 'package:bit_array/bit_array.dart';

import '../IntervalSet.dart';
import '../Parser.dart';
import '../atn/ATNConfig.dart';
import '../atn/ATNConfigSet.dart';
import '../dfa/DFA.dart';
import 'ErrorListener.dart';

/**
 * This implementation of {@link ANTLRErrorListener} can be used to identify
 * certain potential correctness and performance problems in grammars. "Reports"
 * are made by calling {@link Parser#notifyErrorListeners} with the appropriate
 * message.
 *
 * <ul>
 * <li><b>Ambiguities</b>: These are cases where more than one path through the
 * grammar can match the input.</li>
 * <li><b>Weak context sensitivity</b>: These are cases where full-context
 * prediction resolved an SLL conflict to a unique alternative which equaled the
 * minimum alternative of the SLL conflict.</li>
 * <li><b>Strong (forced) context sensitivity</b>: These are cases where the
 * full-context prediction resolved an SLL conflict to a unique alternative,
 * <em>and</em> the minimum alternative of the SLL conflict was found to not be
 * a truly viable alternative. Two-stage parsing cannot be used for inputs where
 * this situation occurs.</li>
 * </ul>
 *
 * @author Sam Harwell
 */
class DiagnosticErrorListener extends BaseErrorListener {
  /**
   * When {@code true}, only exactly known ambiguities are reported.
   */
  final bool exactOnly;

  /**
   * Initializes a new instance of {@link DiagnosticErrorListener}, specifying
   * whether all ambiguities or only exact ambiguities are reported.
   *
   * @param exactOnly {@code true} to report only exact ambiguities, otherwise
   * {@code false} to report all ambiguities.
   */
  DiagnosticErrorListener([this.exactOnly = true]);

  void reportAmbiguity(Parser recognizer, DFA dfa, int startIndex,
      int stopIndex, bool exact, BitArray ambigAlts, ATNConfigSet configs) {
    if (exactOnly && !exact) {
      return;
    }

    final decision = getDecisionDescription(recognizer, dfa);
    final conflictingAlts = getConflictingAlts(ambigAlts, configs);
    final text =
        recognizer.getTokenStream().getText(Interval.of(startIndex, stopIndex));
    final message =
        "reportAmbiguity d=$decision: ambigAlts=$conflictingAlts, input='$text'";
    recognizer.notifyErrorListeners(message);
  }

  void reportAttemptingFullContext(Parser recognizer, DFA dfa, int startIndex,
      int stopIndex, BitArray conflictingAlts, ATNConfigSet configs) {
    final decision = getDecisionDescription(recognizer, dfa);
    final text =
        recognizer.getTokenStream().getText(Interval.of(startIndex, stopIndex));
    final message = "reportAttemptingFullContext d=$decision, input='$text'";
    recognizer.notifyErrorListeners(message);
  }

  void reportContextSensitivity(Parser recognizer, DFA dfa, int startIndex,
      int stopIndex, int prediction, ATNConfigSet configs) {
    String decision = getDecisionDescription(recognizer, dfa);
    String text =
        recognizer.getTokenStream().getText(Interval.of(startIndex, stopIndex));
    String message = "reportContextSensitivity d=$decision, input='$text'";
    recognizer.notifyErrorListeners(message);
  }

  String getDecisionDescription(Parser recognizer, DFA dfa) {
    int decision = dfa.decision;
    int ruleIndex = dfa.atnStartState.ruleIndex;

    final ruleNames = recognizer.getRuleNames();
    if (ruleIndex < 0 || ruleIndex >= ruleNames.length) {
      return decision.toString();
    }

    final ruleName = ruleNames[ruleIndex];
    if (ruleName == null || ruleName.isEmpty) {
      return decision.toString();
    }

    return "$decision ($ruleName)";
  }

  /**
   * Computes the set of conflicting or ambiguous alternatives from a
   * configuration set, if that information was not already provided by the
   * parser.
   *
   * @param reportedAlts The set of conflicting or ambiguous alternatives, as
   * reported by the parser.
   * @param configs The conflicting or ambiguous configuration set.
   * @return Returns {@code reportedAlts} if it is not {@code null}, otherwise
   * returns the set of alternatives represented in {@code configs}.
   */
  BitArray getConflictingAlts(BitArray reportedAlts, ATNConfigSet configs) {
    if (reportedAlts != null) {
      return reportedAlts;
    }

    BitArray result = new BitArray();
    for (ATNConfig config in configs) {
      result.setBit(config.alt);
    }

    return result;
  }
}
