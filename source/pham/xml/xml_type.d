/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml.type;

nothrow @safe:

/** Template trait to determine if S is an build in D string (string, wstring, dstring.)
    Params:
        S = A type name.
    Returns:
        true if S is of a type string, wstring or dstring.
*/
enum bool isXmlString(S) = is(S == string) || is(S == wstring) || is(S == dstring);

/** Get XMLChar qualifier template from one of D string type S
*/
template XmlChar(S)
if (isXmlString!S)
{
    static if (is(S == string))
        alias XmlChar = char;
    else static if (is(S == wstring))
        alias XmlChar = wchar;
    else static if (is(S == dstring))
        alias XmlChar = dchar;
    else
        static assert(0);
}
