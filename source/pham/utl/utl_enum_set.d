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

module pham.utl.enum_set;

import std.conv : to;
import std.exception : assumeWontThrow;
import std.meta : allSatisfy;
import std.traits : EnumMembers, isIntegral, Unqual;

nothrow @safe:

/**
 * Count members of an enum type, E
 * Params:
 *  E = an enum type
 * Returns:
 *  Number of members in E enum
 * Ex:
 *  enum E {e1, e2, e3}
 *  count!E() returns 3
 */
size_t count(E)() pure
if (is(E == enum))
{
    size_t result;
    foreach (i; EnumMembers!E)
        result++;
    return result;
}

/**
 * Detect whether an enum is of integral type and has distinct bit flag values
 * Ex:
 *  enum E {e1 = 1 << 0, e2 = 1 << 1, ...}
 */
template isBitEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isBitEnum = (E.min > 0) &&
        {
            ulong values;
            foreach (i; EnumMembers!E)
            {
                if ((values & i) != 0)
                    return false;
                values |= i;
            }
            return count!E <= maxBits();
        }();
    }
    else
    {
        enum isBitEnum = false;
    }
}

/**
 * Detect whether an enum is of integral type and has increasing values
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 */
template isOrderedEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isOrderedEnum =
        {
            auto prev = E.min;
            foreach (i; EnumMembers!E)
            {
                if (i != E.min && i <= prev)
                    return false;
                prev = i;
            }
            return count!E <= maxBits();
        }();
    }
    else
    {
        enum isOrderedEnum = false;
    }
}

/**
 * Detect whether an enum is of integral type and has increasing sequence values
 * Ex:
 *  enum E {e1 = 0, e2 = 1, e3 = 2, ...}
 */
template isSequenceEnum(E)
{
    static if (is(E Base == enum) && isIntegral!Base)
    {
        enum isSequenceEnum = (E.min >= 0) &&
        {
            auto prev = E.min;
            foreach (i; EnumMembers!E)
            {
                if (i != E.min && i != prev + 1)
                    return false;
                prev = i;
            }
            return E.max < maxBits() && count!E <= maxBits();
        }();
    }
    else
    {
        enum isSequenceEnum = false;
    }
}

/**
 * Check if an enum, E, can be used in enum set
 */
template isEnumSet(E)
{
    enum isEnumSet =
    {
        return isBitEnum!E || isOrderedEnum!E || isSequenceEnum!E;
    }();
}

/**
 * Define a simple enum set fit in 32/64 bit integral
 */
template EnumSetType(E)
if (isEnumSet!E)
{
    static if (isBitEnum!E)
    {
        static if (E.max <= uint.max)
            alias EnumSetType = uint;
        else
            alias EnumSetType = ulong;
    }
    else
    {
        static if (count!E() <= uint.sizeof * 8)
            alias EnumSetType = uint;
        else
            alias EnumSetType = ulong;
    }
}

/**
 * Return the bit mask for an enum, value
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 *  bit!E(e3) returns 4
 */
auto bit(E)(E value) pure
if (isEnumSet!E)
{
    static if (isBitEnum!E)
        return value;
    else static if (isSequenceEnum!E)
        return cast(EnumSetType!E)1 << value;
    else
    {
        size_t at;
        foreach (e; EnumMembers!E)
        {
            if (e == value)
                return cast(EnumSetType!E)1 << at;
            at++;
        }
        assert(0);
    }
}

/**
 * Return order value of an enum, value
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 *  ord!E(e3) returns 2
 */
size_t ord(E)(E value) pure
if (isEnumSet!E)
{
    static if (isSequenceEnum!E)
        return value;
    else
    {
        size_t at;
        foreach (e; EnumMembers!E)
        {
            if (e == value)
                return at;
            at++;
        }
        assert(0);
    }
}

/**
 * Convert a string, value, to it E enum presentation
 * Assume that value is a valid/matching value
 * Params:
 *  value = a string to be converted
 *  emptyValue = a result if value is empty
 * Returns:
 *  if value is empty, return enum emptyValue
 *  otherwise return the enum that matches value
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 *  toEnum!E("e3") returns e3
 *  toEnum!E("", e2) returns e2
 */
E toEnum(E)(string value, E emptyValue = E.init) pure
if (is(E Base == enum))
{
    return value.length != 0 ? assumeWontThrow(to!E(value)) : emptyValue;
}

/**
 * Convert an enum to its string presentation
 * Params:
 *  value = an enum to be converted
 * Returns:
 *  a string for parameter value
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 *  toName!E(e3) returns "e3"
 */
string toName(E)(E value) pure
if (is(E Base == enum))
{
    return assumeWontThrow(to!string(value));
}

/**
 * Define a simple enum set struct that fit in 32/64 bit integral
 */
struct EnumSet(E)
if (isEnumSet!E)
{
nothrow @safe:

public:
    enum size = count!E();

public:
    static struct EnumSetRange
    {
    nothrow @safe:

    public:
        this(EnumSet!E values) pure
        {
            if (!values.empty)
            {
                foreach (e; EnumMembers!E)
                {
                    if (values.on(e))
                        this._values[this._length++] = e;
                }
            }
        }

        void popBack()
        {
            --_length;
        }

        void popFront()
        {
            ++_index;
        }

        auto save()
        {
            return this;
        }

        @property E back()
        in
        {
            assert(!empty);
        }
        do
        {
            return _values[_length - 1];
        }

        @property bool empty() const
        {
            return _index >= _length;
        }

        @property E front()
        in
        {
            assert(!empty);
        }
        do
        {
            return _values[_index];
        }

    private:
        E[size] _values;
        size_t _index, _length;
    }

public:
    this(E value) pure
    {
        this._values = bit(value);
    }

    this(scope const(E)[] values) pure
    {
        this._values = 0;
        foreach (e; values)
            this._values |= bit(e);
    }

    this(V...)(scope V values) pure
    if (allSatisfy!(isEnumSet, V))
    {
        this._values = 0;
        foreach (e; values)
            this._values |= bit(e);
    }

    bool opCast(C: bool)() const pure
    {
        return _values != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    EnumSet!E opCast(T)() const
    if (is(Unqual!T == EnumSet!E))
    {
        return this;
    }

    ref typeof(this) opAssign(E value) pure return
    {
        this._values = bit(value);
        return this;
    }

    ref typeof(this) opAssign(const(E)[] values) pure return
    {
        this._values = 0;
        foreach (e; values)
            this._values |= bit(e);
        return this;
    }

    ref typeof(this) opAssign(V...)(V values) pure return
    if (allSatisfy!(isEnumSet, V))
    {
        this._values = 0;
        foreach (e; values)
            this._values |= bit(e);
        return this;
    }

    ref typeof(this) opOpAssign(string op)(E value) pure return
    if (op == "^" || op == "-" || op == "|" || op == "+")
    {
        static if (op == "^" || op == "-")
            _values &= ~bit(value);
        else static if (op == "|" || op == "+")
            _values |= bit(value);
        else
            static assert(0);

        return this;
    }

    ref typeof(this) opOpAssign(string op)(EnumSet!E source) pure return
    if (op == "^" || op == "-" || op == "|" || op == "+" || op == "&" || op == "*")
    {
        static if (op == "^" || op == "-")
            _values &= ~source.values;
        else static if (op == "|" || op == "+")
            _values |= source.values;
        else static if (op == "&" || op == "*")
            _values &= source.values;
        else
            static assert(0);

        return this;
    }

    typeof(this) opBinary(string op)(E value) const pure
    if (op == "^" || op == "-" || op == "|" || op == "+")
    {
        EnumSet!E res = this;
        return res.opOpAssign!op(value);
    }

    typeof(this) opBinary(string op)(EnumSet!E source) const pure
    if (op == "^" || op == "-" || op == "|" || op == "+" || op == "&" || op == "*")
    {
        EnumSet!E res = this;
        return res.opOpAssign!op(source);
    }

    bool opBinaryRight(string op : "in")(E value) const pure
    {
        return on(value);
    }

    bool opEquals()(auto const ref EnumSet!E source) const pure
    {
        return _values == source.values;
    }

    EnumSetRange opSlice() return
    {
        return EnumSetRange(this);
    }

    ref typeof(this) exclude(E value) pure return
    {
        return opOpAssign!"-"(value);
    }

    ref typeof(this) include(E value) pure return
    {
        return opOpAssign!"+"(value);
    }

    pragma (inline, true)
    bool any(scope const(E)[] source) const pure
    {
        foreach (i; source)
        {
            if (on(i))
                return true;
        }
        return false;
    }

    bool any(V...)(scope V source) const pure
    if (allSatisfy!(isEnumSet, V))
    {
        foreach (e; source)
        {
            if (on(e))
                return true;
        }
        return false;
    }

    pragma (inline, true)
    bool off(E value) const pure
    {
        return _values == 0 || (_values & bit(value)) == 0;
    }

    pragma (inline, true)
    bool on(E value) const pure
    {
        return _values != 0 && (_values & bit(value)) != 0;
    }

    ref typeof(this) reset() pure return
    {
        _values = 0;
        return this;
    }

    ref typeof(this) set(E value, bool isSet) pure return
    {
        if (isSet)
            return opOpAssign!"+"(value);
        else
            return opOpAssign!"-"(value);
    }

    /**
     * Defines the set from a string representation
     * Params:
     *  values = a string representing one or several E members separated by comma
     * Returns:
     *  Number of failed to convert from a member string
     */
    size_t fromString(scope const(char)[] values) pure
    {
        import std.ascii : isWhite;
        import std.conv : to;

        this._values = 0;

        size_t fails, pos;
        size_t len = values.length;

        // Skip trailing spaces
        while (len > pos && isWhite(values[len - 1]))
            --len;

        // Skip trailing set indicator?
        if (pos < len && values[len - 1] == ']')
            --len;

        // Skip preceeding spaces
        bool skipSpaces()
        {
            while (pos < len && isWhite(values[pos]))
                pos++;
            return pos < len;
        }

        // Skip preceeding set indicator?
        if (skipSpaces() && values[pos] == '[')
            pos++;

        // Empty set?
        if (pos >= len)
            return 0;

        while (skipSpaces())
        {
            // Get the begin and end position for the string element
            const begin = pos;
            size_t lastSpace = size_t.max;
            while (pos < len && values[pos] != ',')
            {
                if (isWhite(values[pos]))
                {
                    if (lastSpace == size_t.max)
                        lastSpace = pos;
                }
                else if (lastSpace != size_t.max)
                    lastSpace = size_t.max;
                pos++;
            }

            // Get the string element
            auto value = values[begin..lastSpace == size_t.max ? pos : lastSpace];

            // Skip comma
            pos++;

            try
            {
                auto toValue = to!E(value);
                include(toValue);
             }
             catch (Exception e)
             {
                 fails++;
             }
        }

        return fails;
    }

    ulong toHash() const pure
    {
        return _values;
    }

    /**
     * Returns the string representation of the set
     */
    string toString() const
    {
        import std.array : Appender;

        if (empty)
            return "[]";

        size_t count;
        auto res = Appender!string();
        res.reserve(500);
        res.put('[');
        foreach(e; EnumMembers!E)
        {
            if (on(e))
            {
                if (count++ != 0)
                    res.put(',');
                res.put(toName(e));
            }
        }
        res.put(']');
        return res.data;
    }

    @property bool empty() const pure
    {
        return _values == 0;
    }

    @property EnumSetType!E values() const pure
    {
        return _values;
    }

private:
    EnumSetType!E _values;
}

/**
 * Define a static array with length of number of enum values
 */
struct EnumArray(E, T)
if (isEnumSet!E)
{
nothrow @safe:

public:
    enum size = count!E();

    static struct EnumArrayEntry
    {
    nothrow @safe:

    public:
        this(E e, T v) pure
        {
            this.e = e;
            this.v = v;
        }

    public:
        T v;
        E e;
    }

public:
    this(V...)(V values)
    if (allSatisfy!(isEntry, V))
    {
        foreach (i; values)
            this._values[ord(i.e)] = i.v;
    }

    /**
     * Returns value for enum, i
     */
    T opIndex(E i) inout
    {
        return _values[ord(i)];
    }

    /**
     * Assigns value for enum i
     */
    ref typeof(this) opIndexAssign(T value, E i) return
    {
        this._values[ord(i)] = value;
        return this;
    }

    /**
     * Returns value for an enum by its name
     */
    T opDispatch(string enumName)()
    {
        import std.conv : to;

        enum e = enumName.to!E;
        return _values[ord(e)];
    }

    /**
     * Assigns value for enum name, enumName
     */
    T opDispatch(string enumName)(T value)
    {
        import std.conv : to;

        enum e = enumName.to!E;
        return _values[ord(e)] = value;
    }

    /**
     * Returns true if value exists in this array
     */
    bool exist(T value) const
    {
        foreach (i; EnumMembers!E)
        {
            if (_values[ord(i)] == value)
                return true;
        }

        return false;
    }

    /**
     * Returns enum for its associated value
     * If the value is not exists, returns defaultValue
     */
    E get(T value, E defaultValue = E.min) const
    {
        foreach (i; EnumMembers!E)
        {
            if (_values[ord(i)] == value)
                return i;
        }

        return defaultValue;
    }

    /**
     * Length of this enum array
     */
    @property size_t length() const pure
    {
        return size;
    }

private:
    enum isEntry(TEntry) = is(TEntry == EnumArrayEntry);
    T[size] _values;
}


// Any below codes are private
private:


size_t maxBits() pure
{
    return ulong.sizeof * 8;
}

nothrow @safe unittest // toEnum
{
    import pham.utl.utltest;
    traceUnitTest("unittest utl.enum_set.toEnum");

    enum EnumTestOrder
    {
        one,
        two,
        three
    }

    assert(toEnum!EnumTestOrder("") == EnumTestOrder.one);
    assert(toEnum!EnumTestOrder("", EnumTestOrder.two) == EnumTestOrder.two);
    assert(toEnum!EnumTestOrder("one") == EnumTestOrder.one);
    assert(toEnum!EnumTestOrder("two") == EnumTestOrder.two);
    assert(toEnum!EnumTestOrder("three") == EnumTestOrder.three);
}

nothrow @safe unittest // toName
{
    import pham.utl.utltest;
    traceUnitTest("unittest utl.enum_set.toName");

    enum EnumTestOrder : byte
    {
        one,
        two,
        three
    }

    assert(toName(EnumTestOrder.one) == "one");
    assert(toName(EnumTestOrder.two) == "two");
    assert(toName(EnumTestOrder.three) == "three");
}

nothrow @safe unittest // EnumSet
{
    import std.traits : OriginalType;
    import pham.utl.utltest;
    traceUnitTest("unittest utl.enum_set.EnumSet");

    //pragma(msg, size_t.sizeof * 8, '.', size_t.max);

    void Test(E)(string values)
    {
        alias EnumTestSet = EnumSet!E;

        EnumTestSet testFlags;

        assert(testFlags.values == 0);
        foreach (i; EnumMembers!E)
        {
            assert(testFlags.off(i));
            assert(!testFlags.on(i));
            assert(!(i in testFlags));
        }

        testFlags.include(E.one);
        assert(testFlags.on(E.one));
        assert(testFlags.off(E.two));
        assert(testFlags.off(E.three));

        testFlags.include(E.two);
        assert(testFlags.on(E.two));
        assert(testFlags.on(E.one));
        assert(testFlags.off(E.three));

        testFlags.include(E.three);
        assert(testFlags.on(E.three));

        assert(testFlags.values != 0);
        foreach (i; EnumMembers!E)
        {
            assert(!testFlags.off(i));
            assert(testFlags.on(i));
        }
        assert(testFlags.toString() == values, testFlags.toString());

        testFlags.exclude(E.one);
        assert(testFlags.off(E.one));
        assert(testFlags.on(E.two));
        assert(testFlags.on(E.three));

        testFlags.exclude(E.two);
        assert(testFlags.off(E.two));
        assert(testFlags.off(E.two));
        assert(testFlags.on(E.three));

        testFlags.exclude(E.three);
        assert(testFlags.off(E.three));

        assert(testFlags.values == 0);
        foreach (i; EnumMembers!E)
        {
            assert(testFlags.off(i));
            assert(!testFlags.on(i));
        }
        assert(testFlags.toString() == "[]", testFlags.toString());

        assert(testFlags.fromString(values) == 0);
        assert(testFlags.toString() == values, testFlags.toString());

        EnumTestSet testFlag1s = EnumTestSet(E.one, E.three);
        EnumTestSet testFlag2s = EnumTestSet(E.two, E.three);
        assert(testFlag1s != testFlag2s);

        EnumTestSet testFlag3s = testFlag1s * testFlag2s;
        assert(testFlag3s.toString() == "[three]", testFlag3s.toString());

        testFlag3s = testFlag1s + testFlag2s;
        assert(testFlag3s.toString() == "[one,two,three]", testFlag3s.toString());

        testFlag3s = testFlag1s - testFlag2s;
        assert(testFlag3s.toString() == "[one]", testFlag3s.toString());
    }

    enum EnumTestOrder
    {
        one = 1,
        two = 3,
        three = 32
    }

    /*
    pragma(msg,
        "EnumTestSkip ", EnumSetType!EnumTestOrder,
        ", min: ", EnumTestOrder.min + 0,
        ", max: ", EnumTestOrder.max + 0,
        ", count: ", count!EnumTestOrder(),
        ", isEnumSet: ", isEnumSet!(EnumTestOrder),
        ", OriginalType: ", OriginalType!EnumTestOrder);
    */

    static assert(!isBitEnum!EnumTestOrder);
    static assert(!isSequenceEnum!EnumTestOrder);
    Test!EnumTestOrder("[one,two,three]");


    enum EnumTestSequence
    {
        one,
        two,
        three
    }

    /*
    pragma(msg,
        "EnumTestSequence ", EnumSetType!EnumTestSequence,
        ", min: ", EnumTestSequence.min + 0,
        ", max: ", EnumTestSequence.max + 0,
        ", count: ", count!EnumTestSequence(),
        ", isEnumSet: ", isEnumSet!(EnumTestSequence),
        ", OriginalType: ", OriginalType!EnumTestSequence);
    */

    Test!EnumTestSequence("[one,two,three]");

    enum EnumTestBit
    {
        one = 1 << 0,
        two = 1 << 1,
        three = 1 << 2
    }

    /*
    pragma(msg,
        "EnumTestBit ", EnumSetType!EnumTestBit,
        ", min: ", EnumTestBit.min + 0,
        ", max: ", EnumTestBit.max + 0,
        ", count: ", count!EnumTestBit(),
        ", isEnumSet: ", isEnumSet!(EnumTestBit),
        ", OriginalType: ", OriginalType!EnumTestBit);
    */

    Test!EnumTestBit("[one,two,three]");


    enum EnumTestLimit1
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32
    }
    static assert(isEnumSet!EnumTestLimit1);
    static assert(is(EnumSetType!EnumTestLimit1 == uint));

    enum EnumTestLimit2
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32, b33, b34, b35, b36, b37, b38, b39, b40,
        b41, b42, b43, b44, b45, b46, b47, b48, b49, b50,
        b51, b52, b53, b54, b55, b56, b57, b58, b59, b60,
        b61, b62, b63, b64
    }
    static assert(isEnumSet!EnumTestLimit2);
    static assert(is(EnumSetType!EnumTestLimit2 == ulong));

    enum EnumTestFailOverSequence
    {
        b1=60,
        b2=61,
        b3=62,
        b4=63,
        b5=64
    }
    static assert(!isSequenceEnum!EnumTestFailOverSequence);

    enum EnumTestFailOverElement
    {
        b1, b2, b3, b4, b5, b6, b7, b8, b9, b0,
        b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
        b21, b22, b23, b24, b25, b26, b27, b28, b29, b30,
        b31, b32, b33, b34, b35, b36, b37, b38, b39, b40,
        b41, b42, b43, b44, b45, b46, b47, b48, b49, b50,
        b51, b52, b53, b54, b55, b56, b57, b58, b59, b60,
        b61, b62, b63, b64, b65
    }
    static assert(!isEnumSet!EnumTestFailOverElement);
}

nothrow @safe unittest // EnumArray
{
    import pham.utl.utltest;
    traceUnitTest("unittest utl.enum_set.EnumArray");

    enum EnumTest
    {
        one,
        two,
        max
    }

    alias EnumTestInt = EnumArray!(EnumTest, int);

    EnumTestInt testInt = EnumTestInt(
        EnumTestInt.EnumArrayEntry(EnumTest.one, 1),
        EnumTestInt.EnumArrayEntry(EnumTest.two, 2),
        EnumTestInt.EnumArrayEntry(EnumTest.max, int.max)
    );

    assert(testInt.one == 1);
    assert(testInt.two == 2);
    assert(testInt.max == int.max);

    assert(testInt[EnumTest.one] == 1);
    assert(testInt[EnumTest.two] == 2);
    assert(testInt[EnumTest.max] == int.max);

    assert(testInt.get(1) == EnumTest.one);
    assert(testInt.get(2) == EnumTest.two);
    assert(testInt.get(int.max) == EnumTest.max);

    // Unknown -> return default min
    assert(!testInt.exist(3));
    assert(testInt.get(3) == EnumTest.min);


    alias EnumTestString = EnumArray!(EnumTest, string);

    EnumTestString testString = EnumTestString(
        EnumTestString.EnumArrayEntry(EnumTest.one, "1"),
        EnumTestString.EnumArrayEntry(EnumTest.two, "2"),
        EnumTestString.EnumArrayEntry(EnumTest.max, "int.max")
    );

    assert(testString[EnumTest.one] == "1");
    assert(testString[EnumTest.two] == "2");
    assert(testString[EnumTest.max] == "int.max");

    assert(testString.get("1") == EnumTest.one);
    assert(testString.get("2") == EnumTest.two);
    assert(testString.get("int.max") == EnumTest.max);

    // Unknown -> return default min
    assert(!testString.exist("3"));
    assert(testString.get("3") == EnumTest.min);
}
