/*
 *  Copyright 2017 Alexey Andreev.
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
 * Node accepting substrings in unicode case insensitive manner.
 *
 * @author Nikolay A. Kuznetsov
 */
class PatchedUCISequenceSet extends TLeafSet {

    private String string;
    private int[] codePoints;
    private int count;

    PatchedUCISequenceSet(StringBuffer substring) {
        string = substring.toString();
        charCount = string.length();
        codePoints = new int[charCount];
        for (int i = 0; i < string.length();) {
            int codePoint = Character.codePointAt(string, i);
            codePoints[count++] = Character.toLowerCase(Character.toUpperCase(codePoint));
            i += Character.charCount(codePoint);
        }
    }

    @Override
    public int accepts(int strIndex, CharSequence text) {
        int start = strIndex;
        for (int i = 0; i < count; i++) {
            int codePoint = Character.codePointAt(text, strIndex);
            if (codePoints[i] != Character.toLowerCase(Character.toUpperCase(codePoint))) {
                return -1;
            }
            strIndex += Character.charCount(codePoint);
        }
        return strIndex - start;
    }

    @Override
    public String getName() {
        return new StringBuilder("UCI sequence: ").append(string).toString();
    }
}
