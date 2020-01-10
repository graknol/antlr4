/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

import 'dart:developer';

import 'common_token_factory.dart';
import 'int_stream.dart';
import 'interval_set.dart';
import 'lexer.dart';
import 'parser_rule_context.dart';
import 'recognizer.dart';
import 'rule_context.dart';
import 'token.dart';
import 'token_source.dart';
import 'token_stream.dart';
import 'atn/atn.dart';
import 'atn/atn_deserialization_options.dart';
import 'atn/atn_deserializer.dart';
import 'atn/atn_simulator.dart';
import 'atn/atn_state.dart';
import 'atn/parser_atn_simulator.dart';
import 'atn/prediction_mode.dart';
import 'atn/profiling_atn_simulator.dart';
import 'atn/Transition.dart';
import 'atn/info.dart';
import 'dfa/dfa.dart';
import 'error/error_listener.dart';
import 'error/error_strategy.dart';
import 'error/errors.dart';
import 'tree/tree.dart';
import 'tree/pattern/parse_tree_match.dart';

/** This is all the parsing support code essentially; most of it is error recovery stuff. */
abstract class Parser extends Recognizer<ParserATNSimulator> {
  /**
   * This field maps from the serialized ATN string to the deserialized {@link ATN} with
   * bypass alternatives.
   *
   * @see ATNDeserializationOptions#isGenerateRuleBypassTransitions()
   */
  static final Map<String, ATN> bypassAltsAtnCache = {};

  /**
   * The error handling strategy for the parser. The default value is a new
   * instance of {@link DefaultErrorStrategy}.
   *
   * @see #getErrorHandler
   * @see #setErrorHandler
   */

  ErrorStrategy _errHandler = new DefaultErrorStrategy();

  /**
   * The input stream.
   *
   * @see #getInputStream
   * @see #setInputStream
   */
  TokenStream _input;

  final List<int> _precedenceStack = [0];

  /**
   * The {@link ParserRuleContext} object for the currently executing rule.
   * This is always non-null during the parsing process.
   */
  ParserRuleContext _ctx;

  /**
   * Specifies whether or not the parser should construct a parse tree during
   * the parsing process. The default value is {@code true}.
   *
   * @see #getBuildParseTree
   * @see #setBuildParseTree
   */
  bool _buildParseTrees = true;

  /**
   * When {@link #setTrace}{@code (true)} is called, a reference to the
   * {@link TraceListener} is stored here so it can be easily removed in a
   * later call to {@link #setTrace}{@code (false)}. The listener itself is
   * implemented as a parser listener so this field is not directly used by
   * other parser methods.
   */
  TraceListener _tracer;

  /**
   * The list of {@link ParseTreeListener} listeners registered to receive
   * events during the parse.
   *
   * @see #addParseListener
   */
  List<ParseTreeListener> _parseListeners;

  /**
   * The number of syntax errors reported during parsing. This value is
   * incremented each time {@link #notifyErrorListeners} is called.
   */
  int _syntaxErrors;

  /** Indicates parser has match()ed EOF token. See {@link #exitRule()}. */
  bool matchedEOF;

  Parser(TokenStream input) {
    setInputStream(input);
  }

  /** reset the parser's state */
  void reset() {
    if (inputStream != null) inputStream.seek(0);
    _errHandler.reset(this);
    _ctx = null;
    _syntaxErrors = 0;
    matchedEOF = false;
    setTrace(false);
    _precedenceStack.clear();
    _precedenceStack.add(0);
    ATNSimulator interpreter = getInterpreter();
    if (interpreter != null) {
      interpreter.reset();
    }
  }

  /**
   * Match current input symbol against {@code ttype}. If the symbol type
   * matches, {@link ANTLRErrorStrategy#reportMatch} and {@link #consume} are
   * called to complete the match process.
   *
   * <p>If the symbol type does not match,
   * {@link ANTLRErrorStrategy#recoverInline} is called on the current error
   * strategy to attempt recovery. If {@link #getBuildParseTree} is
   * {@code true} and the token index of the symbol returned by
   * {@link ANTLRErrorStrategy#recoverInline} is -1, the symbol is added to
   * the parse tree by calling {@link #createErrorNode(ParserRuleContext, Token)} then
   * {@link ParserRuleContext#addErrorNode(ErrorNode)}.</p>
   *
   * @param ttype the token type to match
   * @return the matched symbol
   * @throws RecognitionException if the current input symbol did not match
   * {@code ttype} and the error strategy could not recover from the
   * mismatched symbol
   */
  Token match(int ttype) {
    Token t = getCurrentToken();
    if (t.type == ttype) {
      if (ttype == Token.EOF) {
        matchedEOF = true;
      }
      _errHandler.reportMatch(this);
      consume();
    } else {
      t = _errHandler.recoverInline(this);
      if (_buildParseTrees && t.tokenIndex == -1) {
        // we must have conjured up a new token during single token insertion
        // if it's not the current symbol
        _ctx.addErrorNode(createErrorNode(_ctx, t));
      }
    }
    return t;
  }

  /**
   * Match current input symbol as a wildcard. If the symbol type matches
   * (i.e. has a value greater than 0), {@link ANTLRErrorStrategy#reportMatch}
   * and {@link #consume} are called to complete the match process.
   *
   * <p>If the symbol type does not match,
   * {@link ANTLRErrorStrategy#recoverInline} is called on the current error
   * strategy to attempt recovery. If {@link #getBuildParseTree} is
   * {@code true} and the token index of the symbol returned by
   * {@link ANTLRErrorStrategy#recoverInline} is -1, the symbol is added to
   * the parse tree by calling {@link Parser#createErrorNode(ParserRuleContext, Token)}. then
   * {@link ParserRuleContext#addErrorNode(ErrorNode)}</p>
   *
   * @return the matched symbol
   * @throws RecognitionException if the current input symbol did not match
   * a wildcard and the error strategy could not recover from the mismatched
   * symbol
   */
  Token matchWildcard() {
    Token t = getCurrentToken();
    if (t.type > 0) {
      _errHandler.reportMatch(this);
      consume();
    } else {
      t = _errHandler.recoverInline(this);
      if (_buildParseTrees && t.tokenIndex == -1) {
        // we must have conjured up a new token during single token insertion
        // if it's not the current symbol
        _ctx.addErrorNode(createErrorNode(_ctx, t));
      }
    }

    return t;
  }

  /**
   * Track the {@link ParserRuleContext} objects during the parse and hook
   * them up using the {@link ParserRuleContext#children} list so that it
   * forms a parse tree. The {@link ParserRuleContext} returned from the start
   * rule represents the root of the parse tree.
   *
   * <p>Note that if we are not building parse trees, rule contexts only point
   * upwards. When a rule exits, it returns the context but that gets garbage
   * collected if nobody holds a reference. It points upwards but nobody
   * points at it.</p>
   *
   * <p>When we build parse trees, we are adding all of these contexts to
   * {@link ParserRuleContext#children} list. Contexts are then not candidates
   * for garbage collection.</p>
   */
  void setBuildParseTree(bool buildParseTrees) {
    this._buildParseTrees = buildParseTrees;
  }

  /**
   * Gets whether or not a complete parse tree will be constructed while
   * parsing. This property is {@code true} for a newly constructed parser.
   *
   * @return {@code true} if a complete parse tree will be constructed while
   * parsing, otherwise {@code false}
   */
  bool getBuildParseTree() {
    return _buildParseTrees;
  }

  /**
   * Trim the internal lists of the parse tree during parsing to conserve memory.
   * This property is set to {@code false} by default for a newly constructed parser.
   *
   * @param trimParseTrees {@code true} to trim the capacity of the {@link ParserRuleContext#children}
   * list to its size after a rule is parsed.
   */
  void setTrimParseTree(bool trimParseTrees) {
    if (trimParseTrees) {
      if (getTrimParseTree()) return;
      addParseListener(TrimToSizeListener.INSTANCE);
    } else {
      removeParseListener(TrimToSizeListener.INSTANCE);
    }
  }

  /**
   * @return {@code true} if the {@link ParserRuleContext#children} list is trimmed
   * using the default {@link Parser.TrimToSizeListener} during the parse process.
   */
  bool getTrimParseTree() {
    return getParseListeners().contains(TrimToSizeListener.INSTANCE);
  }

  List<ParseTreeListener> getParseListeners() {
    List<ParseTreeListener> listeners = _parseListeners;
    if (listeners == null) {
      return [];
    }

    return listeners;
  }

  /**
   * Registers {@code listener} to receive events during the parsing process.
   *
   * <p>To support output-preserving grammar transformations (including but not
   * limited to left-recursion removal, automated left-factoring, and
   * optimized code generation), calls to listener methods during the parse
   * may differ substantially from calls made by
   * {@link ParseTreeWalker#DEFAULT} used after the parse is complete. In
   * particular, rule entry and exit events may occur in a different order
   * during the parse than after the parser. In addition, calls to certain
   * rule entry methods may be omitted.</p>
   *
   * <p>With the following specific exceptions, calls to listener events are
   * <em>deterministic</em>, i.e. for identical input the calls to listener
   * methods will be the same.</p>
   *
   * <ul>
   * <li>Alterations to the grammar used to generate code may change the
   * behavior of the listener calls.</li>
   * <li>Alterations to the command line options passed to ANTLR 4 when
   * generating the parser may change the behavior of the listener calls.</li>
   * <li>Changing the version of the ANTLR Tool used to generate the parser
   * may change the behavior of the listener calls.</li>
   * </ul>
   *
   * @param listener the listener to add
   *
   * @throws NullPointerException if {@code} listener is {@code null}
   */
  void addParseListener(ParseTreeListener listener) {
    if (listener == null) {
      throw new ArgumentError.notNull("listener");
    }

    if (_parseListeners == null) {
      _parseListeners = [];
    }

    this._parseListeners.add(listener);
  }

  /**
   * Remove {@code listener} from the list of parse listeners.
   *
   * <p>If {@code listener} is {@code null} or has not been added as a parse
   * listener, this method does nothing.</p>
   *
   * @see #addParseListener
   *
   * @param listener the listener to remove
   */
  void removeParseListener(ParseTreeListener listener) {
    if (_parseListeners != null) {
      if (_parseListeners.remove(listener)) {
        if (_parseListeners.isEmpty) {
          _parseListeners = null;
        }
      }
    }
  }

  /**
   * Remove all parse listeners.
   *
   * @see #addParseListener
   */
  void removeParseListeners() {
    _parseListeners = null;
  }

  /**
   * Notify any parse listeners of an enter rule event.
   *
   * @see #addParseListener
   */
  void triggerEnterRuleEvent() {
    for (ParseTreeListener listener in _parseListeners) {
      listener.enterEveryRule(_ctx);
      _ctx.enterRule(listener);
    }
  }

  /**
   * Notify any parse listeners of an exit rule event.
   *
   * @see #addParseListener
   */
  void triggerExitRuleEvent() {
    // reverse order walk of listeners
    for (int i = _parseListeners.length - 1; i >= 0; i--) {
      ParseTreeListener listener = _parseListeners[i];
      _ctx.exitRule(listener);
      listener.exitEveryRule(_ctx);
    }
  }

  /**
   * Gets the number of syntax errors reported during parsing. This value is
   * incremented each time {@link #notifyErrorListeners} is called.
   *
   * @see #notifyErrorListeners
   */
  int getNumberOfSyntaxErrors() {
    return _syntaxErrors;
  }

  TokenFactory getTokenFactory() {
    return _input.getTokenSource().getTokenFactory();
  }

  /** Tell our token source and error strategy about a new way to create tokens. */

  void setTokenFactory(TokenFactory factory) {
    _input.getTokenSource().setTokenFactory(factory);
  }

  /**
   * The ATN with bypass alternatives is expensive to create so we create it
   * lazily.
   *
   * @throws UnsupportedOperationException if the current parser does not
   * implement the {@link #getSerializedATN()} method.
   */
  ATN getATNWithBypassAlts() {
    String serializedAtn = getSerializedATN();
    if (serializedAtn == null) {
      throw new UnsupportedError(
          "The current parser does not support an ATN with bypass alternatives.");
    }

    ATN result = bypassAltsAtnCache[serializedAtn];
    if (result == null) {
      ATNDeserializationOptions deserializationOptions =
          new ATNDeserializationOptions();
      deserializationOptions.setGenerateRuleBypassTransitions(true);
      result = new ATNDeserializer(deserializationOptions)
          .deserialize(serializedAtn.codeUnits);
      bypassAltsAtnCache[serializedAtn] = result;
    }

    return result;
  }

  /**
   * The preferred method of getting a tree pattern. For example, here's a
   * sample use:
   *
   * <pre>
   * ParseTree t = parser.expr();
   * ParseTreePattern p = parser.compileParseTreePattern("&lt;ID&gt;+0", MyParser.RULE_expr);
   * ParseTreeMatch m = p.match(t);
   * String id = m.get("ID");
   * </pre>
   */
  ParseTreePattern compileParseTreePattern(String pattern, int patternRuleIndex,
      [Lexer lexer]) {
    if (lexer == null) {
      TokenSource tokenSource = getTokenStream()?.getTokenSource();
      if (tokenSource == null || !(tokenSource is Lexer)) {
        throw new UnsupportedError("Parser can't discover a lexer to use");
      }
      lexer = tokenSource;
    }

    ParseTreePatternMatcher m = new ParseTreePatternMatcher(lexer, this);
    return m.compile(pattern, patternRuleIndex);
  }

  ErrorStrategy getErrorHandler() {
    return _errHandler;
  }

  void setErrorHandler(ErrorStrategy handler) {
    this._errHandler = handler;
  }

  TokenStream get inputStream {
    return getTokenStream();
  }

  void setInputStream(IntStream input) {
    setTokenStream(input);
  }

  TokenStream getTokenStream() {
    return _input;
  }

  /** Set the token stream and reset the parser. */
  void setTokenStream(TokenStream input) {
    this._input = null;
    reset();
    this._input = input;
  }

  /** Match needs to return the current input symbol, which gets put
   *  into the label for the associated token ref; e.g., x=ID.
   */

  Token getCurrentToken() {
    return _input.LT(1);
  }

  void notifyErrorListeners(String msg,
      [Token offendingToken = null, RecognitionException e = null]) {
    offendingToken = offendingToken ?? getCurrentToken();
    _syntaxErrors++;
    int line = -1;
    int charPositionInLine = -1;
    line = offendingToken.line;
    charPositionInLine = offendingToken.charPositionInLine;

    ErrorListener listener = getErrorListenerDispatch();
    listener.syntaxError(
        this, offendingToken, line, charPositionInLine, msg, e);
  }

  /**
   * Consume and return the {@linkplain #getCurrentToken current symbol}.
   *
   * <p>E.g., given the following input with {@code A} being the current
   * lookahead symbol, this function moves the cursor to {@code B} and returns
   * {@code A}.</p>
   *
   * <pre>
   *  A B
   *  ^
   * </pre>
   *
   * If the parser is not in error recovery mode, the consumed symbol is added
   * to the parse tree using {@link ParserRuleContext#addChild}, and
   * {@link ParseTreeListener#visitTerminal} is called on any parse listeners.
   * If the parser <em>is</em> in error recovery mode, the consumed symbol is
   * added to the parse tree using {@link #createErrorNode(ParserRuleContext, Token)} then
   * {@link ParserRuleContext#addErrorNode(ErrorNode)} and
   * {@link ParseTreeListener#visitErrorNode} is called on any parse
   * listeners.
   */
  Token consume() {
    Token o = getCurrentToken();
    if (o.type != IntStream.EOF) {
      inputStream.consume();
    }
    bool hasListener = _parseListeners != null && !_parseListeners.isEmpty;
    if (_buildParseTrees || hasListener) {
      if (_errHandler.inErrorRecoveryMode(this)) {
        ErrorNode node = _ctx.addErrorNode(createErrorNode(_ctx, o));
        if (_parseListeners != null) {
          for (ParseTreeListener listener in _parseListeners) {
            listener.visitErrorNode(node);
          }
        }
      } else {
        TerminalNode node = _ctx.addChild(createTerminalNode(_ctx, o));
        if (_parseListeners != null) {
          for (ParseTreeListener listener in _parseListeners) {
            listener.visitTerminal(node);
          }
        }
      }
    }
    return o;
  }

  /** How to create a token leaf node associated with a parent.
   *  Typically, the terminal node to create is not a function of the parent.
   *
   * @since 4.7
   */
  TerminalNode createTerminalNode(ParserRuleContext parent, Token t) {
    return new TerminalNodeImpl(t);
  }

  /** How to create an error node, given a token, associated with a parent.
   *  Typically, the error node to create is not a function of the parent.
   *
   * @since 4.7
   */
  ErrorNode createErrorNode(ParserRuleContext parent, Token t) {
    return new ErrorNodeImpl(t);
  }

  void addContextToParseTree() {
    ParserRuleContext parent = _ctx.getParent();
    // add current context to parent if we have a parent
    if (parent != null) {
      parent.addAnyChild(_ctx);
    }
  }

  /**
   * Always called by generated parsers upon entry to a rule. Access field
   * {@link #_ctx} get the current context.
   */
  void enterRule(ParserRuleContext localctx, int state, int ruleIndex) {
    this.state = state;
    _ctx = localctx;
    _ctx.start = _input.LT(1);
    if (_buildParseTrees) addContextToParseTree();
    if (_parseListeners != null) triggerEnterRuleEvent();
  }

  void exitRule() {
    if (matchedEOF) {
      // if we have matched EOF, it cannot consume past EOF so we use LT(1) here
      _ctx.stop = _input.LT(1); // LT(1) will be end of file
    } else {
      _ctx.stop = _input.LT(-1); // stop node is what we just matched
    }
    // trigger event on _ctx, before it reverts to parent
    if (_parseListeners != null) triggerExitRuleEvent();
    state = _ctx.invokingState;
    _ctx = _ctx.getParent();
  }

  void enterOuterAlt(ParserRuleContext localctx, int altNum) {
    localctx.setAltNumber(altNum);
    // if we have new localctx, make sure we replace existing ctx
    // that is previous child of parse tree
    if (_buildParseTrees && _ctx != localctx) {
      ParserRuleContext parent = _ctx.getParent();
      if (parent != null) {
        parent.removeLastChild();
        parent.addAnyChild(localctx);
      }
    }
    _ctx = localctx;
  }

  /**
   * Get the precedence level for the top-most precedence rule.
   *
   * @return The precedence level for the top-most precedence rule, or -1 if
   * the parser context is not nested within a precedence rule.
   */
  int getPrecedence() {
    if (_precedenceStack.isEmpty) {
      return -1;
    }

    return _precedenceStack.last;
  }

  void enterRecursionRule(
      ParserRuleContext localctx, int state, int ruleIndex, int precedence) {
    this.state = state;
    _precedenceStack.add(precedence);
    _ctx = localctx;
    _ctx.start = _input.LT(1);
    if (_parseListeners != null) {
      triggerEnterRuleEvent(); // simulates rule entry for left-recursive rules
    }
  }

  /** Like {@link #enterRule} but for recursive rules.
   *  Make the current context the child of the incoming localctx.
   */
  void pushNewRecursionContext(
      ParserRuleContext localctx, int state, int ruleIndex) {
    ParserRuleContext previous = _ctx;
    previous.setParent(localctx);
    previous.invokingState = state;
    previous.stop = _input.LT(-1);

    _ctx = localctx;
    _ctx.start = previous.start;
    if (_buildParseTrees) {
      _ctx.addAnyChild(previous);
    }

    if (_parseListeners != null) {
      triggerEnterRuleEvent(); // simulates rule entry for left-recursive rules
    }
  }

  void unrollRecursionContexts(ParserRuleContext _parentctx) {
    _precedenceStack.removeLast();
    _ctx.stop = _input.LT(-1);
    ParserRuleContext retctx = _ctx; // save current ctx (return value)

    // unroll so _ctx is as it was before call to recursive method
    if (_parseListeners != null) {
      while (_ctx != _parentctx) {
        triggerExitRuleEvent();
        _ctx = _ctx.getParent();
      }
    } else {
      _ctx = _parentctx;
    }

    // hook into tree
    retctx.setParent(_parentctx);

    if (_buildParseTrees && _parentctx != null) {
      // add return ctx into invoking rule's tree
      _parentctx.addAnyChild(retctx);
    }
  }

  ParserRuleContext getInvokingContext(int ruleIndex) {
    ParserRuleContext p = _ctx;
    while (p != null) {
      if (p.ruleIndex == ruleIndex) return p;
      p = p.getParent();
    }
    return null;
  }

  ParserRuleContext getContext() {
    return _ctx;
  }

  void setContext(ParserRuleContext ctx) {
    _ctx = ctx;
  }

  bool precpred(RuleContext localctx, int precedence) {
    return precedence >= _precedenceStack.last;
  }

  bool inContext(String context) {
    // TODO: useful in parser?
    return false;
  }

  /**
   * Checks whether or not {@code symbol} can follow the current state in the
   * ATN. The behavior of this method is equivalent to the following, but is
   * implemented such that the complete context-sensitive follow set does not
   * need to be explicitly constructed.
   *
   * <pre>
   * return expectedTokens.contains(symbol);
   * </pre>
   *
   * @param symbol the symbol type to check
   * @return {@code true} if {@code symbol} can follow the current state in
   * the ATN, otherwise {@code false}.
   */
  bool isExpectedToken(int symbol) {
//   		return getInterpreter().atn.nextTokens(_ctx);
    ATN atn = getInterpreter().atn;
    ParserRuleContext ctx = _ctx;
    ATNState s = atn.states[state];
    IntervalSet following = atn.nextTokens(s);
    if (following.contains(symbol)) {
      return true;
    }
//        log("following "+s+"="+following);
    if (!following.contains(Token.EPSILON)) return false;

    while (ctx != null &&
        ctx.invokingState >= 0 &&
        following.contains(Token.EPSILON)) {
      ATNState invokingState = atn.states[ctx.invokingState];
      RuleTransition rt = invokingState.transition(0);
      following = atn.nextTokens(rt.followState);
      if (following.contains(symbol)) {
        return true;
      }

      ctx = ctx.getParent();
    }

    if (following.contains(Token.EPSILON) && symbol == Token.EOF) {
      return true;
    }

    return false;
  }

  bool isMatchedEOF() {
    return matchedEOF;
  }

  /**
   * Computes the set of input symbols which could follow the current parser
   * state and context, as given by {@link #getState} and {@link #getContext},
   * respectively.
   *
   * @see ATN#getExpectedTokens(int, RuleContext)
   */
  IntervalSet get expectedTokens {
    return getATN().getExpectedTokens(state, getContext());
  }

  IntervalSet getExpectedTokensWithinCurrentRule() {
    ATN atn = getInterpreter().atn;
    ATNState s = atn.states[state];
    return atn.nextTokens(s);
  }

  /** Get a rule's index (i.e., {@code RULE_ruleName} field) or -1 if not found. */
  int getRuleIndex(String ruleName) {
    int ruleIndex = getRuleIndexMap()[ruleName];
    if (ruleIndex != null) return ruleIndex;
    return -1;
  }

  ParserRuleContext getRuleContext() {
    return _ctx;
  }

  /** Return List&lt;String&gt; of the rule names in your parser instance
   *  leading up to a call to the current rule.  You could override if
   *  you want more details such as the file/line info of where
   *  in the ATN a rule is invoked.
   *
   *  This is very useful for error messages.
   */
  List<String> getRuleInvocationStack([RuleContext p]) {
    p = p ?? _ctx;
    final ruleNames = getRuleNames();
    List<String> stack = [];
    while (p != null) {
      // compute what follows who invoked us
      int ruleIndex = p.ruleIndex;
      if (ruleIndex < 0)
        stack.add("n/a");
      else
        stack.add(ruleNames[ruleIndex]);
      p = p.getParent();
    }
    return stack;
  }

  /** For debugging and other purposes. */
  List<String> getDFAStrings() {
    List<String> s = [];
    for (int d = 0; d < interp.decisionToDFA.length; d++) {
      DFA dfa = interp.decisionToDFA[d];
      s.add(dfa.toString(getVocabulary()));
    }
    return s;
  }

  /** For debugging and other purposes. */
  void dumpDFA() {
    bool seenOne = false;
    for (int d = 0; d < interp.decisionToDFA.length; d++) {
      DFA dfa = interp.decisionToDFA[d];
      if (!dfa.states.isEmpty) {
        if (seenOne) log("");
        log("Decision ${dfa.decision}:");
        log(dfa.toString(getVocabulary()));
        seenOne = true;
      }
    }
  }

  String getSourceName() {
    return _input.sourceName;
  }

  ParseInfo getParseInfo() {
    ParserATNSimulator interp = getInterpreter();
    if (interp is ProfilingATNSimulator) {
      return new ParseInfo(interp);
    }
    return null;
  }

  /**
   * @since 4.3
   */
  void setProfile(bool profile) {
    ParserATNSimulator interp = getInterpreter();
    PredictionMode saveMode = interp.getPredictionMode();
    if (profile) {
      if (!(interp is ProfilingATNSimulator)) {
        setInterpreter(new ProfilingATNSimulator(this));
      }
    } else if (interp is ProfilingATNSimulator) {
      ParserATNSimulator sim = new ParserATNSimulator(
          this, getATN(), interp.decisionToDFA, interp.getSharedContextCache());
      setInterpreter(sim);
    }
    getInterpreter().setPredictionMode(saveMode);
  }

  /** During a parse is sometimes useful to listen in on the rule entry and exit
   *  events as well as token matches. This is for quick and dirty debugging.
   */
  void setTrace(bool trace) {
    if (!trace) {
      removeParseListener(_tracer);
      _tracer = null;
    } else {
      if (_tracer != null)
        removeParseListener(_tracer);
      else
        _tracer = new TraceListener(this);
      addParseListener(_tracer);
    }
  }

  /**
   * Gets whether a {@link TraceListener} is registered as a parse listener
   * for the parser.
   *
   * @see #setTrace(bool)
   */
  bool isTrace() {
    return _tracer != null;
  }
}
