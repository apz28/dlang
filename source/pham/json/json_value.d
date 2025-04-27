/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_value;

import std.conv : ConvException, text, to;
import std.exception : enforce;
import std.range : isSomeFiniteCharInputRange;
import std.traits : fullyQualifiedName, isArray, isFloatingPoint, isIntegral, isSomeString,
    isStaticArray, isUnsigned, Unqual;
import std.utf : byUTF;

debug(debug_pham_utl_utl_json) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.json.json_reader;
import pham.json.json_type;
import pham.json.json_writer;
public import pham.utl.utl_array_dictionary : Dictionary;
public import pham.json.json_exception : JSONException;
public import pham.json.json_type : defaultOptions, defaultPrettyOptions, defaultTab,
    JSONFloatLiteralType, JSONLiteral, JSONOptions, JSONType;


/**
 * JSON value node
 */
struct JSONValue
{
public:
    /**
     * Constructor for `JSONValue`. If `arg` is a `JSONValue`
     * its value and type will be copied to the new `JSONValue`.
     * Note that this is a shallow copy: if type is `JSONType.object`
     * or `JSONType.array` then only the reference to the data will
     * be copied.
     * Otherwise, `arg` must be implicitly convertible to one of the
     * following types: `typeof(null)`, `string`,
     * `long`, `double`, an associative array `V[K]` for any `V`
     * and `K` i.e. a JSON object, any array or `bool`. The type will
     * be set accordingly.
     */
    this(T)(T arg)
    if (!isStaticArray!T)
    {
        assign!false(arg);
    }

    /// Ditto
    this(T)(ref T arg)
    if (isStaticArray!T)
    {
        assignRef!false(arg);
    }

    /// Ditto
    this(T : JSONValue)(inout(T) arg) inout
    {
        this._store = arg._store;
        this._type = arg._type;
    }

    /// Implements the foreach `opApply` interface for json array & object.
    alias opApply = opApplyImpl!(int delegate(size_t index, ref JSONValue value));
    alias opApply = opApplyImpl!(int delegate(string key, ref JSONValue value));
    alias opApply = opApplyImpl!(int delegate(size_t index, string key, ref JSONValue value));
    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(size_t, ref JSONValue))
        || is(CallBack : int delegate(string, ref JSONValue))
        || is(CallBack : int delegate(size_t, string, ref JSONValue)))
    {
        static if (is(CallBack : int delegate(size_t, ref JSONValue)))
        {
            auto arr = this.array;
            foreach (i, ref v; arr)
            {
                if (auto r = callBack(i, v))
                    return r;
            }
        }
        else static if (is(CallBack : int delegate(size_t, string, ref JSONValue)))
        {
            auto obj = this.object;
            foreach (i, k, ref v; obj)
            {
                if (auto r = callBack(i, k, v))
                    return r;
            }
        }
        else
        {
            auto obj = this.object;
            foreach (k, ref v; obj)
            {
                if (auto r = callBack(k, v))
                    return r;
            }
        }

        return 0;
    }

    void opAssign(T)(T arg)
    if (!isStaticArray!T && !is(T : JSONValue))
    {
        assign!true(arg);
    }

    void opAssign(T)(ref T arg)
    if (isStaticArray!T)
    {
        assignRef!true(arg);
    }

    JSONValue opBinary(string op : "~", T)(T arg)
    {
        auto arr = this.array;
        static if (isArray!T)
        {
            return JSONValue(arr ~ JSONValue(arg).array);
        }
        else static if (is(T : JSONValue))
        {
            return JSONValue(arr ~ arg.array);
        }
        else
        {
            static assert(false, "argument is not an array or a JSONValue array");
        }
    }

    /**
     * Provides support for the `in` operator.
     *
     * Tests whether a key can be found in an object.
     *
     * Returns:
     *      When found, the `inout(JSONValue)*` that matches to the key,
     *      otherwise `null`.
     *
     * Throws: `JSONException` if the right hand side argument `JSONType` is not `object`.
     */
    inout(JSONValue)* opBinaryRight(string op : "in")(scope const(char)[] key) inout return @safe
    {
        auto obj = this.object;
        return key in obj;
    }

    /**
     * Compare two JSONValues for equality
     *
     * JSON arrays and objects are compared deeply. The order of object keys does not matter.
     *
     * Floating point numbers are compared for exact equality, not approximal equality.
     *
     * Different number types (unsigned, signed, and floating) will be compared by converting
     * them to a common type, in the same way that comparison of built-in D `int`, `uint` and
     * `float` works.
     *
     * Other than that, types must match exactly.
     * Empty arrays are not equal to empty objects, and booleans are never equal to integers.
     *
     * Returns: whether this `JSONValue` is equal to `rhs`
     */
    bool opEquals(const JSONValue rhs) const @nogc nothrow pure @safe
    {
        return opEquals(rhs);
    }

    /// ditto
    bool opEquals(ref const JSONValue rhs) const @nogc nothrow pure @trusted
    {
        import std.algorithm.searching : canFind;

        final switch (this.type)
        {
            case JSONType.integer:
                switch (rhs.type)
                {
                    case JSONType.integer:
                        return this._store.integer == rhs._store.integer;
                    case JSONType.float_:
                        return this._store.integer == rhs._store.floating;
                    default:
                        return false;
                }

            case JSONType.float_:
                switch (rhs.type)
                {
                    case JSONType.integer:
                        return this._store.floating == rhs._store.integer;
                    case JSONType.float_:
                        return this._store.floating == rhs._store.floating;
                    default:
                        return false;
                }

            case JSONType.string:
                return rhs.type == JSONType.string && this._store.str == rhs._store.str;

            case JSONType.array:
                return rhs.type == JSONType.array && this._store.array == rhs._store.array;

            case JSONType.object:
                return rhs.type == JSONType.object && this._store.object == rhs._store.object;

            case JSONType.null_:
            case JSONType.true_:
            case JSONType.false_:
                return this.type == rhs.type;
        }
    }

    /**
     * Array syntax for JSON arrays.
     * Throws: `JSONException` if `type` is not `JSONType.array`.
     */
    ref inout(JSONValue) opIndex(size_t index) inout pure @safe
    {
        auto arr = this.array;
        enforce!JSONException(index < arr.length, "JSONValue array index is out of range: " ~ index.to!string);
        return arr[index];
    }

    /**
     * Hash syntax for JSON objects.
     * Throws: `JSONException` if `type` is not `JSONType.object`.
     */
    ref inout(JSONValue) opIndex(return scope const(char)[] key) inout pure @safe
    {
        auto obj = this.object;
        return *enforce!JSONException(key in obj, "Key not found: " ~ key);
    }

    /**
     * Provides support for index assignments, which sets the
     * corresponding value of the JSON object's `key` field to `value`.
     *
     * If the `JSONValue` is `JSONType.null_`, then this function
     * initializes it with a JSON object and then performs
     * the index assignment.
     *
     * Throws: `JSONException` if `type` is not `JSONType.object` or `JSONType.null_`.
     */
    void opIndexAssign(T)(auto ref T arg, string key) @trusted
    {
        enforce!JSONException(type == JSONType.object || type == JSONType.null_, "JSONValue must be an object or null type");

        if (type == JSONType.null_)
            nullify(JSONType.object)._store = Store(object: Dictionary!(string, JSONValue)([key: asJSONValue(arg)]));
        else
            _store.object[key] = asJSONValue(arg);
        debug(debug_pham_utl_utl_json) debug writeln(__FUNCTION__, "(key=", key, ", json=", toString(), ")");
    }

    /// ditto
    void opIndexAssign(T)(auto ref T arg, size_t index)
    {
        enforce!JSONException(type == JSONType.array, "JSONValue is not an array");
        enforce!JSONException(index < _store.array.length, "JSONValue array index is out of range: " ~ index.to!string);

        _store.array[index] = asJSONValue(arg);
        debug(debug_pham_utl_utl_json) debug writeln(__FUNCTION__, "(index=", index, ", json=", toString(), ")");
    }

    void opOpAssign(string op : "~", T)(auto ref T arg)
    {
        enforce!JSONException(type == JSONType.array, "JSONValue is not an array type");

        static if (isArray!T)
            _store.array ~= JSONValue(arg).array;
        else static if (is(T : JSONValue))
            _store.array ~= arg.array;
        else
            static assert(false, "Argument is not an array or a JSONValue array: " ~ fullyQualifiedName!T);
        debug(debug_pham_utl_utl_json) debug writeln(__FUNCTION__, "(json=", toString(), ")");
    }

    /**
     * An enum value that can be used to obtain a `JSONValue` representing an empty JSON array.
     */
    enum emptyArray = JSONValue(JSONValue[].init);

    /**
     * An enum value that can be used to obtain a `JSONValue` representing an empty JSON object.
     */
    enum emptyObject = JSONValue(Dictionary!(string, JSONValue).init);

    /**
     * A convenience getter that returns this `JSONValue` as the specified D type.
     * Note: Only numeric types, `bool`, `string`, `JSONValue[string]`, and `JSONValue[]` types are accepted
     * Throws: `JSONException` if `T` cannot hold the contents of this `JSONValue`
     *         or in case of integer overflow when converting to `T`
     */
    inout(T) get(T)() const inout pure @safe
    if (!is(T : JSONValue[string]))
    {
        alias UT = Unqual!T;

        static if (is(immutable T == immutable string))
        {
            return str;
        }
        else static if (is(immutable T == immutable bool))
        {
            return boolean;
        }
        else static if (isFloatingPoint!T)
        {
            switch (type)
            {
                case JSONType.integer:
                    return cast(T)_store.integer;
                case JSONType.float_:
                    return cast(T)_store.floating;
                default:
                    throw new JSONException("JSONValue is not a number type: " ~ fullyQualifiedName!T);
            }
        }
        else static if (isIntegral!T)
        {
            switch (type)
            {
                case JSONType.integer:
                    long integerV = _store.integer;
                    try { return integerV.to!UT; } catch (ConvException e) throw new JSONException(e.msg, e.file, e.line, e);
                case JSONType.float_:
                    long floatV = cast(long)_store.floating;
                    try { return floatV.to!UT; } catch (ConvException e) throw new JSONException(e.msg, e.file, e.line, e);
                default:
                    throw new JSONException("JSONValue is not an integral type: " ~ fullyQualifiedName!T);
            }
        }
        else
        {
            static assert(false, "Unsupported get() for type: " ~ fullyQualifiedName!T);
        }
    }

    /// ditto
    inout(T) get(T : JSONValue[])() inout pure @safe
    {
        return array;
    }

    /// ditto
    inout(T) get(T : Dictionary!(string, JSONValue))() inout pure @safe
    {
        return object;
    }

    /// ditto
    T get(T : JSONValue[string])() @safe
    {
        return object.asAA;
    }

    ref JSONValue nullify(JSONType newType = JSONType.null_) nothrow return @trusted
    {
        final switch (_type)
        {
            case JSONType.string:
                _store.str = null;
                break;

            case JSONType.array:
                _store.array = [];
                break;

            case JSONType.object:
                _store.object = Dictionary!(string, JSONValue).init;
                break;

            case JSONType.null_:
            case JSONType.false_:
            case JSONType.true_:
            case JSONType.integer:
            case JSONType.float_:
                break;
        }

        _store.dummy[] = 0;
        _type = newType;
        version(JSONCommentStore) comment = null;
        return this;
    }

    static JSONValue parse(T, JSONOptions options = defaultOptions)(T json, uint maxDepth = 0)
    if (isSomeFiniteCharInputRange!T)
    {
        return parseJSON!(T, options)(json, maxDepth);
    }

    static JSONValue parse(JSONOptions options, T)(T json, uint maxDepth = 0)
    if (isSomeFiniteCharInputRange!T)
    {
        return parseJSON!(T, options)(json, maxDepth);
    }

    /**
     * Calculate a numerical hash value for this value,
     * allowing `JSONValue` to be used in associative arrays.
     */
    size_t toHash() const @nogc nothrow pure @trusted
    {
        final switch (type)
        {
            case JSONType.integer:
                return hashOf(_store.integer);

            case JSONType.float_:
                return hashOf(_store.floating);

            case JSONType.string:
                return hashOf(_store.str);

            case JSONType.object:
                return _store.object.hashOf();

            case JSONType.array:
                size_t result;
                foreach (ref v; _store.array)
                    result = hashOf(v, result);
                return result;

            case JSONType.null_:
            case JSONType.false_:
            case JSONType.true_:
                return type + 1;
        }
    }

    /**
     * Implicitly calls `toJSON` on this JSONValue.
     *
     * $(I options) can be used to tweak the conversion behavior.
     */
    string toString(JSONOptions options = defaultOptions,
        string tab = defaultTab) const @safe
    {
        Appender!string result;
        return toJSON(result, this, options, tab).data;
    }

    ///
    auto ref Sink toString(Sink)(auto ref Sink sink,
        JSONOptions options = defaultOptions,
        string tab = defaultTab) const @safe
    {
        return toJSON(sink, this, options, tab);
    }

    /**
     * Value getter/setter for `JSONType.array`.
     * Throws: `JSONException` for read access if `type` is not `JSONType.array`.
     */
    @property ref inout(JSONValue[]) array() inout pure return scope @trusted
    {
        enforce!JSONException(type == JSONType.array, "JSONValue is not an array type");
        return _store.array;
    }

    /// ditto
    @property JSONValue[] array(return scope JSONValue[] v) nothrow scope @safe// TODO make @safe
    {
        assign!true(v);
        return v;
    }

    /**
     * Value getter/setter for boolean stored in JSON.
     * Throws: `JSONException` for read access if `this.type` is not
     * `JSONType.true_` or `JSONType.false_`.
     */
    @property bool boolean() const pure @safe
    {
        if (type == JSONType.true_)
            return true;

        if (type == JSONType.false_)
            return false;

        throw new JSONException("JSONValue is not a boolean type");
    }

    /// ditto
    @property bool boolean(bool v) nothrow @safe
    {
        assign!true(v);
        return v;
    }

    /**
     * Value getter/setter for `JSONType.float_`.
     * Throws: `JSONException` for read access if `type` is not `JSONType.float_`.
     * Note:
     *  Despite the name, this is a 64-bit `double`, not a 32-bit `float`.
     */
    @property double floating() const pure @safe
    {
        enforce!JSONException(type == JSONType.float_, "JSONValue is not a floating type");
        return _store.floating;
    }

    /// ditto
    @property double floating(double v) nothrow @safe
    {
        assign!true(v);
        return v;
    }

    /**
     * Value getter/setter for `JSONType.integer`.
     * Throws: `JSONException` for read access if `type` is not `JSONType.integer`.
     */
    @property long integer() const pure @safe
    {
        enforce!JSONException(type == JSONType.integer, "JSONValue is not an integer type");
        return _store.integer;
    }

    /// ditto
    @property long integer(long v) nothrow @safe
    {
        assign!true(v);
        return v;
    }

    /// Test whether the type is `JSONType.null_`
    @property bool isNull() const @nogc nothrow pure @safe
    {
        return type == JSONType.null_;
    }

    /**
     * Value getter/setter for unordered `JSONType.object`.
     * Throws: `JSONException` for read access if `type` is not `JSONType.object`
     */
    @property ref inout(Dictionary!(string, JSONValue)) object() inout pure return @trusted
    {
        enforce!JSONException(type == JSONType.object, "JSONValue is not an object type");
        return _store.object;
    }

    /// ditto
    @property Dictionary!(string, JSONValue) object(return scope Dictionary!(string, JSONValue) v) nothrow @safe
    {
        assign!true(v);
        return v;
    }

    /// ditto
    @property Dictionary!(string, JSONValue) object(scope JSONValue[string] v) nothrow @safe
    {
        auto newV = v.asAA;
        assign!true(newV);
        return newV;
    }

    /**
     * Value getter/setter for `JSONType.string`.
     * Throws: `JSONException` for read access if `type` is not `JSONType.string`.
     */
    @property string str() const pure return scope @trusted
    {
        enforce!JSONException(type == JSONType.string, "JSONValue is not a string type");
        return _store.str;
    }

    /// ditto
    @property string str(return scope string v) nothrow return @safe // TODO make @safe
    {
        assign!true(v);
        return v;
    }

    /**
     * Returns the JSONType of the value stored in this structure.
     */
    pragma(inline, true)
    @property JSONType type() const @nogc nothrow pure @safe
    {
        return _type;
    }

public:
    static union Store
    {
        size_t[2] dummy; // First member to be initialized to all zero
        long integer;
        double floating;
        string str;
        JSONValue[] array;
        Dictionary!(string, JSONValue) object;
    }

    version(JSONCommentStore) string comment;

private:
    auto ref JSONValue asJSONValue(T)(return auto ref T arg)
    {
        static if (is(T : JSONValue))
            return arg;
        else
            return JSONValue(arg);
    }

    void assign(bool byAssign, T)(T arg)
    {
        static if (byAssign)
            nullify();

        static if (is(T : typeof(null)))
        {
            _type = JSONType.null_;
        }
        else static if (is(T : string))
        {
            _store = Store(str: arg);
            _type = JSONType.string;
        }
        // https://issues.dlang.org/show_bug.cgi?id=15884
        else static if (isSomeString!T)
        {
            Appender!string strV;
            strV.put(arg.byUTF!char);
            _store = Store(str: strV.data);
            _type = JSONType.string;
        }
        else static if (is(T : bool))
        {
            _type = arg ? JSONType.true_ : JSONType.false_;
        }
        else static if (isIntegral!T)
        {
            _store = Store(integer: arg);
            _type = JSONType.integer;
        }
        else static if (isFloatingPoint!T)
        {
            _store = Store(floating: arg);
            _type = JSONType.float_;
        }
        else static if (is(T : Dictionary!(Key, Value), Key, Value))
        {
            static assert(is(Key : string), "Dictionary key must be string");

            static if (is(Value : JSONValue))
            {
                _store = Store(object: arg);
            }
            else
            {
                auto newArg = Dictionary!(string, JSONValue)(arg.length + 5, arg.length);
                foreach (k, ref v; arg)
                    newArg[k] = JSONValue(v);
                _store = Store(object: newArg);
            }
            _type = JSONType.object;
        }
        else static if (is(T : Value[Key], Key, Value))
        {
            static assert(is(Key : string), "Associative Array key must be string");

            static if (is(Value : JSONValue))
            {
                auto newArg = arg.asAA();
            }
            else
            {
                auto newArg = Dictionary!(string, JSONValue)(arg.length + 5, arg.length);
                foreach (k, ref v; arg)
                    newArg[k] = JSONValue(v);
            }
            _store = Store(object: newArg);
            _type = JSONType.object;
        }
        else static if (isArray!T)
        {
            static if (is(ElementEncodingType!T : JSONValue))
            {
                _store = Store(array: arg);
            }
            else
            {
                JSONValue[] newArg = new JSONValue[arg.length];
                foreach (i, ref v; arg)
                    newArg[i] = JSONValue(v);
                _store = Store(array: newArg);
            }
            _type = JSONType.array;
        }
        else static if (is(T : JSONValue))
        {
            this._store = arg._store;
            this._type = arg._type;
            version(JSONCommentStore) this.comment = arg.comment;
        }
        else
        {
            static assert(false, `Unable to convert type "` ~ fullyQualifiedName!T ~ `" to json value`);
        }
    }

    void assignRef(bool byAssign, T)(ref T arg)
    if (isStaticArray!T)
    {
        static if (byAssign)
            nullify();

        static if (is(ElementEncodingType!T : JSONValue))
        {
            _store = Store(array: arg);
        }
        else
        {
            JSONValue[] newArg = new JSONValue[arg.length];
            foreach (i, ref e; arg)
                newArg[i] = JSONValue(e);
            _store = Store(array: newArg);
        }
        _type = JSONType.array;
    }

package:
    Store _store;
    JSONType _type;
}


private:

///
@safe unittest // Constructor
{
    JSONValue j = ["language": "D"];

    // get value
    assert(j["language"].str == "D");

    // change existing key to new string
    j["language"].str = "Perl";
    assert(j["language"].str == "Perl");
}

///
@safe unittest // Constructor
{
    import std.exception : assertThrown;

    JSONValue j = true;
    assert(j.boolean == true);

    j.boolean = false;
    assert(j.boolean == false);

    j.integer = 12;
    assertThrown!JSONException(j.boolean);
}

///
@safe unittest // Constructor
{
    JSONValue j = JSONValue("a string");
    j = JSONValue(42);

    j = JSONValue([1, 2, 3]);
    assert(j.type == JSONType.array);

    j = JSONValue(["language": "D"]);
    assert(j.type == JSONType.object);
}

///
unittest // emptyObject
{
    JSONValue obj1 = JSONValue.emptyObject;
    assert(obj1.type == JSONType.object);
    obj1.object["a"] = JSONValue(1);
    assert(obj1.object["a"] == JSONValue(1));

    JSONValue obj2 = JSONValue.emptyObject;
    assert("a" !in obj2.object);
    obj2.object["b"] = JSONValue(5);
    assert(obj1 != obj2);
}

///
unittest // emptyArray
{
    JSONValue arr1 = JSONValue.emptyArray;
    assert(arr1.type == JSONType.array);
    assert(arr1.array.length == 0);
    arr1.array ~= JSONValue("Hello");
    assert(arr1.array.length == 1);
    assert(arr1.array[0] == JSONValue("Hello"));

    JSONValue arr2 = JSONValue.emptyArray;
    assert(arr2.array.length == 0);
    assert(arr1 != arr2);
}

///
@safe unittest // Constructor + JSONValue.array
{
    JSONValue j = JSONValue([42, 43, 44]);
    assert(j[0].integer == 42);
    assert(j[1].integer == 43);
}

///
@safe unittest // Constructor + JSONValue.object
{
    JSONValue j = JSONValue(["language": "D"]);
    assert(j["language"].str == "D");
}

///
@safe unittest // Constructor + JSONValue.array
{
    JSONValue j = JSONValue(["Perl", "C"]);
    j[1].str = "D";
    assert(j[1].str == "D");
}

///
@safe unittest // Constructor + JSONValue.object
{
    JSONValue j = JSONValue(["language": "D"]);
    j["language"].str = "Perl";
    assert(j["language"].str == "Perl");
}

///
@safe unittest // JSONValue.in
{
    JSONValue j = ["language": "D", "author": "walter"];
    string a = ("author" in j).str;
    *("author" in j) = "Walter";
    assert(j["author"].str == "Walter");
}

///
@safe unittest // JSONValue.opEquals
{
    assert(JSONValue(10).opEquals(JSONValue(10.0)));
    assert(JSONValue(10) != (JSONValue(10.5)));

    assert(JSONValue(1) != JSONValue(true));
    assert(JSONValue.emptyArray != JSONValue.emptyObject);

    assert(parseJSON(`{"a": 1, "b": 2}`).opEquals(parseJSON(`{"b": 2, "a": 1}`)));
}

///
unittest
{
    import std.conv : to;

    // parse a file or string of json into a usable structure
    string s = `{ "language": "D", "rating": 3.5, "code": "42" }`;
    JSONValue j = parseJSON(s);
    // j and j["language"] return JSONValue,
    // j["language"].str returns a string
    assert(j["language"].str == "D");
    assert(j["rating"].floating == 3.5);

    // check a type
    long x;
    if (const(JSONValue)* code = "code" in j)
    {
        if (code.type() == JSONType.integer)
            x = code.integer;
        else
            x = to!int(code.str);
    }

    // create a json struct
    JSONValue jj = [ "language": "D" ];
    // rating doesnt exist yet, so use .object to assign
    jj.object["rating"] = JSONValue(3.5);
    // create an array to assign to list
    jj.object["list"] = JSONValue( ["a", "b", "c"] );
    // list already exists, so .object optional
    jj["list"].array ~= JSONValue("D");

    string jjStr = `{"language":"D","rating":3.5,"list":["a","b","c","D"]}`;
    assert(jj.toString == jjStr, jj.toString);
}

///
@safe unittest // parse
{
    string s;
    JSONValue j, language;

    s = `{ "language": "D" }`;
    j = parseJSON(s);
    assert(j.type == JSONType.object);
    language = j["language"];
    assert(language.type == JSONType.string);
    assert(language.str == "D");

    s = `{ "language": "D \" \\ \/ \b \f \n \r \t D" }`;
    j = parseJSON(s);
    assert(j.type == JSONType.object);
    language = j["language"];
    assert(language.type == JSONType.string);
    assert(language.str == "D \" \\ / \b \f \n \r \t D");
}

///
@safe unittest // parse
{
    import std.exception;
    import std.conv;

    string s =
    `{
        "a": 123,
        "b": 3.1415,
        "c": "text",
        "d": true,
        "e": [1, 2, 3],
        "f": { "a": 1 },
        "g": -45,
        "h": ` ~ long.max.to!string ~ `,
     }`;

    struct a { }

    auto json = parseJSON(s);
    assert(json["a"].get!double == 123.0);
    assert(json["a"].get!int == 123);
    assert(json["a"].get!uint == 123);
    assert(json["b"].get!double == 3.1415);
    //assertThrown!JSONException(json["b"].get!int);
    assert(json["b"].get!int == 3); // same cast behavior as double
    assert(json["c"].get!string == "text");
    assert(json["d"].get!bool == true);
    assertNotThrown(json["e"].get!(JSONValue[]));
    assertNotThrown(json["f"].get!(JSONValue[string]));
    static assert(!__traits(compiles, json["a"].get!a));
    assertThrown!JSONException(json["e"].get!float);
    assertThrown!JSONException(json["d"].get!(JSONValue[string]));
    assertThrown!JSONException(json["f"].get!(JSONValue[]));
    assert(json["g"].get!int == -45);
    assertThrown!JSONException(json["g"].get!uint);
    assert(json["h"].get!long == long.max);
    assertThrown!JSONException(json["h"].get!uint);
    assertNotThrown(json["h"].get!float);
}

@safe unittest // CTFE parse
{
    enum issue15742objectOfObject = `{ "key1": { "key2": 1 }}`;
    static assert(parseJSON(issue15742objectOfObject).type == JSONType.object);

    enum issue15742arrayOfArray = `[[1]]`;
    static assert(parseJSON(issue15742arrayOfArray).type == JSONType.array);
}

@safe unittest // parse
{
    // Ensure we can parse and use JSON from @safe code
    auto a = `{ "key1": { "key2": 1 }}`.parseJSON;
    assert(a["key1"]["key2"].integer == 1);
    assert(a.toString == `{"key1":{"key2":1}}`);
}

@system unittest // parse
{
    // Ensure we can parse JSON from a @system range.
    struct Range
    {
    nothrow:

        string s;
        size_t index;
        @system
        {
            bool empty() { return index >= s.length; }
            void popFront() { index++; }
            char front() { return s[index]; }
        }
    }
    auto s = Range(`{ "key1": { "key2": 1 }}`);
    auto json = parseJSON(s);
    assert(json["key1"]["key2"].integer == 1);
}

// https://issues.dlang.org/show_bug.cgi?id=20527
@safe unittest
{
    static assert(parseJSON(`{"a" : 2}`)["a"].integer == 2);
}

// https://issues.dlang.org/show_bug.cgi?id=20874
@system unittest
{
    static struct MyCustomType
    {
        public string toString () const @system { return null; }
        alias toString this;
    }

    static struct B
    {
        public JSONValue asJSON() const @system { return JSONValue.init; }
        alias asJSON this;
    }

    if (false) // Just checking attributes
    {
        JSONValue json;
        MyCustomType ilovedlang;
        json = ilovedlang;
        json["foo"] = ilovedlang;
        auto s = ilovedlang in json;

        B b;
        json ~= b;
        json ~ b;
    }
}

// https://issues.dlang.org/show_bug.cgi?id=12897
@safe unittest
{
    JSONValue jv0 = JSONValue("test测试");
    assert(toJSON(jv0, JSONOptions.escapeNonAsciiChars) == `"test\u6D4B\u8BD5"`);
    JSONValue jv00 = JSONValue("test\u6D4B\u8BD5");
    assert(toJSON(jv00, JSONOptions.none) == `"test测试"`);
    assert(toJSON(jv0, JSONOptions.none) == `"test测试"`);
    JSONValue jv1 = JSONValue("été");
    assert(toJSON(jv1, JSONOptions.escapeNonAsciiChars) == `"\u00E9t\u00E9"`);
    JSONValue jv11 = JSONValue("\u00E9t\u00E9");
    assert(toJSON(jv11, JSONOptions.none) == `"été"`);
    assert(toJSON(jv1, JSONOptions.none) == `"été"`);
}

// https://issues.dlang.org/show_bug.cgi?id=20511
@system unittest
{
    import std.format.write : formattedWrite;
    import std.range : nullSink, outputRangeObject;

    outputRangeObject!(const(char)[])(nullSink)
        .formattedWrite!"%s"(JSONValue.init);
}

// Issue 16432 - JSON incorrectly parses to string
@safe unittest
{
    // Floating points numbers are rounded to the nearest integer and thus get
    // incorrectly parsed

    import std.math.operations : isClose;

    string s = "{\"rating\": 3.0 }";
    JSONValue j = parseJSON(s);
    assert(j["rating"].type == JSONType.float_);
    j = j.toString.parseJSON;
    assert(j["rating"].type == JSONType.float_);
    assert(isClose(j["rating"].floating, 3.0));

    s = "{\"rating\": -3.0 }";
    j = parseJSON(s);
    assert(j["rating"].type == JSONType.float_);
    j = j.toString.parseJSON;
    assert(j["rating"].type == JSONType.float_);
    assert(isClose(j["rating"].floating, -3.0));

    // https://issues.dlang.org/show_bug.cgi?id=13660
    auto jv1 = JSONValue(4.0);
    auto textual = jv1.toString();
    auto jv2 = parseJSON(textual);
    assert(jv1.type == JSONType.float_);
    assert(textual == "4.0");
    assert(jv2.type == JSONType.float_);
}

@safe unittest
{
    // Adapted from https://github.com/dlang/phobos/pull/5005
    // Result from toString is not checked here, because this
    // might differ (%e-like or %f-like output) depending
    // on OS and compiler optimization.
    import std.math.operations : isClose;

    string json;

    // test positive extreme values
    JSONValue j;
    j["rating"] = 1e18 - 65;
    json = j.toString;
    assert(isClose(json.parseJSON["rating"].floating, 1e18 - 65), json);

    j["rating"] = 1e18 - 64;
    json = j.toString;
    assert(isClose(json.parseJSON["rating"].floating, 1e18 - 64), json);

    // negative extreme values
    j["rating"] = -1e18 + 65;
    json = j.toString;
    assert(isClose(json.parseJSON["rating"].floating, -1e18 + 65), json);

    j["rating"] = -1e18 + 64;
    json = j.toString;
    assert(isClose(json.parseJSON["rating"].floating, -1e18 + 64), json);
}

@system unittest
{
    import std.exception;
    JSONValue jv = "123";
    assert(jv.type == JSONType.string);
    assertNotThrown(jv.str);
    assertThrown!JSONException(jv.integer);
    assertThrown!JSONException(jv.floating);
    assertThrown!JSONException(jv.object);
    assertThrown!JSONException(jv.array);
    assertThrown!JSONException(jv["aa"]);
    assertThrown!JSONException(jv[2]);

    jv = -3;
    assert(jv.type == JSONType.integer);
    assertNotThrown(jv.integer);

    jv = 3.0;
    assert(jv.type == JSONType.float_);
    assertNotThrown(jv.floating);

    jv = ["key" : "value"];
    assert(jv.type == JSONType.object);
    assertNotThrown(jv.object);
    assertNotThrown(jv["key"]);
    assert("key" in jv);
    assert("notAnElement" !in jv);
    assertThrown!JSONException(jv["notAnElement"]);
    const cjv = jv;
    assert("key" in cjv);
    assertThrown!JSONException(cjv["notAnElement"]);

    foreach (string key, value; jv)
    {
        static assert(is(typeof(value) == JSONValue));
        assert(key == "key");
        assert(value.type == JSONType.string);
        assertNotThrown(value.str);
        assert(value.str == "value");
    }

    jv = [3, 4, 5];
    assert(jv.type == JSONType.array);
    assertNotThrown(jv.array);
    assertNotThrown(jv[2]);
    foreach (size_t index, value; jv)
    {
        static assert(is(typeof(value) == JSONValue));
        assert(value.type == JSONType.integer);
        assertNotThrown(value.integer);
        assert(index == (value.integer-3));
    }

    jv = null;
    assert(jv.type == JSONType.null_);
    assert(jv.isNull);
    jv = "foo";
    assert(!jv.isNull);

    jv = JSONValue("value");
    assert(jv.type == JSONType.string);
    assert(jv.str == "value");

    JSONValue jv2 = JSONValue("value");
    assert(jv2.type == JSONType.string);
    assert(jv2.str == "value");

    JSONValue jv3 = JSONValue("\u001c");
    assert(jv3.type == JSONType.string);
    assert(jv3.str == "\u001C");
}

// https://issues.dlang.org/show_bug.cgi?id=11504
@system unittest
{
    JSONValue jv = 1;
    assert(jv.type == JSONType.integer);

    jv.str = "123";
    assert(jv.type == JSONType.string);
    assert(jv.str == "123");

    jv.integer = 1;
    assert(jv.type == JSONType.integer);
    assert(jv.integer == 1);

    jv.floating = 1.5;
    assert(jv.type == JSONType.float_);
    assert(jv.floating == 1.5);

    jv.object = ["key" : JSONValue("value")];
    assert(jv.type == JSONType.object);
    assert(jv.object.asAA == ["key" : JSONValue("value")]);

    jv.array = [JSONValue(1), JSONValue(2), JSONValue(3)];
    assert(jv.type == JSONType.array);
    assert(jv.array == [JSONValue(1), JSONValue(2), JSONValue(3)]);

    jv = true;
    assert(jv.type == JSONType.true_);

    jv = false;
    assert(jv.type == JSONType.false_);

    enum E{True = true}
    jv = E.True;
    assert(jv.type == JSONType.true_);
}

@system pure unittest
{
    // Adding new json element via array() / object() directly

    JSONValue jarr = JSONValue([10]);
    foreach (i; 0 .. 9)
        jarr.array ~= JSONValue(i);
    assert(jarr.array.length == 10);

    JSONValue jobj = JSONValue(["key" : JSONValue("value")]);
    foreach (i; 0 .. 9)
        jobj.object[text("key", i)] = JSONValue(text("value", i));
    assert(jobj.object.length == 10);
}

@system unittest /* pure */
{
    // Adding new json element without array() / object() access

    JSONValue jarr = JSONValue([10]);
    foreach (i; 0 .. 9)
        jarr ~= [JSONValue(i)];
    assert(jarr.array.length == 10);

    JSONValue jobj = JSONValue(["key" : JSONValue("value")]);
    foreach (i; 0 .. 9)
        jobj[text("key", i)] = JSONValue(text("value", i));
    assert(jobj.object.length == 10);

    // No array alias
    auto jarr2 = jarr ~ [1,2,3];
    jarr2[0] = 999;
    assert(jarr[0] == JSONValue(10));
}

@system unittest
{
    // @system because JSONValue.array is @system
    import std.exception;

    // An overly simple test suite, if it can parse a serializated string and
    // then use the resulting values tree to generate an identical
    // serialization, both the decoder and encoder works.

    auto jsons = [
        `null`,
        `true`,
        `false`,
        `0`,
        `123`,
        `-4321`,
        `0.25`,
        `-0.25`,
        `""`,
        `"hello\nworld"`,
        `"\"\\\/\b\f\n\r\t"`,
        `[]`,
        `[12,"foo",true,false]`,
        `{}`,
        `{"a":1,"b":null}`,
        `{"goodbye":[true,"or",false,["test",42,{"nested":{"a":23.5,"b":0.140625}}]],`
        ~`"hello":{"array":[12,null,{}],"json":"is great"}}`,
    ];

    enum dbl1_844 = `1.8446744073709568`;
    version (MinGW)
        jsons ~= dbl1_844 ~ `e+019`;
    else
        jsons ~= dbl1_844 ~ `e+19`;

    JSONValue val;
    string result;
    foreach (json; jsons)
    {
        try
        {
            val = parseJSON(json);
            result = toJSON(val);
            assert(result == json, text(result, " should be ", json));
        }
        catch (JSONException e)
        {
            import std.stdio : writefln;
            writefln(text(json, "\n", e.toString()));
        }
    }

    // Should be able to correctly interpret unicode entities
    val = parseJSON(`"\u003C\u003E"`);
    assert(toJSON(val) == "\"\&lt;\&gt;\"");
    assert(val.to!string() == "\"\&lt;\&gt;\"");
    val = parseJSON(`"\u0391\u0392\u0393"`);
    assert(toJSON(val) == "\"\&Alpha;\&Beta;\&Gamma;\"");
    assert(val.to!string() == "\"\&Alpha;\&Beta;\&Gamma;\"");
    val = parseJSON(`"\u2660\u2666"`);
    assert(toJSON(val) == "\"\&spades;\&diams;\"");
    assert(val.to!string() == "\"\&spades;\&diams;\"");

    //0x7F is a control character (see Unicode spec)
    val = parseJSON(`"\u007F"`);
    assert(toJSON(val) == "\"\\u007F\"");
    assert(val.to!string() == "\"\\u007F\"");

    with(parseJSON(`""`))
        assert(str == "", str);
    with(parseJSON(`[]`))
        assert(!array.length);

    // Formatting
    static immutable string expectedPretty =
`{
    "a": [
        null,
        {
            "x": 1
        },
        {},
        []
    ]
}`;
    val = parseJSON(`{"a":[null,{"x":1},{},[]]}`);
    auto valPretty = toJSON(val, JSONOptions.prettyString);
    assert(valPretty == expectedPretty, text('\n', valPretty, '\n', expectedPretty, '\n', valPretty.length, " vs ", expectedPretty.length));
}

@safe unittest
{
  auto json = `"hello\nworld"`;
  const jv = parseJSON(json);
  assert(jv.toString == json);
  assert(toJSON(jv, JSONOptions.prettyString) == json);
}

// https://issues.dlang.org/show_bug.cgi?id=12969
@system unittest /* pure */
{
    JSONValue jv;
    jv["int"] = 123;

    assert(jv.type == JSONType.object);
    assert("int" in jv);
    assert(jv["int"].integer == 123);

    jv["array"] = [1, 2, 3, 4, 5];

    assert(jv["array"].type == JSONType.array);
    assert(jv["array"][2].integer == 3);

    jv["str"] = "D language";
    assert(jv["str"].type == JSONType.string);
    assert(jv["str"].str == "D language");

    jv["bool"] = false;
    assert(jv["bool"].type == JSONType.false_);

    assert(jv.object.length == 4);

    jv = [5, 4, 3, 2, 1];
    assert(jv.type == JSONType.array);
    assert(jv[3].integer == 2);
}

@safe unittest
{
    auto s = q"EOF
[
  1,
  2,
  3,
  potato
]
EOF";

    import std.exception;

    auto e = collectException!JSONException(parseJSON(s));
    if (defaultOptions & JSONOptions.json5)
        assert(e.msg == "JSON - Unexpected text found 'potato' (5:3)", e.msg);
    else
        assert(e.msg == "JSON - Unexpected character 'p' (5:3)", e.msg);
}

// handling of special float values (NaN, Inf, -Inf)
@safe unittest
{
    import std.exception : assertThrown;
    import std.math.traits : isNaN, isInfinity;

    // expected representations of NaN and Inf
    enum
    {
        nanString         = '"' ~ JSONLiteral.pnan ~ '"',
        infString         = '"' ~ JSONLiteral.pinf ~ '"',
        negativeInfString = '"' ~ JSONLiteral.ninf ~ '"',
    }

    // with the specialFloatLiterals option, encode NaN/Inf as strings
    assert(JSONValue(float.nan).toString(JSONOptions.specialFloatLiterals)       == nanString);
    assert(JSONValue(double.infinity).toString(JSONOptions.specialFloatLiterals) == infString);
    assert(JSONValue(-real.infinity).toString(JSONOptions.specialFloatLiterals)  == negativeInfString);

    // without the specialFloatLiterals option, throw on encoding NaN/Inf
    assertThrown!JSONException(JSONValue(float.nan).toString(JSONOptions.none));
    assertThrown!JSONException(JSONValue(double.infinity).toString(JSONOptions.none));
    assertThrown!JSONException(JSONValue(-real.infinity).toString(JSONOptions.none));

    // when parsing json with specialFloatLiterals option, decode special strings as floats
    JSONValue jvNan    = parseJSON!(JSONOptions.specialFloatLiterals)(nanString);
    JSONValue jvInf    = parseJSON!(JSONOptions.specialFloatLiterals)(infString);
    JSONValue jvNegInf = parseJSON!(JSONOptions.specialFloatLiterals)(negativeInfString);

    assert(jvNan.floating.isNaN);
    assert(jvInf.floating.isInfinity    && jvInf.floating > 0);
    assert(jvNegInf.floating.isInfinity && jvNegInf.floating < 0);

    // when parsing json without the specialFloatLiterals option, decode special strings as strings
    jvNan    = parseJSON!(JSONOptions.none)(nanString);
    jvInf    = parseJSON!(JSONOptions.none)(infString);
    jvNegInf = parseJSON!(JSONOptions.none)(negativeInfString);

    assert(jvNan.str    == JSONLiteral.pnan);
    assert(jvInf.str    == JSONLiteral.pinf);
    assert(jvNegInf.str == JSONLiteral.ninf);
}

@safe unittest /* @nogc nothrow pure */
{
    JSONValue testVal;
    testVal = "test";
    testVal = 10;
    testVal = 10u;
    testVal = 1.0;
    testVal = (JSONValue[string]).init;
    testVal = JSONValue[].init;
    testVal = null;
    assert(testVal.isNull);
}

// https://issues.dlang.org/show_bug.cgi?id=15884
nothrow @safe unittest /* pure */
{
    import std.typecons;
    void Test(C)() {
        C[] a = ['x'];
        JSONValue testVal = a;
        assert(testVal.type == JSONType.string);
        testVal = a.idup;
        assert(testVal.type == JSONType.string);
    }
    Test!char();
    Test!wchar();
    Test!dchar();
}

// https://issues.dlang.org/show_bug.cgi?id=15885
@safe unittest
{
    enum bool realInDoublePrecision = real.mant_dig == double.mant_dig;

    static bool test(const double num0)
    {
        import std.math.operations : feqrel;
        const json0 = JSONValue(num0);
        const num1 = to!double(toJSON(json0));
        static if (realInDoublePrecision)
            return feqrel(num1, num0) >= (double.mant_dig - 1);
        else
            return num1 == num0;
    }

    assert(test( 0.23));
    assert(test(-0.23));
    assert(test(1.223e+24));
    assert(test(23.4));
    assert(test(0.0012));
    assert(test(30738.22));

    assert(test(1 + double.epsilon));
    assert(test(double.min_normal));
    static if (realInDoublePrecision)
        assert(test(-double.max / 2));
    else
        assert(test(-double.max));

    const minSub = double.min_normal * double.epsilon;
    assert(test(minSub));
    assert(test(3*minSub));
}

// https://issues.dlang.org/show_bug.cgi?id=17555
@safe unittest
{
    import std.exception : assertThrown;

    assertThrown!JSONException(parseJSON("\"a\nb\""));
}

// https://issues.dlang.org/show_bug.cgi?id=17556
@safe unittest
{
    auto v = JSONValue("\U0001D11E");
    auto j = toJSON(v, JSONOptions.escapeNonAsciiChars);
    assert(j == `"\uD834\uDD1E"`);
}

// https://issues.dlang.org/show_bug.cgi?id=5904
@safe unittest
{
    string s = `"\uD834\uDD1E"`;
    auto j = parseJSON(s);
    assert(j.str == "\U0001D11E");
}

// https://issues.dlang.org/show_bug.cgi?id=17557
@safe unittest
{
    assert(parseJSON("\"\xFF\"").str == "\xFF");
    assert(parseJSON("\"\U0001D11E\"").str == "\U0001D11E");
}

// https://issues.dlang.org/show_bug.cgi?id=17553
@safe unittest
{
    auto v = JSONValue("\xFF");
    assert(toJSON(v) == "\"\xFF\"");
}

@safe unittest
{
    import std.utf;
    assert(parseJSON("\"\xFF\"".byChar).str == "\xFF");
    assert(parseJSON("\"\U0001D11E\"".byChar).str == "\U0001D11E");
}

// JSONOptions.doNotEscapeSlashes (https://issues.dlang.org/show_bug.cgi?id=17587)
@safe unittest
{
    assert(parseJSON(`"/"`).toString == `"\/"`);
    assert(parseJSON(`"\/"`).toString == `"\/"`);
    assert(parseJSON(`"/"`).toString(JSONOptions.doNotEscapeSlash) == `"/"`);
    assert(parseJSON(`"\/"`).toString(JSONOptions.doNotEscapeSlash) == `"/"`);
}

// JSONOptions.strictParsing (https://issues.dlang.org/show_bug.cgi?id=16639)
@safe unittest
{
    import std.exception : assertThrown;

    // Unescaped ASCII NULs
    assert(parseJSON("[\0]").type == JSONType.array);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("[\0]", ));
    assert(parseJSON("\"\0\"").str == "\0");
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("\"\0\""));

    // Unescaped ASCII DEL (0x7f) in strings
    assert(parseJSON("\"\x7f\"").str == "\x7f");
    assert(parseJSON!(JSONOptions.strictParsing)("\"\x7f\"").str == "\x7f");

    // "true", "false", "null" case sensitivity
    assert(parseJSON("true").type == JSONType.true_);
    assert(parseJSON!(JSONOptions.strictParsing)("true").type == JSONType.true_);
    assert(parseJSON("True").type == JSONType.true_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("True"));
    assert(parseJSON("tRUE").type == JSONType.true_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("tRUE"));

    assert(parseJSON("false").type == JSONType.false_);
    assert(parseJSON!(JSONOptions.strictParsing)("false").type == JSONType.false_);
    assert(parseJSON("False").type == JSONType.false_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("False"));
    assert(parseJSON("fALSE").type == JSONType.false_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("fALSE"));

    assert(parseJSON("null").type == JSONType.null_);
    assert(parseJSON("null", JSONOptions.strictParsing).type == JSONType.null_);
    assert(parseJSON("Null").type == JSONType.null_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("Null"));
    assert(parseJSON("nULL").type == JSONType.null_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("nULL"));

    // Whitespace characters
    assert(parseJSON("[\f\v]").type == JSONType.array);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("[\f\v]"));
    assert(parseJSON("[ \t\r\n]").type == JSONType.array);
    assert(parseJSON!(JSONOptions.strictParsing)("[ \t\r\n]").type == JSONType.array);

    // Empty input
    assert(parseJSON("").type == JSONType.null_);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)(""));

    // Numbers with leading '0's
    assert(parseJSON("01").integer == 1);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("01"));
    assert(parseJSON("-01").integer == -1);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("-01"));
    assert(parseJSON("0.01").floating == 0.01);
    assert(parseJSON!(JSONOptions.strictParsing)("0.01").floating == 0.01);
    assert(parseJSON("0e1").floating == 0);
    assert(parseJSON!(JSONOptions.strictParsing)("0e1").floating == 0);

    // Trailing characters after JSON value
    // No longer compatible with std.json - assert(parseJSON(`""asdf`).str == "");
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)(`""asdf`));
    // No longer compatible with std.json - assert(parseJSON("987\0").integer == 987);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("987\0"));
    // No longer compatible with std.json - assert(parseJSON("987\0\0").integer == 987);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("987\0\0"));
    // No longer compatible with std.json - assert(parseJSON("[]]").type == JSONType.array);
    assertThrown!JSONException(parseJSON!(JSONOptions.strictParsing)("[]]"));
    assert(parseJSON("123 \t\r\n").integer == 123); // Trailing whitespace is OK
    assert(parseJSON!(JSONOptions.strictParsing)("123 \t\r\n").integer == 123);
}

@system unittest // Trailing comma in array
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.exception : assertThrown;

    string s = `{ "a" : [1,2,3,], }`;
    JSONValue j = parseJSON(s);
    assert(j["a"].array().map!(i => i.integer()).array == [1,2,3]);

    assertThrown(parseJSON!(JSONOptions.strictParsing)(s));
}

@system unittest // Trailing comma in object
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.exception : assertThrown;

    string s = `{ "a" : { }  , }`;
    JSONValue j = parseJSON(s);
    assert("a" in j);
    auto t = j["a"].object();
    assert(t.empty);

    assertThrown(parseJSON!(JSONOptions.strictParsing)(s));
}

// https://issues.dlang.org/show_bug.cgi?id=20330
@safe unittest
{
    string s = `{"a":[1,2,3]}`;
    JSONValue j = parseJSON(s);
    auto json = j.toString();
    assert(json == s, json);
}

// https://issues.dlang.org/show_bug.cgi?id=20330
@safe unittest
{
    string expectedPretty =
`{
    "a": [
        1,
        2,
        3
    ]
}`;
    JSONValue j = parseJSON(expectedPretty);
    auto prettyJSON = j.toString(JSONOptions.prettyString);
    assert(prettyJSON == expectedPretty, text('\n', prettyJSON, '\n', expectedPretty, '\n', prettyJSON.length, " vs ", expectedPretty.length));
}

// https://issues.dlang.org/show_bug.cgi?id=24823
@safe unittest
{
    string s = `{"b":2,"a":1}`;
    JSONValue j = parseJSON(s);
    auto json = j.toString();
    assert(json == s, json);
}

@safe unittest
{
    bool[JSONValue] aa;
    aa[JSONValue("test")] = true;
    assert(parseJSON(`"test"`) in aa);
    assert(parseJSON(`"boo"`) !in aa);

    aa[JSONValue(int(5))] = true;
    assert(JSONValue(int(5)) in aa);
    assert(JSONValue(uint(5)) in aa);
}

unittest // prettyString + objectName
{
    string expectedPretty =
`{
    a: [
        1,
        2,
        3
    ],
    b: "abc"
}`;

    JSONValue json = parseJSON!(defaultOptions)(expectedPretty);
    auto prettyJSON = json.toString(optionsOf([JSONOptions.objectName], defaultPrettyOptions));
    assert(prettyJSON == expectedPretty, text('\n', prettyJSON, '\n', expectedPretty, '\n', diffLoc(prettyJSON, expectedPretty)));
}

version(JSONCommentStore)
unittest // comment
{
    string expectedPretty =
`{
    /* First comment line */
    "a": [
        1,
        2,
        3
    ],
    /* First
       Second
       Third */
    "b": "abc"
}`;

    JSONValue json = parseJSON!(defaultOptions)(expectedPretty);
    auto prettyJSON = json.toString(defaultPrettyOptions);
    assert(prettyJSON == expectedPretty, text('\n', prettyJSON, '\n', expectedPretty, '\n', diffLoc(prettyJSON, expectedPretty)));
}

version(JSONCommentStore)
unittest // comment + prettyString + objectName
{
    string expectedPretty =
`{
    /* First comment line */
    a: [
        1,
        2,
        3
    ],
    /* First
       Second
       Third */
    b: "abc",
    f1: NaN,
    f2: -NaN,
    f3: Infinity,
    f4: -Infinity
}`;

    JSONValue json = parseJSON!(defaultOptions)(expectedPretty);
    auto prettyJSON = json.toString(optionsOf([JSONOptions.objectName], defaultPrettyOptions));
    assert(prettyJSON == expectedPretty, text('\n', prettyJSON, '\n', expectedPretty, '\n', diffLoc(prettyJSON, expectedPretty)));
}
