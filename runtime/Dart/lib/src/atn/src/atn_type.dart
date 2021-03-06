/*
 * Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

/// Represents the type of recognizer an ATN applies to.
enum ATNType {
  /**
   * A lexer grammar.
   */
  LEXER,

  /**
   * A parser grammar.
   */
  PARSER
}
