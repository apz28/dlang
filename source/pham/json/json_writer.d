/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_writer;

import std.range : empty, isOutputRange;

import pham.utl.utl_array_append : Appender;
import pham.json.json_codec;
import pham.json.json_exception;
import pham.json.json_type;
import pham.json.json_value;

struct JSONTextWriter
{
    //import std.ascii : newline;
    import std.string : splitLines;

@safe:

public:
    this(JSONOptions options, string tab = defaultTab) nothrow pure
    {
        this.options = options;
        this.tab = tab;
        this.encoder = JSONTextEncoder(options);
        this.json5 = (options & JSONOptions.json5) != 0;
        this.objectName = (options & JSONOptions.objectName) != 0;
        this.prettyString = (options & JSONOptions.prettyString) != 0;
    }

    auto ref Sink put(Sink)(return auto ref Sink json, ref const(JSONValue) root)
    if (isOutputRange!(Sink, char))
    {
        put(json, root, 0);
        return json;
    }

    /* Mark as @trusted because json.put() may be @system. This has difficulty
     * inferring @safe because it is recursive.
     */
    void put(Sink)(auto ref Sink json, ref const(JSONValue) value, const(uint) indentLevel) @trusted
    if (isOutputRange!(Sink, char))
    {
        final switch (value.type)
        {
            case JSONType.integer:
                encoder.toString(json, value._store.integer);
                break;

            case JSONType.float_:
                encoder.toString(json, value._store.floating);
                break;

            case JSONType.string:
                encoder.toString(json, value._store.str);
                break;

            case JSONType.array:
                auto arr = value._store.array;
                if (arr.empty)
                {
                    json.put("[]");
                }
                else
                {
                    const elIndentLevel = indentLevel + 1;
                    putCharAndEOL(json, '[');
                    foreach (i, ref e; arr)
                    {
                        if (i)
                            putCharAndEOL(json, ',');

                        putTabs(json, elIndentLevel);
                        put(json, e, elIndentLevel);
                    }
                    putEOL(json);
                    putTabs(json, indentLevel);
                    json.put(']');
                }
                break;

            case JSONType.object:
                auto obj = cast()value._store.object; // Cast away const for foreach
                if (obj.empty)
                {
                    json.put("{}");
                }
                else
                {
                    const elIndentLevel = indentLevel + 1;
                    putCharAndEOL(json, '{');
                    foreach (i, k, ref v; obj)
                    {
                        if (i)
                            putCharAndEOL(json, ',');

                        putTabs(json, elIndentLevel);
                        version(JSONCommentStore) 
                        {
                            if (v.comment.length)
                            {
                                putComment(json, v.comment, elIndentLevel);
                                putEOL(json);
                                putTabs(json, elIndentLevel);
                            }
                        }
                        if (objectName)
                            encoder.toStringName(json, k);
                        else
                            encoder.toString(json, k);
                        json.put(prettyString ? ": " : ":");
                        put(json, v, elIndentLevel);
                    }

                    putEOL(json);
                    putTabs(json, indentLevel);
                    json.put('}');
                }
                break;

            case JSONType.true_:
                encoder.toString(json, true);
                break;

            case JSONType.false_:
                encoder.toString(json, false);
                break;

            case JSONType.null_:
                encoder.toString(json, null);
                break;
        }
    }

private:
    void putCharAndEOL(Sink)(auto ref Sink json, char value) nothrow
    {
        json.put(value);
        putEOL(json);
    }

    void putComment(Sink)(auto ref Sink json, scope const(char)[] comment, const(uint) indentLevel) nothrow
    {
        import std.string : strip;
        
        json.put("/* ");
        auto lines = splitLines(comment);
        foreach (i, line; lines)
        {
            if (i)
            {
                putEOL(json);
                putTabs(json, indentLevel);
                json.put("   ");
            }
            json.put(line.strip());
        }
        json.put(" */");
    }

    void putEOL(Sink)(auto ref Sink json) nothrow
    {
        if (prettyString)
            json.put('\n');
    }

    void putTabs(Sink)(auto ref Sink json, const(uint) indentLevel) nothrow
    {
        if (prettyString && tab.length)
        {
            foreach (i; 0..indentLevel)
                json.put(tab);
        }
    }

public:
    string tab;
    JSONTextEncoder encoder;
    JSONOptions options;
    bool json5;
    bool objectName;
    bool prettyString;
}

/**
 * Takes a tree of JSON values and returns the serialized string.
 */
auto ref Sink toJSON(Sink)(auto ref Sink json, auto ref const(JSONValue) root,
    JSONOptions options = defaultOptions,
    string tab = defaultTab)
if (isOutputRange!(Sink, char))
{
    auto writer = JSONTextWriter(options, tab);
    return writer.put(json, root);
}

/// dito
string toJSON(ref const(JSONValue) root,
    JSONOptions options = defaultOptions,
    string tab = defaultTab) @safe
{
    Appender!string result;
    return toJSON(result, root, options, tab).data;
}
