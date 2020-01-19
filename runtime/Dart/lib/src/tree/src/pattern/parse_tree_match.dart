import '../../../error/error.dart';
import '../../../input_stream.dart';
import '../../../lexer.dart';
import '../../../misc/multi_map.dart';
import '../../../parser.dart';
import '../../../parser_interpreter.dart';
import '../../../parser_rule_context.dart';
import '../../../token.dart';
import '../../../token_source.dart';
import '../../../token_stream.dart';
import '../../../util/utils.dart';
import '../tree.dart';
import 'chunk.dart';

/**
 * Represents the result of matching a {@link ParseTree} against a tree pattern.
 */
class ParseTreeMatch {
  /**
   * Get the parse tree we are trying to match to a pattern.
   *
   * @return The {@link ParseTree} we are trying to match to a pattern.
   */
  final ParseTree tree;

  /**
   * Get the tree pattern we are matching against.
   *
   * @return The tree pattern we are matching against.
   */
  final ParseTreePattern pattern;


  /**
   * Return a mapping from label &rarr; [list of nodes].
   *
   * <p>The map includes special entries corresponding to the names of rules and
   * tokens referenced in tags in the original pattern. For additional
   * information, see the description of {@link #getAll(String)}.</p>
   *
   * @return A mapping from labels to parse tree nodes. If the parse tree
   * pattern did not contain any rule or token tags, this map will be empty.
   */
  final MultiMap<String, ParseTree> labels;

  /**
   * Get the node at which we first detected a mismatch.
   *
   * @return the node at which we first detected a mismatch, or {@code null}
   * if the match was successful.
   */
  final ParseTree mismatchedNode;

  /**
   * Constructs a new instance of {@link ParseTreeMatch} from the specified
   * parse tree and pattern.
   *
   * @param tree The parse tree to match against the pattern.
   * @param pattern The parse tree pattern.
   * @param labels A mapping from label names to collections of
   * {@link ParseTree} objects located by the tree pattern matching process.
   * @param mismatchedNode The first node which failed to match the tree
   * pattern during the matching process.
   *
   * @exception ArgumentError.notNull) if {@code tree} is {@code null}
   * @exception ArgumentError.notNull) if {@code pattern} is {@code null}
   * @exception ArgumentError.notNull) if {@code labels} is {@code null}
   */
  ParseTreeMatch(this.tree, this.pattern, this.labels, this.mismatchedNode) {
    if (tree == null) {
      throw new ArgumentError.notNull("tree");
    }

    if (pattern == null) {
      throw new ArgumentError.notNull("pattern");
    }

    if (labels == null) {
      throw new ArgumentError.notNull("labels");
    }
  }

  /**
   * Get the last node associated with a specific {@code label}.
   *
   * <p>For example, for pattern {@code <id:ID>}, {@code get("id")} returns the
   * node matched for that {@code ID}. If more than one node
   * matched the specified label, only the last is returned. If there is
   * no node associated with the label, this returns {@code null}.</p>
   *
   * <p>Pattern tags like {@code <ID>} and {@code <expr>} without labels are
   * considered to be labeled with {@code ID} and {@code expr}, respectively.</p>
   *
   * @param label The label to check.
   *
   * @return The last {@link ParseTree} to match a tag with the specified
   * label, or {@code null} if no parse tree matched a tag with the label.
   */

  ParseTree get(String label) {
    List<ParseTree> parseTrees = labels[label];
    if (parseTrees == null || parseTrees.length == 0) {
      return null;
    }

    return parseTrees[parseTrees.length - 1]; // return last if multiple
  }

  /**
   * Return all nodes matching a rule or token tag with the specified label.
   *
   * <p>If the {@code label} is the name of a parser rule or token in the
   * grammar, the resulting list will contain both the parse trees matching
   * rule or tags explicitly labeled with the label and the complete set of
   * parse trees matching the labeled and unlabeled tags in the pattern for
   * the parser rule or token. For example, if {@code label} is {@code "foo"},
   * the result will contain <em>all</em> of the following.</p>
   *
   * <ul>
   * <li>Parse tree nodes matching tags of the form {@code <foo:anyRuleName>} and
   * {@code <foo:AnyTokenName>}.</li>
   * <li>Parse tree nodes matching tags of the form {@code <anyLabel:foo>}.</li>
   * <li>Parse tree nodes matching tags of the form {@code <foo>}.</li>
   * </ul>
   *
   * @param label The label.
   *
   * @return A collection of all {@link ParseTree} nodes matching tags with
   * the specified {@code label}. If no nodes matched the label, an empty list
   * is returned.
   */

  List<ParseTree> getAll(String label) {
    List<ParseTree> nodes = labels[label];
    if (nodes == null) {
      return [];
    }

    return nodes;
  }

  /**
   * Gets a value indicating whether the match operation succeeded.
   *
   * @return {@code true} if the match operation succeeded; otherwise,
   * {@code false}.
   */
  bool get succeeded => mismatchedNode == null;

  /**
   * {@inheritDoc}
   */
  String toString() {
    return "Match ${succeeded ? "succeeded" : "failed"}; found ${labels.length} labels";
  }
}

/**
 * A pattern like {@code <ID> = <expr>;} converted to a {@link ParseTree} by
 * {@link ParseTreePatternMatcher#compile(String, int)}.
 */
class ParseTreePattern {
  /**
   * Get the parser rule which serves as the outermost rule for the tree
   * pattern.
   *
   * @return The parser rule which serves as the outermost rule for the tree
   * pattern.
   */
  final int patternRuleIndex;

  /**
   * Get the tree pattern in concrete syntax form.
   *
   * @return The tree pattern in concrete syntax form.
   */
  final String pattern;


  /**
   * Get the tree pattern as a {@link ParseTree}. The rule and token tags from
   * the pattern are present in the parse tree as terminal nodes with a symbol
   * of type {@link RuleTagToken} or {@link TokenTagToken}.
   *
   * @return The tree pattern as a {@link ParseTree}.
   */
  final ParseTree patternTree;

  /**
   * Get the {@link ParseTreePatternMatcher} which created this tree pattern.
   *
   * @return The {@link ParseTreePatternMatcher} which created this tree
   * pattern.
   */
  final ParseTreePatternMatcher matcher;

  /**
   * Construct a new instance of the {@link ParseTreePattern} class.
   *
   * @param matcher The {@link ParseTreePatternMatcher} which created this
   * tree pattern.
   * @param pattern The tree pattern in concrete syntax form.
   * @param patternRuleIndex The parser rule which serves as the root of the
   * tree pattern.
   * @param patternTree The tree pattern in {@link ParseTree} form.
   */
  ParseTreePattern(
      this.matcher, this.pattern, this.patternRuleIndex, this.patternTree);

  /**
   * Match a specific parse tree against this tree pattern.
   *
   * @param tree The parse tree to match against this tree pattern.
   * @return A {@link ParseTreeMatch} object describing the result of the
   * match operation. The {@link ParseTreeMatch#succeeded()} method can be
   * used to determine whether or not the match was successful.
   */

  ParseTreeMatch match(ParseTree tree) {
    return matcher.match(tree, pattern: this);
  }

  /**
   * Determine whether or not a parse tree matches this tree pattern.
   *
   * @param tree The parse tree to match against this tree pattern.
   * @return {@code true} if {@code tree} is a match for the current tree
   * pattern; otherwise, {@code false}.
   */
  bool matches(ParseTree tree) {
    return matcher.match(tree, pattern: this).succeeded;
  }
}

/**
 * A tree pattern matching mechanism for ANTLR {@link ParseTree}s.
 *
 * <p>Patterns are strings of source input text with special tags representing
 * token or rule references such as:</p>
 *
 * <p>{@code <ID> = <expr>;}</p>
 *
 * <p>Given a pattern start rule such as {@code statement}, this object constructs
 * a {@link ParseTree} with placeholders for the {@code ID} and {@code expr}
 * subtree. Then the {@link #match} routines can compare an actual
 * {@link ParseTree} from a parse with this pattern. Tag {@code <ID>} matches
 * any {@code ID} token and tag {@code <expr>} references the result of the
 * {@code expr} rule (generally an instance of {@code ExprContext}.</p>
 *
 * <p>Pattern {@code x = 0;} is a similar pattern that matches the same pattern
 * except that it requires the identifier to be {@code x} and the expression to
 * be {@code 0}.</p>
 *
 * <p>The {@link #matches} routines return {@code true} or {@code false} based
 * upon a match for the tree rooted at the parameter sent in. The
 * {@link #match} routines return a {@link ParseTreeMatch} object that
 * contains the parse tree, the parse tree pattern, and a map from tag name to
 * matched nodes (more below). A subtree that fails to match, returns with
 * {@link ParseTreeMatch#mismatchedNode} set to the first tree node that did not
 * match.</p>
 *
 * <p>For efficiency, you can compile a tree pattern in string form to a
 * {@link ParseTreePattern} object.</p>
 *
 * <p>See {@code TestParseTreeMatcher} for lots of examples.
 * {@link ParseTreePattern} has two static helper methods:
 * {@link ParseTreePattern#findAll} and {@link ParseTreePattern#match} that
 * are easy to use but not super efficient because they create new
 * {@link ParseTreePatternMatcher} objects each time and have to compile the
 * pattern in string form before using it.</p>
 *
 * <p>The lexer and parser that you pass into the {@link ParseTreePatternMatcher}
 * constructor are used to parse the pattern in string form. The lexer converts
 * the {@code <ID> = <expr>;} into a sequence of four tokens (assuming lexer
 * throws out whitespace or puts it on a hidden channel). Be aware that the
 * input stream is reset for the lexer (but not the parser; a
 * {@link ParserInterpreter} is created to parse the input.). Any user-defined
 * fields you have put into the lexer might get changed when this mechanism asks
 * it to scan the pattern string.</p>
 *
 * <p>Normally a parser does not accept token {@code <expr>} as a valid
 * {@code expr} but, from the parser passed in, we create a special version of
 * the underlying grammar representation (an {@link ATN}) that allows imaginary
 * tokens representing rules ({@code <expr>}) to match entire rules. We call
 * these <em>bypass alternatives</em>.</p>
 *
 * <p>Delimiters are {@code <} and {@code >}, with {@code \} as the escape string
 * by default, but you can set them to whatever you want using
 * {@link #setDelimiters}. You must escape both start and stop strings
 * {@code \<} and {@code \>}.</p>
 */
class ParseTreePatternMatcher {
  /**
   * Used to convert the tree pattern string into a series of tokens. The
   * input stream is reset.
   */
  final Lexer lexer;

  /**
   * Used to collect to the grammar file name, token names, rule names for
   * used to parse the pattern into a parse tree.
   */
  final Parser parser;

  String start = "<";
  String stop = ">";
  String escape = "\\"; // e.g., \< and \> must escape BOTH!

  /**
   * Constructs a {@link ParseTreePatternMatcher} or from a {@link Lexer} and
   * {@link Parser} object. The lexer input stream is altered for tokenizing
   * the tree patterns. The parser is used as a convenient mechanism to get
   * the grammar name, plus token, rule names.
   */
  ParseTreePatternMatcher(this.lexer, this.parser);

  /**
   * Set the delimiters used for marking rule and token tags within concrete
   * syntax used by the tree pattern parser.
   *
   * @param start The start delimiter.
   * @param stop The stop delimiter.
   * @param escapeLeft The escape sequence to use for escaping a start or stop delimiter.
   *
   * @exception ArgumentError if {@code start} is {@code null} or empty.
   * @exception ArgumentError if {@code stop} is {@code null} or empty.
   */
  void setDelimiters(String start, String stop, String escapeLeft) {
    if (start == null || start.isEmpty) {
      throw new ArgumentError.value(start, "start", "cannot be null or empty");
    }

    if (stop == null || stop.isEmpty) {
      throw new ArgumentError.value(stop, "stop", "cannot be null or empty");
    }

    this.start = start;
    this.stop = stop;
    this.escape = escapeLeft;
  }

  /** Does {@code pattern} matched as rule patternRuleIndex match tree? Pass in a
   *  compiled pattern instead of a string representation of a tree pattern.
   */
  bool matches(ParseTree tree,
      {ParseTreePattern pattern, String patternStr, int patternRuleIndex}) {
    if (pattern == null) {
      pattern = compile(patternStr, patternRuleIndex);
    }

    MultiMap<String, ParseTree> labels = new MultiMap<String, ParseTree>();
    ParseTree mismatchedNode =
        matchImpl(tree, pattern.patternTree, labels);
    return mismatchedNode == null;
  }

  /**
   * Compare {@code pattern} matched against {@code tree} and return a
   * {@link ParseTreeMatch} object that contains the matched elements, or the
   * node at which the match failed. Pass in a compiled pattern instead of a
   * string representation of a tree pattern.
   */

  ParseTreeMatch match(ParseTree tree,
      {ParseTreePattern pattern, String patternStr, int patternRuleIndex}) {
    if (pattern == null) {
      pattern = compile(patternStr, patternRuleIndex);
    }

    MultiMap<String, ParseTree> labels = new MultiMap<String, ParseTree>();
    ParseTree mismatchedNode =
        matchImpl(tree, pattern.patternTree, labels);
    return new ParseTreeMatch(tree, pattern, labels, mismatchedNode);
  }

  /**
   * For repeated use of a tree pattern, compile it to a
   * {@link ParseTreePattern} using this method.
   */
  ParseTreePattern compile(String pattern, int patternRuleIndex) {
    List<Token> tokenList = tokenize(pattern);
    ListTokenSource tokenSrc = new ListTokenSource(tokenList);
    CommonTokenStream tokens = new CommonTokenStream(tokenSrc);

    ParserInterpreter parserInterp = new ParserInterpreter(
        parser.grammarFileName,
        parser.vocabulary,
        parser.ruleNames,
        parser.ATNWithBypassAlts,
        tokens);

    ParseTree tree = null;
    try {
      parserInterp.errorHandler = new BailErrorStrategy();
      tree = parserInterp.parse(patternRuleIndex);
//			System.out.println("pattern tree = "+tree.toStringTree(parserInterp));
    } on ParseCancellationException catch (e) {
      throw e;
    } on RecognitionException catch (re) {
      throw re;
    } catch (e) {
      throw new CannotInvokeStartRule(e);
    }

    // Make sure tree pattern compilation checks for a complete parse
    if (tokens.LA(1) != Token.EOF) {
      throw new StartRuleDoesNotConsumeFullPattern();
    }

    return new ParseTreePattern(this, pattern, patternRuleIndex, tree);
  }

  // ---- SUPPORT CODE ----

  /**
   * Recursively walk {@code tree} against {@code patternTree}, filling
   * {@code match.}{@link ParseTreeMatch#labels labels}.
   *
   * @return the first node encountered in {@code tree} which does not match
   * a corresponding node in {@code patternTree}, or {@code null} if the match
   * was successful. The specific node returned depends on the matching
   * algorithm used by the implementation, and may be overridden.
   */

  ParseTree matchImpl(ParseTree tree, ParseTree patternTree,
      MultiMap<String, ParseTree> labels) {
    if (tree == null) {
      throw new ArgumentError("tree cannot be null");
    }

    if (patternTree == null) {
      throw new ArgumentError("patternTree cannot be null");
    }

    // x and <ID>, x and y, or x and x; or could be mismatched types
    if (tree is TerminalNode && patternTree is TerminalNode) {
      TerminalNode t1 = tree;
      TerminalNode t2 = patternTree;
      ParseTree mismatchedNode = null;
      // both are tokens and they have same type
      if (t1.symbol.type == t2.symbol.type) {
        if (t2.symbol is TokenTagToken) {
          // x and <ID>
          TokenTagToken tokenTagToken = t2.symbol;
          // track label->list-of-nodes for both token name and label (if any)
          labels.put(tokenTagToken.tokenName, tree);
          if (tokenTagToken.label != null) {
            labels.put(tokenTagToken.label, tree);
          }
        } else if (t1.text == t2.text) {
          // x and x
        } else {
          // x and y
          if (mismatchedNode == null) {
            mismatchedNode = t1;
          }
        }
      } else {
        if (mismatchedNode == null) {
          mismatchedNode = t1;
        }
      }

      return mismatchedNode;
    }

    if (tree is ParserRuleContext && patternTree is ParserRuleContext) {
      ParserRuleContext r1 = tree;
      ParserRuleContext r2 = patternTree;
      ParseTree mismatchedNode = null;
      // (expr ...) and <expr>
      RuleTagToken ruleTagToken = getRuleTagToken(r2);
      if (ruleTagToken != null) {
        if (r1.ruleContext.ruleIndex == r2.ruleContext.ruleIndex) {
          // track label->list-of-nodes for both rule name and label (if any)
          labels.put(ruleTagToken.ruleName, tree);
          if (ruleTagToken.label != null) {
            labels.put(ruleTagToken.label, tree);
          }
        } else {
          if (mismatchedNode == null) {
            mismatchedNode = r1;
          }
        }

        return mismatchedNode;
      }

      // (expr ...) and (expr ...)
      if (r1.childCount != r2.childCount) {
        if (mismatchedNode == null) {
          mismatchedNode = r1;
        }

        return mismatchedNode;
      }

      int n = r1.childCount;
      for (int i = 0; i < n; i++) {
        ParseTree childMatch =
            matchImpl(r1.getChild(i), patternTree.getChild(i), labels);
        if (childMatch != null) {
          return childMatch;
        }
      }

      return mismatchedNode;
    }

    // if nodes aren't both tokens or both rule nodes, can't match
    return tree;
  }

  /** Is {@code t} {@code (expr <expr>)} subtree? */
  RuleTagToken getRuleTagToken(ParseTree t) {
    if (t is RuleNode) {
      RuleNode r = t;
      if (r.childCount == 1 && r.getChild(0) is TerminalNode) {
        TerminalNode c = r.getChild(0);
        if (c.symbol is RuleTagToken) {
//					System.out.println("rule tag subtree "+t.toStringTree(parser));
          return c.symbol;
        }
      }
    }
    return null;
  }

  List<Token> tokenize(String pattern) {
    // split pattern into chunks: sea (raw input) and islands (<ID>, <expr>)
    List<Chunk> chunks = split(pattern);

    // create token stream from text and tags
    List<Token> tokens = [];
    for (Chunk chunk in chunks) {
      if (chunk is TagChunk) {
        TagChunk tagChunk = chunk;
        // add special rule token or conjure up new token from name
        if (isUpperCase(tagChunk.tag[0])) {
          int ttype = parser.getTokenType(tagChunk.tag);
          if (ttype == Token.INVALID_TYPE) {
            throw new ArgumentError("Unknown token " +
                tagChunk.tag +
                " in pattern: " +
                pattern);
          }
          TokenTagToken t =
              new TokenTagToken(tagChunk.tag, ttype, tagChunk.label);
          tokens.add(t);
        } else if (isLowerCase(tagChunk.tag[0])) {
          int ruleIndex = parser.getRuleIndex(tagChunk.tag);
          if (ruleIndex == -1) {
            throw new ArgumentError("Unknown rule " +
                tagChunk.tag +
                " in pattern: " +
                pattern);
          }
          int ruleImaginaryTokenType =
              parser.ATNWithBypassAlts.ruleToTokenType[ruleIndex];
          tokens.add(new RuleTagToken(
              tagChunk.tag, ruleImaginaryTokenType, tagChunk.label));
        } else {
          throw new ArgumentError(
              "invalid tag: " + tagChunk.tag + " in pattern: " + pattern);
        }
      } else {
        TextChunk textChunk = chunk;
        InputStream inputStream =
            new InputStream.fromString(textChunk.text);
        lexer.inputStream = inputStream;
        Token t = lexer.nextToken();
        while (t.type != Token.EOF) {
          tokens.add(t);
          t = lexer.nextToken();
        }
      }
    }

//		System.out.println("tokens="+tokens);
    return tokens;
  }

  /** Split {@code <ID> = <e:expr> ;} into 4 chunks for tokenizing by {@link #tokenize}. */
  List<Chunk> split(String pattern) {
    int p = 0;
    int n = pattern.length;
    List<Chunk> chunks = [];
    // find all start and stop indexes first, then collect
    List<int> starts = [];
    List<int> stops = [];
    while (p < n) {
      if (p == pattern.indexOf(escape + start, p)) {
        p += escape.length + start.length;
      } else if (p == pattern.indexOf(escape + stop, p)) {
        p += escape.length + stop.length;
      } else if (p == pattern.indexOf(start, p)) {
        starts.add(p);
        p += start.length;
      } else if (p == pattern.indexOf(stop, p)) {
        stops.add(p);
        p += stop.length;
      } else {
        p++;
      }
    }

//		System.out.println("");
//		System.out.println(starts);
//		System.out.println(stops);
    if (starts.length > stops.length) {
      throw new ArgumentError("unterminated tag in pattern: " + pattern);
    }

    if (starts.length < stops.length) {
      throw new ArgumentError("missing start tag in pattern: " + pattern);
    }

    int ntags = starts.length;
    for (int i = 0; i < ntags; i++) {
      if (starts[i] >= stops[i]) {
        throw new ArgumentError(
            "tag delimiters out of order in pattern: " + pattern);
      }
    }

    // collect into chunks now
    if (ntags == 0) {
      String text = pattern.substring(0, n);
      chunks.add(new TextChunk(text));
    }

    if (ntags > 0 && starts[0] > 0) {
      // copy text up to first tag into chunks
      String text = pattern.substring(0, starts[0]);
      chunks.add(new TextChunk(text));
    }
    for (int i = 0; i < ntags; i++) {
      // copy inside of <tag>
      String tag = pattern.substring(starts[i] + start.length, stops[i]);
      String ruleOrToken = tag;
      String label = null;
      int colon = tag.indexOf(':');
      if (colon >= 0) {
        label = tag.substring(0, colon);
        ruleOrToken = tag.substring(colon + 1, tag.length);
      }
      chunks.add(new TagChunk(ruleOrToken, label: label));
      if (i + 1 < ntags) {
        // copy from end of <tag> to start of next
        String text = pattern.substring(stops[i] + stop.length, starts[i + 1]);
        chunks.add(new TextChunk(text));
      }
    }
    if (ntags > 0) {
      int afterLastTag = stops[ntags - 1] + stop.length;
      if (afterLastTag < n) {
        // copy text from end of last tag to end
        String text = pattern.substring(afterLastTag, n);
        chunks.add(new TextChunk(text));
      }
    }

    // strip out the escape sequences from text chunks but not tags
    for (int i = 0; i < chunks.length; i++) {
      Chunk c = chunks[i];
      if (c is TextChunk) {
        TextChunk tc = c;
        String unescaped = tc.text.replaceAll(escape, "");
        if (unescaped.length < tc.text.length) {
          chunks[i] = new TextChunk(unescaped);
        }
      }
    }

    return chunks;
  }
}

class CannotInvokeStartRule extends StateError {
  CannotInvokeStartRule(String message) : super(message);
}

// Fixes https://github.com/antlr/antlr4/issues/413
// "Tree pattern compilation doesn't check for a complete parse"
class StartRuleDoesNotConsumeFullPattern extends Error {}

/**
 * This exception is thrown to cancel a parsing operation. This exception does
 * not extend {@link RecognitionException}, allowing it to bypass the standard
 * error recovery mechanisms. {@link BailErrorStrategy} throws this exception in
 * response to a parse error.
 */
class ParseCancellationException extends StateError {
  ParseCancellationException(String message) : super(message);
}
