import '../Vocabulary.dart';
import '../atn/ATNConfigSet.dart';
import '../atn/ATNState.dart';
import 'DFASerializer.dart';
import 'DFAState.dart';

class DFA {
  /** A set of all DFA states. Use {@link Map} so we can get old state back
   *  ({@link Set} only allows you to see if it's there).
   */

  Map<DFAState, DFAState> states = {};

  DFAState s0;

  int decision;

  /** From which ATN state did we create this DFA? */

  DecisionState atnStartState;

  /**
   * {@code true} if this DFA is for a precedence decision; otherwise,
   * {@code false}. This is the backing field for {@link #isPrecedenceDfa}.
   */
  bool precedenceDfa;

  DFA(this.atnStartState, [this.decision]) {
    bool precedenceDfa = false;
    if (atnStartState is StarLoopEntryState) {
      if ((atnStartState as StarLoopEntryState).isPrecedenceDecision) {
        precedenceDfa = true;
        DFAState precedenceState = new DFAState(configs: ATNConfigSet());
        precedenceState.edges = [];
        precedenceState.isAcceptState = false;
        precedenceState.requiresFullContext = false;
        this.s0 = precedenceState;
      }
    }

    this.precedenceDfa = precedenceDfa;
  }

  /**
   * Gets whether this DFA is a precedence DFA. Precedence DFAs use a special
   * start state {@link #s0} which is not stored in {@link #states}. The
   * {@link DFAState#edges} array for this start state contains outgoing edges
   * supplying individual start states corresponding to specific precedence
   * values.
   *
   * @return {@code true} if this is a precedence DFA; otherwise,
   * {@code false}.
   * @see Parser#getPrecedence()
   */
  bool isPrecedenceDfa() {
    return precedenceDfa;
  }

  /**
   * Get the start state for a specific precedence value.
   *
   * @param precedence The current precedence.
   * @return The start state corresponding to the specified precedence, or
   * {@code null} if no start state exists for the specified precedence.
   *
   * @throws IllegalStateException if this is not a precedence DFA.
   * @see #isPrecedenceDfa()
   */
  DFAState getPrecedenceStartState(int precedence) {
    if (!isPrecedenceDfa()) {
      throw new StateError(
          "Only precedence DFAs may contain a precedence start state.");
    }

    // s0.edges is never null for a precedence DFA
    if (precedence < 0 || precedence >= s0.edges.length) {
      return null;
    }

    return s0.edges[precedence];
  }

  /**
   * Set the start state for a specific precedence value.
   *
   * @param precedence The current precedence.
   * @param startState The start state corresponding to the specified
   * precedence.
   *
   * @throws IllegalStateException if this is not a precedence DFA.
   * @see #isPrecedenceDfa()
   */
  void setPrecedenceStartState(int precedence, DFAState startState) {
    if (!isPrecedenceDfa()) {
      throw new StateError(
          "Only precedence DFAs may contain a precedence start state.");
    }

    if (precedence < 0) {
      return;
    }

    // synchronization on s0 here is ok. when the DFA is turned into a
    // precedence DFA, s0 will be initialized once and not updated again
    // s0.edges is never null for a precedence DFA
    if (precedence >= s0.edges.length) {
      final original = s0.edges;
      s0.edges = List(precedence + 1);
      List.copyRange(s0.edges, 0, original);
    }

    s0.edges[precedence] = startState;
  }

  /**
   * Return a list of all states in this DFA, ordered by state number.
   */

  List<DFAState> getStates() {
    List<DFAState> result = states.keys.toList();
    result.sort((DFAState o1, DFAState o2) {
      return o1.stateNumber - o2.stateNumber;
    });

    return result;
  }

  String toString([Vocabulary vocabulary]) {
    vocabulary = vocabulary ?? VocabularyImpl.EMPTY_VOCABULARY;
    if (s0 == null) {
      return "";
    }

    DFASerializer serializer = new DFASerializer(this, vocabulary);
    return serializer.toString();
  }

  String toLexerString() {
    if (s0 == null) return "";
    DFASerializer serializer = new LexerDFASerializer(this);
    return serializer.toString();
  }
}
