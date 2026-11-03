/*
 *  Copyright 2014 Alexey Andreev.
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
 * Default quantifier over groups, in fact this type of quantifier is generally
 * used for constructions we cant identify number of characters they consume.
 *
 * @author Nikolay A. Kuznetsov
 */
public class PatchedGroupQuantifierSet extends TQuantifierSet {

    public PatchedGroupQuantifierSet(TAbstractSet innerSet, TAbstractSet next, int type) {
        super(innerSet, next, type);
    }

    @Override
    public int matches(int stringIndex, CharSequence testString, TMatchResultImpl matchResult) {

        // Atomic code-point ranges cannot alter capture groups. Preserve TeaVM's own
        // character semantics while avoiding one JavaScript stack frame per character.
        if (innerSet instanceof TSupplRangeSet || innerSet instanceof TCompositeRangeSet) {
            int[] positions = new int[64];
            int count = 0;
            positions[0] = stringIndex;
            TAbstractSet saved = innerSet.getNext();
            innerSet.setNext(TFSet.posFSet);
            try {
                while (stringIndex < matchResult.getRightBound()) {
                    int end = innerSet.matches(stringIndex, testString, matchResult);
                    if (end <= stringIndex) break;
                    if (++count == positions.length) positions = java.util.Arrays.copyOf(positions, count * 2);
                    positions[count] = end;
                    stringIndex = end;
                }
            } finally { innerSet.setNext(saved); }
            for (; count >= 0; count--) {
                int end = next.matches(positions[count], testString, matchResult);
                if (end >= 0) return end;
            }
            return -1;
        }
        if (!innerSet.hasConsumed(matchResult)) {
            return next.matches(stringIndex, testString, matchResult);
        }

        int nextIndex = innerSet.matches(stringIndex, testString, matchResult);

        if (nextIndex < 0) {
            return next.matches(stringIndex, testString, matchResult);
        } else {
            return nextIndex;
        }
    }

    @Override
    protected String getName() {
        return "<GroupQuant>";
    }
}
