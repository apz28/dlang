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

module pham.db.parser;

import std.array : Appender;

version (unittest) import pham.utl.test;
import pham.utl.utf8;
import pham.db.message;
import pham.db.exception;
import pham.db.type;
import pham.db.util;
import pham.db.database;

nothrow:

// Since we deal with Ascii characters, no need to use parseNextChar
string parseParameter(string sql, void delegate(ref Appender!string result, string, size_t) nothrow @safe parameterCallBack) @safe
in
{
    assert(parameterCallBack !is null);
}
do
{
    import std.ascii : isAlphaNum;

    version (TraceFunction) dgFunctionTrace("sql.length=", sql.length);

    if (sql.length == 0)
        return null;

    size_t pos = 0;
    size_t posBegin = size_t.max;
    size_t prmCount = 0; // Based 1 value
    auto result = Appender!string();

    static bool isNameChar(dchar c) nothrow pure
    {
        return c == '_' || c == '$' || isAlphaNum(c);
    }

    string readName() nothrow
    {
        const begin = pos;
        while (pos < sql.length && isNameChar(sql[pos]))
            ++pos;
        return sql[begin..pos].idup;
    }

    void saveCurrent(size_t endPos) nothrow
    {
        if (posBegin != size_t.max)
        {
            if (result.capacity == 0)
                result.reserve(sql.length);

            result.put(sql[posBegin..endPos]);
            posBegin = size_t.max;
        }
    }

    void skipBlockCommentIf() nothrow
    {
        if (sql[pos] == '*')
        {
            ++pos;
            char prev = 0;
            while (pos < sql.length)
            {
                const c = sql[pos++];
                if (c == '/' && prev == '*')
                    return;
                prev = c;
            }
        }
    }

    void skipLineCommentIf() nothrow
    {
        if (sql[pos] == '-')
        {
            ++pos;
            while (pos < sql.length)
            {
                const c = sql[pos++];
                if (c == 0x0A)
                    return;
                // Skip return line feed?
                else if (c == 0x0D)
                {
                    if (pos < sql.length && sql[pos] == 0x0A)
                        ++pos;
                    return;
                }
            }
        }
    }

    void skipQuote(in char quote) nothrow
    {
        char prev = 0;
        while (pos < sql.length)
        {
            const c = sql[pos++];
            if (c == quote && prev != '\\')
                return;
            prev = c;
        }
    }

    while (pos < sql.length)
    {
        const c = sql[pos];

        version (none)
        {
            dgWriteln(c, " [", pos, "]");
        }

        if (c == '@' || c == ':')
        {
            if ((pos + 1) < sql.length)
            {
                saveCurrent(pos++);
                parameterCallBack(result, readName(), ++prmCount);
            }
            else if (posBegin == size_t.max)
                posBegin = pos;
        }
        else
        {
            if (posBegin == size_t.max)
                posBegin = pos;

            if (++pos < sql.length)
            {
                if (c == '\'' || c == '"')
                    skipQuote(c);
                else if (c == '/')
                    skipBlockCommentIf();
                else if (c == '-')
                    skipLineCommentIf();
            }
        }
    }

    if (prmCount != 0)
    {
        saveCurrent(sql.length);
        return result.data;
    }
    else
        return sql;
}


// Any below codes are private
private:

unittest // parseParameter
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.parser.parseParameter");

    static class StringList
    {
    nothrow @safe:

    public:
        StringList clear()
        {
            items.length = 0;
            return this;
        }

        void saveParameter(ref Appender!string result, string prmName, size_t prmNo)
        {
            result.put('?');
            items ~= prmName;
        }

    public:
        string[] items;

        alias items this;
    }

    string s;
    auto slist = new StringList();

    slist.clear();
    assert(parseParameter("", &slist.saveParameter) == "");
    assert(slist.length == 0);

    slist.clear();
    s = parseParameter("select count(int_field) from test", &slist.saveParameter);
    assert(s == "select count(int_field) from test", s);
    assert(slist.length == 0);

    slist.clear();
    s = parseParameter("select count(int_field) from test where varchar_field = @p0", &slist.saveParameter);
    assert(s == "select count(int_field) from test where varchar_field = ?", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = parseParameter("select count(int_field) from test where varchar_field = @p0 and int_field < :p1", &slist.saveParameter);
    assert(s == "select count(int_field) from test where varchar_field = ? and int_field < ?", s);
    assert(slist.length == 2);
    assert(slist[0] == "p0");
    assert(slist[1] == "p1");

    slist.clear();
    s = parseParameter(" select count(int_field)  from test /* this is a comment with ' */  where varchar_field = @_LongName$123 ", &slist.saveParameter);
    assert(s == " select count(int_field)  from test /* this is a comment with ' */  where varchar_field = ? ", s);
    assert(slist.length == 1);
    assert(slist[0] == "_LongName$123");

    slist.clear();
    s = parseParameter("select count(int_field), ' @ ' as ab, \" : \" ac from test where varchar_field = @p0 -- comment with @p123 ", &slist.saveParameter);
    assert(s == "select count(int_field), ' @ ' as ab, \" : \" ac from test where varchar_field = ? -- comment with @p123 ", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = parseParameter("", &slist.saveParameter);
    assert(s == "", s);
    assert(slist.length == 0);
}
