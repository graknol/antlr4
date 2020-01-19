//
/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */
import 'package:collection/collection.dart';

import '../../input_stream.dart';
import '../../lexer.dart';
import '../../util/murmur_hash.dart';
import 'lexer_action.dart';

/**
 * Represents an executor for a sequence of lexer actions which traversed during
 * the matching operation of a lexer rule (token).
 *
 * <p>The executor tracks position information for position-dependent lexer actions
 * efficiently, ensuring that actions appearing only at the end of the rule do
 * not cause bloating of the {@link DFA} created for the lexer.</p>
 *
 * @author Sam Harwell
 * @since 4.2
 */
class LexerActionExecutor {
  /**
   * Gets the lexer actions to be executed by this executor.
   * @return The lexer actions to be executed by this executor.
   */
  final List<LexerAction> lexerActions;

  /**
   * Caches the result of {@link #hashCode} since the hash code is an element
   * of the performance-critical {@link LexerATNConfig#hashCode} operation.
   */
  int get hashCode {
    int hash = MurmurHash.initialize();
    for (LexerAction lexerAction in lexerActions) {
      hash = MurmurHash.update(hash, lexerAction);
    }

    return MurmurHash.finish(hash, lexerActions.length);
  }

  /**
   * Constructs an executor for a sequence of {@link LexerAction} actions.
   * @param lexerActions The lexer actions to execute.
   */
  LexerActionExecutor(List<LexerAction> this.lexerActions) {}

  /**
   * Creates a {@link LexerActionExecutor} which executes the actions for
   * the input {@code lexerActionExecutor} followed by a specified
   * {@code lexerAction}.
   *
   * @param lexerActionExecutor The executor for actions already traversed by
   * the lexer while matching a token within a particular
   * {@link LexerATNConfig}. If this is {@code null}, the method behaves as
   * though it were an empty executor.
   * @param lexerAction The lexer action to execute after the actions
   * specified in {@code lexerActionExecutor}.
   *
   * @return A {@link LexerActionExecutor} for executing the combine actions
   * of {@code lexerActionExecutor} and {@code lexerAction}.
   */
  static LexerActionExecutor append(
      LexerActionExecutor lexerActionExecutor, LexerAction lexerAction) {
    if (lexerActionExecutor == null) {
      return new LexerActionExecutor([lexerAction]);
    }

    List<LexerAction> lexerActions =
        List.from(lexerActionExecutor.lexerActions);
    lexerActions.add(lexerAction);
    return new LexerActionExecutor(lexerActions);
  }

  /**
   * Creates a {@link LexerActionExecutor} which encodes the current offset
   * for position-dependent lexer actions.
   *
   * <p>Normally, when the executor encounters lexer actions where
   * {@link LexerAction#isPositionDependent} returns {@code true}, it calls
   * {@link IntStream#seek} on the input {@link CharStream} to set the input
   * position to the <em>end</em> of the current token. This behavior provides
   * for efficient DFA representation of lexer actions which appear at the end
   * of a lexer rule, even when the lexer rule matches a variable number of
   * characters.</p>
   *
   * <p>Prior to traversing a match transition in the ATN, the current offset
   * from the token start index is assigned to all position-dependent lexer
   * actions which have not already been assigned a fixed offset. By storing
   * the offsets relative to the token start index, the DFA representation of
   * lexer actions which appear in the middle of tokens remains efficient due
   * to sharing among tokens of the same length, regardless of their absolute
   * position in the input stream.</p>
   *
   * <p>If the current executor already has offsets assigned to all
   * position-dependent lexer actions, the method returns {@code this}.</p>
   *
   * @param offset The current offset to assign to all position-dependent
   * lexer actions which do not already have offsets assigned.
   *
   * @return A {@link LexerActionExecutor} which stores input stream offsets
   * for all position-dependent lexer actions.
   */
  LexerActionExecutor fixOffsetBeforeMatch(int offset) {
    List<LexerAction> updatedLexerActions = null;
    for (int i = 0; i < lexerActions.length; i++) {
      if (lexerActions[i].isPositionDependent &&
          !(lexerActions[i] is LexerIndexedCustomAction)) {
        if (updatedLexerActions == null) {
          updatedLexerActions = List.from(lexerActions);
        }

        updatedLexerActions[i] =
            new LexerIndexedCustomAction(offset, lexerActions[i]);
      }
    }

    if (updatedLexerActions == null) {
      return this;
    }

    return new LexerActionExecutor(updatedLexerActions);
  }

  /**
   * Execute the actions encapsulated by this executor within the context of a
   * particular {@link Lexer}.
   *
   * <p>This method calls {@link IntStream#seek} to set the position of the
   * {@code input} {@link CharStream} prior to calling
   * {@link LexerAction#execute} on a position-dependent action. Before the
   * method returns, the input position will be restored to the same position
   * it was in when the method was invoked.</p>
   *
   * @param lexer The lexer instance.
   * @param input The input stream which is the source for the current token.
   * When this method is called, the current {@link IntStream#index} for
   * {@code input} should be the start of the following token, i.e. 1
   * character past the end of the current token.
   * @param startIndex The token start index. This value may be passed to
   * {@link IntStream#seek} to set the {@code input} position to the beginning
   * of the token.
   */
  void execute(Lexer lexer, CharStream input, int startIndex) {
    bool requiresSeek = false;
    int stopIndex = input.index;
    try {
      for (LexerAction lexerAction in lexerActions) {
        if (lexerAction is LexerIndexedCustomAction) {
          int offset = (lexerAction as LexerIndexedCustomAction).offset;
          input.seek(startIndex + offset);
          lexerAction = (lexerAction as LexerIndexedCustomAction).action;
          requiresSeek = (startIndex + offset) != stopIndex;
        } else if (lexerAction.isPositionDependent) {
          input.seek(stopIndex);
          requiresSeek = false;
        }

        lexerAction.execute(lexer);
      }
    } finally {
      if (requiresSeek) {
        input.seek(stopIndex);
      }
    }
  }

  bool operator ==(Object obj) {
    if (identical(obj, this)) {
      return true;
    } else if (!(obj is LexerActionExecutor)) {
      return false;
    }

    LexerActionExecutor other = obj;
    return hashCode == other.hashCode &&
        ListEquality().equals(lexerActions, other.lexerActions);
  }
}