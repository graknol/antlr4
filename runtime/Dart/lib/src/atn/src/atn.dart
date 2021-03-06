/*
 * Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

import 'dart:collection';

import '../../interval_set.dart';
import '../../ll1_analyzer.dart';
import '../../rule_context.dart';
import '../../token.dart';
import 'atn_state.dart';
import 'atn_type.dart';
import 'lexer_action.dart';
import 'transition.dart';

class ATN {
  static final INVALID_ALT_NUMBER = 0;

  List<ATNState> states = [];

  /** Each subrule/rule is a decision point and we must track them so we
   *  can go back later and build DFA predictors for them.  This includes
   *  all the rules, subrules, optional blocks, ()+, ()* etc...
   */
  List<DecisionState> decisionToState = [];

  /**
   * Maps from rule index to starting state number.
   */
  List<RuleStartState> ruleToStartState;

  /**
   * Maps from rule index to stop state number.
   */
  List<RuleStopState> ruleToStopState;

  Map<String, TokensStartState> modeNameToStartState = LinkedHashMap();

  /**
   * The type of the ATN.
   */
  final ATNType grammarType;

  /**
   * The maximum value for any symbol recognized by a transition in the ATN.
   */
  final int maxTokenType;

  /**
   * For lexer ATNs, this maps the rule index to the resulting token type.
   * For parser ATNs, this maps the rule index to the generated bypass token
   * type if the
   * {@link ATNDeserializationOptions#isGenerateRuleBypassTransitions}
   * deserialization option was specified; otherwise, this is null.
   */
  List<int> ruleToTokenType;

  /**
   * For lexer ATNs, this is an array of [LexerAction] objects which may
   * be referenced by action transitions in the ATN.
   */
  List<LexerAction> lexerActions;

  List<TokensStartState> modeToStartState = [];

  /** Used for runtime deserialization of ATNs from strings */
  ATN(this.grammarType, this.maxTokenType);

  /**
   * TODO merge doc comment
   * Compute the set of valid tokens that can occur starting in state [s].
   *  If [ctx] is null, the set of tokens will not include what can follow
   *  the rule surrounding [s]. In other words, the set will be
   *  restricted to tokens reachable staying within [s]'s rule.
   *
   *  Compute the set of valid tokens that can occur starting in [s] and
   *  staying in same rule. {@link Token#EPSILON} is in set if we reach end of
   *  rule.
   */
  IntervalSet nextTokens(ATNState s, [RuleContext ctx]) {
    if (ctx != null) {
      return LL1Analyzer(this).LOOK(s, ctx);
    }
    if (s.nextTokenWithinRule != null) return s.nextTokenWithinRule;
    s.nextTokenWithinRule = LL1Analyzer(this).LOOK(s, null);
    s.nextTokenWithinRule.setReadonly(true);
    return s.nextTokenWithinRule;
  }

  void addState(ATNState state) {
    if (state != null) {
      state.atn = this;
      state.stateNumber = states.length;
    }

    states.add(state);
  }

  void removeState(ATNState state) {
    states[state.stateNumber] =
        null; // just free mem, don't shift states in list
  }

  int defineDecisionState(DecisionState s) {
    decisionToState.add(s);
    s.decision = decisionToState.length - 1;
    return s.decision;
  }

  DecisionState getDecisionState(int decision) {
    if (!decisionToState.isEmpty) {
      return decisionToState[decision];
    }
    return null;
  }

  int get numberOfDecisions {
    return decisionToState.length;
  }

  /**
   * Computes the set of input symbols which could follow ATN state number
   * [stateNumber] in the specified full [context]. This method
   * considers the complete parser context, but does not evaluate semantic
   * predicates (i.e. all predicates encountered during the calculation are
   * assumed true). If a path in the ATN exists from the starting state to the
   * [RuleStopState] of the outermost context without matching any
   * symbols, {@link Token#EOF} is added to the returned set.
   *
   * <p>If [context] is null, it is treated as {@link ParserRuleContext#EMPTY}.</p>
   *
   * Note that this does NOT give you the set of all tokens that could
   * appear at a given token position in the input phrase.  In other words,
   * it does not answer:
   *
   *   "Given a specific partial input phrase, return the set of all tokens
   *    that can follow the last token in the input phrase."
   *
   * The big difference is that with just the input, the parser could
   * land right in the middle of a lookahead decision. Getting
   * all *possible* tokens given a partial input stream is a separate
   * computation. See https://github.com/antlr/antlr4/issues/1428
   *
   * For this function, we are specifying an ATN state and call stack to compute
   * what token(s) can come next and specifically: outside of a lookahead decision.
   * That is what you want for error reporting and recovery upon parse error.
   *
   * @param stateNumber the ATN state number
   * @param context the full parse context
   * @return The set of potentially valid input symbols which could follow the
   * specified state in the specified context.
   * @throws IllegalArgumentException if the ATN does not contain a state with
   * number [stateNumber]
   */
  IntervalSet getExpectedTokens(int stateNumber, RuleContext context) {
    if (stateNumber < 0 || stateNumber >= states.length) {
      throw new RangeError.index(stateNumber, states, "stateNumber");
    }

    RuleContext ctx = context;
    ATNState s = states[stateNumber];
    IntervalSet following = nextTokens(s);
    if (!following.contains(Token.EPSILON)) {
      return following;
    }

    IntervalSet expected = new IntervalSet();
    expected.addAll(following);
    expected.remove(Token.EPSILON);
    while (ctx != null &&
        ctx.invokingState >= 0 &&
        following.contains(Token.EPSILON)) {
      ATNState invokingState = states[ctx.invokingState];
      RuleTransition rt = invokingState.transition(0);
      following = nextTokens(rt.followState);
      expected.addAll(following);
      expected.remove(Token.EPSILON);
      ctx = ctx.parent;
    }

    if (following.contains(Token.EPSILON)) {
      expected.addOne(Token.EOF);
    }

    return expected;
  }
}
