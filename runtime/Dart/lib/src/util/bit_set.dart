/* Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */
import 'dart:math';
import 'dart:typed_data';

class BitSet {
  static final Uint32List EmptyBits = Uint32List(0);
  static const BitsPerElement = 8 * 32;

  Uint32List _data = EmptyBits;

  BitSet([int nbits = 0]) {
    if (nbits == 0) {
      return;
    }
    if (nbits < 0) throw new RangeError("nbits");

    if (nbits > 0) {
      int length = ((nbits + BitsPerElement - 1) / BitsPerElement).floor();
      _data = Uint32List(length);
    }
  }

  static int getBitCount(Uint32List value) {
    int data = 0;
    final size = value.length;
    const int m1 = 0x5555555555555555;
    const int m2 = 0x3333333333333333;
    const int m4 = 0x0F0F0F0F0F0F0F0F;
    const int m8 = 0x00FF00FF00FF00FF;
    const int m16 = 0x0000FFFF0000FFFF;
    const int h01 = 0x0101010101010101;

    int bitCount = 0;
    int limit30 = size - size % 30;

    // 64-bit tree merging (merging3)
    for (var i = 0; i < limit30; i += 30, data += 30) {
      int acc = 0;
      for (var j = 0; j < 30; j += 3) {
        int count1 = value[data + j];
        int count2 = value[data + j + 1];
        int half1 = value[data + j + 2];
        int half2 = half1;
        half1 &= m1;
        half2 = (half2 >> 1) & m1;
        count1 -= (count1 >> 1) & m1;
        count2 -= (count2 >> 1) & m1;
        count1 += half1;
        count2 += half2;
        count1 = (count1 & m2) + ((count1 >> 2) & m2);
        count1 += (count2 & m2) + ((count2 >> 2) & m2);
        acc += (count1 & m4) + ((count1 >> 4) & m4);
      }

      acc = (acc & m8) + ((acc >> 8) & m8);
      acc = (acc + (acc >> 16)) & m16;
      acc = acc + (acc >> 32);
      bitCount += acc;
    }

    // count the bits of the remaining bytes (MAX 29*8) using
    // "Counting bits set, in parallel" from the "Bit Twiddling Hacks",
    // the code uses wikipedia's 64-bit popcount_3() implementation:
    // http://en.wikipedia.org/wiki/Hamming_weight#Efficient_implementation
    for (int i = 0; i < size - limit30; i++) {
      int x = value[data + i];
      x = x - ((x >> 1) & m1);
      x = (x & m2) + ((x >> 2) & m2);
      x = (x + (x >> 4)) & m4;
      bitCount += ((x * h01) >> 56);
    }

    return bitCount;
  }

  static final List<int> index64 = [
    0,
    47,
    1,
    56,
    48,
    27,
    2,
    60,
    57,
    49,
    41,
    37,
    28,
    16,
    3,
    61,
    54,
    58,
    35,
    52,
    50,
    42,
    21,
    44,
    38,
    32,
    29,
    23,
    17,
    11,
    4,
    62,
    46,
    55,
    26,
    59,
    40,
    36,
    15,
    53,
    34,
    51,
    20,
    43,
    31,
    22,
    10,
    45,
    25,
    39,
    14,
    33,
    19,
    30,
    9,
    24,
    13,
    18,
    8,
    12,
    7,
    6,
    5,
    63
  ];

  static int BitScanForward(int value) {
    if (value == 0) return -1;

    const int debruijn64 = 0x03f79d71b4cb0a89;
    return index64[((value ^ (value - 1)) * debruijn64) >> 58];
  }

  BitSet clone() {
    BitSet result = new BitSet();
    result._data = List.from(_data);
    return result;
  }

  void clear(int index) {
    if (index < 0) throw new RangeError("index");

    int element = (index / BitsPerElement).floor();
    if (element >= _data.length) return;

    _data[element] &= ~(1 << (index % BitsPerElement));
  }

  bool operator [](int index) {
    return get(index);
  }

  bool get(int index) {
    if (index < 0) throw new RangeError("index");

    int element = (index / BitsPerElement).floor();
    if (element >= _data.length) return false;

    return (_data[element] & (1 << (index % BitsPerElement))) != 0;
  }

  void set(int index) {
    if (index < 0) throw new RangeError("index");

    int element = (index / BitsPerElement).floor();
    if (element >= _data.length) {
      final newList = []
        ..length = max(_data.length * 2, element + 1)
        ..setRange(0, _data.length, _data);
      _data = newList;
    }
    _data[element] |= 1 << (index % BitsPerElement);
  }

  bool get isEmpty {
    for (int i = 0; i < _data.length; i++) {
      if (_data[i] != 0) return false;
    }

    return true;
  }

  int get cardinality {
    return getBitCount(_data);
  }

  int nextset(int fromIndex) {
    if (fromIndex < 0) throw new RangeError("fromIndex");

    if (isEmpty) return -1;

    int i = (fromIndex / BitsPerElement).floor();
    if (i >= _data.length) return -1;

    int current = _data[i] & ~((1 << (fromIndex % BitsPerElement)) - 1);

    while (true) {
      int bit = BitScanForward(current);
      if (bit >= 0) return bit + i * BitsPerElement;

      i++;
      if (i >= _data.length) break;

      current = _data[i];
    }

    return -1;
  }

  void and(BitSet set) {
    if (set == null) throw new ArgumentError.notNull("set");

    int length = min(_data.length, set._data.length);
    for (int i = 0; i < length; i++) _data[i] &= set._data[i];

    for (int i = length; i < _data.length; i++) _data[i] = 0;
  }

  void or(BitSet set) {
    if (set == null) throw new ArgumentError.notNull("set");

    if (set._data.length > _data.length) {
      final newList = []
        ..length = set._data.length
        ..setRange(0, _data.length, _data);
      _data = newList;
    }

    for (int i = 0; i < set._data.length; i++) _data[i] |= set._data[i];
  }

  bool operator ==(obj) {
    BitSet other = obj as BitSet;
    if (other == null) return false;

    if (isEmpty) return other.isEmpty;

    int minlength = min(_data.length, other._data.length);
    for (int i = 0; i < minlength; i++) {
      if (_data[i] != other._data[i]) return false;
    }

    for (int i = minlength; i < _data.length; i++) {
      if (_data[i] != 0) return false;
    }

    for (int i = minlength; i < other._data.length; i++) {
      if (other._data[i] != 0) return false;
    }

    return true;
  }

  int get hashCode {
    int result = 1;
    for (int i = 0; i < _data.length; i++) {
      if (_data[i] != 0) {
        result = result * 31 ^ i;
        result = result * 31 ^ _data[i];
      }
    }

    return result.hashCode;
  }

  toString() {
    StringBuffer builder = new StringBuffer();
    builder.write('{');

    for (int i = nextset(0); i >= 0; i = nextset(i + 1)) {
      if (builder.length > 1) builder.write(", ");

      builder.write(i);
    }

    builder.write('}');
    return builder.toString();
  }
}
