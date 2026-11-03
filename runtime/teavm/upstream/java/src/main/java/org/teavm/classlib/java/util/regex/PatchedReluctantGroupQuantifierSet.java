/*
 *  Copyright 2015 Alexey Andreev.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

/*
 *  Licensed to the Apache Software Foundation (ASF) under one or more
 *  contributor license agreements.  See the NOTICE file distributed with
 *  this work for additional information regarding copyright ownership.
 *  The ASF licenses this file to You under the Apache License, Version 2.0
 *  (the "License"); you may not use this file except in compliance with
 *  the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

/**
 * @author Nikolay A. Kuznetsov
 */
package org.teavm.classlib.java.util.regex;

/**
 * Relactant version of the group quantifier set.
 *
 * @author Nikolay A. Kuznetsov
 */
public class PatchedReluctantGroupQuantifierSet extends TGroupQuantifierSet {
    public PatchedReluctantGroupQuantifierSet(TAbstractSet innerSet, TAbstractSet next, int type) {
        super(innerSet, next, type);
    }

    @Override
    public int matches(int stringIndex, CharSequence testString, TMatchResultImpl matchResult) {
        // Dot nodes consume exactly one code point and do not change captures.
        // Keep the native terminator predicate and UTF-16 boundaries, but scan
        // iteratively so a long reluctant match does not exhaust the JS stack.
        if (innerSet instanceof TDotSet || innerSet instanceof TDotAllSet) {
            int right = matchResult.getRightBound();
            while (true) {
                int result = next.matches(stringIndex, testString, matchResult);
                if (result >= 0) return result;
                if (stringIndex >= right) { matchResult.hitEnd = true; return -1; }
                char high = testString.charAt(stringIndex);
                int count = 1, codePoint = high;
                if (Character.isHighSurrogate(high) && stringIndex + 1 < right) {
                    char low = testString.charAt(stringIndex + 1);
                    if (Character.isLowSurrogate(low)) { codePoint = Character.toCodePoint(high, low); count = 2; }
                }
                if (innerSet instanceof TDotSet && ((TDotSet) innerSet).lt.isLineTerminator(codePoint)) return -1;
                stringIndex += count;
            }
        }
        if (!innerSet.hasConsumed(matchResult)) {
            return next.matches(stringIndex, testString, matchResult);
        }

        int res = next.matches(stringIndex, testString, matchResult);
        if (res < 0) {
            return innerSet.matches(stringIndex, testString, matchResult);
        } else {
            return res;
        }
    }
}
