/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */
import 'dart:developer';

import 'Token.dart';
import 'CharStream.dart';
import 'CommonTokenFactory.dart';
import 'IntStream.dart';
import 'IntervalSet.dart';
import 'Recognizer.dart';
import 'TokenSource.dart';
import 'atn/LexerATNSimulator.dart';
import 'error/ErrorListener.dart';
import 'error/Errors.dart';
import 'misc/Pair.dart';

abstract class Lexer extends Recognizer<LexerATNSimulator>
    implements TokenSource {
  static final DEFAULT_MODE = 0;
  static final MORE = -2;
  static final SKIP = -3;

  static final DEFAULT_TOKEN_CHANNEL = Token.DEFAULT_CHANNEL;
  static final HIDDEN = Token.HIDDEN_CHANNEL;
  static final MIN_CHAR_VALUE = 0x0000;
  static final MAX_CHAR_VALUE = 0x10FFFF;

  CharStream _input;

  Pair<TokenSource, CharStream> _tokenFactorySourcePair;
  TokenFactory _factory = CommonTokenFactory.DEFAULT;

  // The goal of all lexer rules/methods is to create a token object.
  // this is an instance variable as multiple rules may collaborate to
  // create a single token. nextToken will return this object after
  // matching lexer rule(s). If you subclass to allow multiple token
  // emissions, then set this to the last token to be matched or
  // something nonnull so that the auto token emit mechanism will not
  // emit another token.
  Token _token = null;

  // What character index in the stream did the current token start at?
  // Needed, for example, to get the text for current token. Set at
  // the start of nextToken.
  int tokenStartCharIndex = -1;

  // The line on which the first character of the token resides///
  int _tokenStartLine = -1;

  // The character position of first character within the line///
  int _tokenStartCharPositionInLine = -1;

  // Once we see EOF on char stream, next token will be EOF.
  // If you have DONE : EOF ; then you see DONE EOF.
  bool _hitEOF = false;

  // The channel number for the current token///
  int _channel = Token.DEFAULT_CHANNEL;

  // The token type for the current token///
  int _type = Token.INVALID_TYPE;

  List<int> _modeStack = [];
  int _mode = Lexer.DEFAULT_MODE;

  /// You can set the text for the current token to override what is in
  /// the input char buffer. Use setText() or can set this instance var.
  String _text = null;

  Lexer(CharStream input) {
    this._input = input;
    this._tokenFactorySourcePair = Pair(this, input);
  }

  reset() {
    // wack Lexer state variables
    if (_input != null) {
      _input.seek(0); // rewind the input
    }
    _token = null;
    _type = Token.INVALID_TYPE;
    _channel = Token.DEFAULT_CHANNEL;
    tokenStartCharIndex = -1;
    _tokenStartCharPositionInLine = -1;
    _tokenStartLine = -1;
    _text = null;

    _hitEOF = false;
    _mode = Lexer.DEFAULT_MODE;
    _modeStack.clear();

    getInterpreter().reset();
  }

  /// Return a token from this source; i.e., match a token on the char stream.
  Token nextToken() {
    if (_input == null) {
      throw new StateError("nextToken requires a non-null input stream.");
    }

    // Mark start location in char stream so unbuffered streams are
    // guaranteed at least have text of current token
    int tokenStartMarker = _input.mark();
    try {
      outer:
      while (true) {
        if (_hitEOF) {
          emitEOF();
          return _token;
        }

        _token = null;
        _channel = Token.DEFAULT_CHANNEL;
        tokenStartCharIndex = _input.index;
        _tokenStartCharPositionInLine =
            getInterpreter().getCharPositionInLine();
        _tokenStartLine = getInterpreter().getLine();
        _text = null;
        do {
          _type = Token.INVALID_TYPE;
//				System.out.println("nextToken line "+tokenStartLine+" at "+((char)input.LA(1))+
//								   " in mode "+mode+
//								   " at index "+input.index());
          int ttype;
          try {
            ttype = getInterpreter().match(_input, _mode);
          } on LexerNoViableAltException catch (e) {
            notifyListeners(e); // report error
            recover(e);
            ttype = SKIP;
          }
          if (_input.LA(1) == IntStream.EOF) {
            _hitEOF = true;
          }
          if (_type == Token.INVALID_TYPE) _type = ttype;
          if (_type == SKIP) {
            continue outer;
          }
        } while (_type == MORE);
        if (_token == null) emit();
        return _token;
      }
    } finally {
      // make sure we release marker after match or
      // unbuffered char stream will keep buffering
      _input.release(tokenStartMarker);
    }
  }

  /// Instruct the lexer to skip creating a token for current lexer rule
  /// and look for another token. nextToken() knows to keep looking when
  /// a lexer rule finishes with token set to SKIP_TOKEN. Recall that
  /// if token==null at end of any token rule, it creates one for you
  /// and emits it.
  skip() {
    this._type = Lexer.SKIP;
  }

  more() {
    this._type = Lexer.MORE;
  }

  mode(int m) {
    this._mode = m;
  }

  pushMode(int m) {
    if (LexerATNSimulator.debug) {
      log("pushMode $m");
    }
    _modeStack.add(_mode);
    mode(m);
  }

  int popMode() {
    if (_modeStack.isEmpty) throw new StateError("");
    if (LexerATNSimulator.debug) log("popMode back to ${_modeStack.last}");
    mode(_modeStack.removeLast());
    return _mode;
  }

  void setTokenFactory(TokenFactory factory) {
    this._factory = factory;
  }

  TokenFactory getTokenFactory() {
    return _factory;
  }

  /** Set the char stream and reset the lexer */

  void setInputStream(IntStream input) {
    this._input = null;
    this._tokenFactorySourcePair =
        new Pair<TokenSource, CharStream>(this, _input);
    reset();
    this._input = input;
    this._tokenFactorySourcePair =
        new Pair<TokenSource, CharStream>(this, _input);
  }

  String get sourceName {
    return _input.sourceName;
  }

  CharStream getInputStream() {
    return _input;
  }

  /** By default does not support multiple emits per nextToken invocation
   *  for efficiency reasons.  Subclass and override this method, nextToken,
   *  and getToken (to push tokens into a list and pull from that list
   *  rather than a single variable as this implementation does).
   */
  void emitToken(Token token) {
    //System.err.println("emit "+token);
    this._token = token;
  }

  /** The standard method called to automatically emit a token at the
   *  outermost lexical rule.  The token object should point into the
   *  char buffer start..stop.  If there is a text override in 'text',
   *  use that to set the token's text.  Override this method to emit
   *  custom Token objects or provide a new factory.
   */
  Token emit() {
    Token t = _factory.create(
        _type,
        _text,
        _tokenFactorySourcePair,
        _channel,
        tokenStartCharIndex,
        getCharIndex() - 1,
        _tokenStartLine,
        _tokenStartCharPositionInLine);
    emitToken(t);
    return t;
  }

  Token emitEOF() {
    int cpos = getCharPositionInLine();
    int line = getLine();
    Token eof = _factory.create(Token.EOF, null, _tokenFactorySourcePair,
        Token.DEFAULT_CHANNEL, _input.index, _input.index - 1, line, cpos);
    emitToken(eof);
    return eof;
  }

  int getLine() {
    return getInterpreter().getLine();
  }

  int getCharPositionInLine() {
    return getInterpreter().getCharPositionInLine();
  }

  void setLine(int line) {
    getInterpreter().setLine(line);
  }

  void setCharPositionInLine(int charPositionInLine) {
    getInterpreter().setCharPositionInLine(charPositionInLine);
  }

  /** What is the index of the current character of lookahead? */
  int getCharIndex() {
    return _input.index;
  }

  /** Return the text matched so far for the current token or any
   *  text override.
   */
  String getText() {
    if (_text != null) {
      return _text;
    }
    return getInterpreter().getText(_input);
  }

  /** Set the complete text of this token; it wipes any previous
   *  changes to the text.
   */
  void setText(String text) {
    this._text = text;
  }

  /** Override if emitting multiple tokens. */
  Token getToken() {
    return _token;
  }

  void setToken(Token _token) {
    this._token = _token;
  }

  void setType(int ttype) {
    _type = ttype;
  }

  int getType() {
    return _type;
  }

  void setChannel(int channel) {
    _channel = channel;
  }

  int getChannel() {
    return _channel;
  }

  List<String> getChannelNames() {
    return null;
  }

  List<String> getModeNames() {
    return null;
  }

  /** Return a list of all Token objects in input char stream.
   *  Forces load of all tokens. Does not include EOF token.
   */
  List<Token> getAllTokens() {
    List<Token> tokens = [];
    Token t = nextToken();
    while (t.type != Token.EOF) {
      tokens.add(t);
      t = nextToken();
    }
    return tokens;
  }

  void notifyListeners(LexerNoViableAltException e) {
    String text =
        _input.getText(Interval.of(tokenStartCharIndex, _input.index));
    String msg = "token recognition error at: '" + getErrorDisplay(text) + "'";

    ErrorListener listener = getErrorListenerDispatch();
    listener.syntaxError(
        this, null, _tokenStartLine, _tokenStartCharPositionInLine, msg, e);
  }

  String getErrorDisplay(String s) {
    StringBuffer buf = new StringBuffer();
    for (int c in s.codeUnits) {
      buf.write(getErrorDisplayForChar(c));
    }
    return buf.toString();
  }

  String getCharErrorDisplay(int c) {
    String s = getErrorDisplay(String.fromCharCode(c));
    return "'$s'";
  }

  /** Lexers can normally match any char in it's vocabulary after matching
   *  a token, so do the easy thing and just kill a character and hope
   *  it all works out.  You can instead use the rule invocation stack
   *  to do sophisticated error recovery if you are in a fragment rule.
   */
  void recover(RecognitionException re) {
    if (re is LexerNoViableAltException) {
      if (_input.LA(1) != IntStream.EOF) {
        // skip a char and try again
        getInterpreter().consume(_input);
      }
    } else {
      //System.out.println("consuming char "+(char)input.LA(1)+" during recovery");
      //re.printStackTrace();
      // TODO: Do we lose character or line position information?
      _input.consume();
    }
  }

  getErrorDisplayForChar(c) {
    if (c.charCodeAt(0) == Token.EOF) {
      return "<EOF>";
    } else if (c == '\n') {
      return "\\n";
    } else if (c == '\t') {
      return "\\t";
    } else if (c == '\r') {
      return "\\r";
    } else {
      return c;
    }
  }
}
