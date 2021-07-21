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

module pham.db.value;

import std.math : isNaN;
import std.range.primitives: ElementType;
import std.traits : isArrayT = isArray, Unqual;

version (profile) import pham.utl.test : PerfFunction;
public import pham.utl.variant : Variant;
import pham.db.type;
import pham.db.convert;

struct DbValue
{
public:
    this(T)(T value, DbType typeIf = DbType.unknown) nothrow @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        doAssign!(T, false)(value, typeIf);
    }

    ref typeof(this) opAssign(T)(T rhs) nothrow return @safe
    {
        doAssign!(T, true)(rhs, DbType.unknown);
        return this;
    }

    bool opCast(C: bool)() const nothrow @safe
    {
        return !isNull;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbValue opCast(T)() const nothrow
    if (is(Unqual!T == DbValue))
    {
        return this;
    }

    bool opEquals(ref DbValue other)
    {
        return type == other.type && value == other.value;
    }

    static typeof(this) dbNull(DbType type = DbType.unknown) nothrow @safe
    {
        typeof(this) result;
        result._type = type;
        return result;
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        _value.nullify();
    }

    static typeof(this) entity(T)(T value, DbType type) nothrow
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong))
    {
        typeof(this) result;
        result._value = value;
        result._type = type;
        return result;
    }

    // Replace type with dbType
    void nullify(DbType typeIf = DbType.unknown) nothrow @safe
    {
        this._value.nullify();
        if (typeIf != DbType.unknown)
            this._type = typeIf;
    }

    void setEntity(T)(T value, DbType type) nothrow
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong))
    {
        this._value = value;
        this._type = type;
    }

    /**
     * Set value as array of a DbType value
     */
    @property ref typeof(this) elementType(DbType value) nothrow return @safe
    {
        _type = DbType.array | value;
        return this;
    }

    @property bool isArray() const nothrow @safe
    {
        return (_type & DbType.array) != 0;
    }

    @property bool isNull() const nothrow @safe
    {
        return _value.isNull;
    }

    /**
     * Returns indicator if value can return its' size
     */
    @property bool hasSize() const nothrow @safe
    {
        return isDbTypeHasSize(type) || isArray;
    }

    /**
     * Gets the DbType of the value
     */
    @property DbType type() const nothrow @safe
    {
        return cast(DbType)(_type & 0x7FFF_FFFF); // Exclude array marker
    }

    @property ref typeof(this) type(DbType value) nothrow return @safe
    {
        _type = isArray ? value | DbType.array : value;
        return this;
    }

    /**
     * Gets maximum size, in bytes of the value
     * used for chars, string, json, xml, binary, struct and array types.
     */
    @property int32 size() @safe
    {
        return hasSize ? cast(int32)value.length : 0;
    }

    @property Variant value() @safe
    {
        return _value;
    }

    @property void value(Variant value) nothrow @safe
    {
        this._value = value;
    }

public:
    alias value this;

package(pham.db):
    Variant _value;
    DbType _type;

private:
    void doAssign(T, bool Assign)(T rhs, DbType rhsTypeIf) nothrow @safe
    {
        alias UT = Unqual!T;

        static if (typeid(T) is typeid(null))
        {
            // Do not reset _type to keep track of type, just value
            if (rhsTypeIf != DbType.unknown)
                this._type = rhsTypeIf;
            this._value.nullify();
        }
        else static if (is(UT == bool))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.boolean;
            this._value = rhs;
        }
        else static if (is(UT == byte))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int8;
            this._value = rhs;
        }
        else static if (is(UT == ubyte) || is(UT == short))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int16;
            this._value = cast(short)rhs;
        }
        else static if (is(UT == ushort) || is(UT == int))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int32;
            this._value = cast(int)rhs;
        }
        else static if (is(UT == uint) || is(UT == long) || is(UT == ulong))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int64;
            this._value = cast(long)rhs;
        }
        else static if (is(UT == float))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float32;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
        }
        else static if (is(UT == double))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float64;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
        }
        else static if (is(UT == real))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float64;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = cast(double)rhs;
        }
        else static if (is(UT == Date))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.date;
            this._value = rhs;
        }
        else static if (is(UT == DbDateTime))
        {
            this._type = rhsTypeIf != DbType.unknown
                ? rhsTypeIf
                : (rhs.isTZ ? DbType.datetimeTZ : DbType.datetime);
            this._value = rhs;
        }
        else static if (is(UT == DbTime))
        {
            this._type = rhsTypeIf != DbType.unknown
                ? rhsTypeIf
                : (rhs.isTZ ? DbType.timeTZ : DbType.time);
            this._value = rhs;
        }
        // Map to DbDateTime
        else static if (is(UT == DateTime))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.datetime;
            this._value = DbDateTime(rhs, 0, rhs.kind);
        }
        // Map to DbTime
        else static if (is(UT == Time))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.time;
            this._value = DbTime(rhs);
        }
        else static if (is(UT == UUID))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.uuid;
            this._value = rhs;
        }
        else static if (is(UT == char) || is(UT == wchar) || is(UT == dchar))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.chars;
            this._value = toString(rhs);
        }
        else static if (is(T == string))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.string;
            this._value = rhs;
        }
        else static if (is(T == wstring) || is(T == dstring))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.string;
            this._value = toString(rhs);
        }
        else static if (is(UT == char[]))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.chars;
            this._value = rhs;
        }
        else static if (is(UT == ubyte[]))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.binary;
            this._value = rhs;
        }
        else static if (is(UT == Decimal32))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal32;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
        }
        else static if (is(UT == Decimal64))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal64;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
        }
        else static if (is(UT == Decimal128))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal128;
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
        }
        else static if (is(UT == BigInteger))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int128;
            this._value = rhs;
        }
        else static if (is(UT == DbValue))
        {
            this._type = rhs._type;
            this._value = rhs._value;
            return;
        }
        else static if (is(T == struct))
        {
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.record;
            this._value = rhs;
        }
        else static if (isArrayT!T)
        {
            alias E = ElementType!T;
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : (DbType.array | dbTypeOf!E());
            this._value = rhs;
        }
        else
            static assert(0, "Not supported type: " ~ T.stringof);
    }
}

struct DbRowValue
{
public:
    this(size_t columnLength) nothrow @safe
    {
        // Allow empty row
        if (columnLength)
            this.columns.length = columnLength;
    }

    bool opCast(C: bool)() const nothrow @safe
    {
        return length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbRowValue opCast(T)() nothrow @safe
    if (is(Unqual!T == DbRowValue))
    {
        return this;
    }

    size_t opDollar() const nothrow @safe
    {
        return length;
    }

    ref DbValue opIndex(size_t index) nothrow return @safe
    in
    {
        assert(index < length);
    }
    do
    {
        return columns[index];
    }

    ref typeof(this) opIndexAssign(DbValue value, size_t index) return @safe
    in
    {
        assert(index < length);
    }
    do
    {
        columns[index] = value;
        return this;
    }

    DbValue[] opSlice() nothrow return @safe
    {
        return columns;
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        if (columns)
        {
            foreach (ref c; columns)
                c.nullify();
            columns = null;
        }
    }

    void nullify() nothrow @safe
    {
        foreach (ref c; columns)
            c.nullify();
    }

    @property size_t length() const nothrow @safe
    {
        return columns.length;
    }

private:
    DbValue[] columns;
}

struct DbRowValueQueue
{
public:
    @disable this(this);

    bool opCast(To: bool)() const nothrow @safe
    {
        return _length != 0;
    }

    void clear() nothrow @safe
    {
        while (length)
            dequeueItem();
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        clearItems(head);
        clearItems(pools);
        tail = null;
        _length = 0;
    }

    DbRowValue dequeue() nothrow @safe
    in
    {
        assert(length != 0);
    }
    do
    {
        auto resultItem = dequeueItem();
        return resultItem.value;
    }

    void enqueue(ref DbRowValue row) nothrow @safe
    {
        auto newRow = newItem(row);
        if (tail is null)
        {
            head = newRow;
            tail = newRow;
        }
        else
        {
            tail.next = newRow;
            tail = newRow;
        }
        _length++;
    }

    alias put = enqueue;

    @property bool empty() const nothrow @safe
    {
        return _length == 0;
    }

    @property ref DbRowValue front() nothrow return @safe
    in
    {
        assert(length != 0);
    }
    do
    {
        return head.value;
    }

    @property size_t length() const nothrow @safe
    {
        return _length;
    }

private:
    DbRowValueQueueItem dequeueItem() nothrow @safe
    in
    {
        assert(length != 0);
    }
    do
    {
        assert(head !is null);

        auto result = head;

        // Unhook from queue
        head = result.next;
        if (--_length == 0)
            tail = null;

        // Cache the instant for next use
        if (pools is null)
            result.next = null;
        else
            result.next = pools;
        pools = result;

        return result;
    }

    DbRowValueQueueItem newItem(ref DbRowValue row) nothrow @safe
    {
        if (pools is null)
            return new DbRowValueQueueItem(row);
        else
        {
            auto result = pools;
            pools = result.next;
            result.next = null;
            result.value = row;
            return result;
        }
    }

    void clearItems(ref DbRowValueQueueItem items) nothrow @safe
    {
        while (items !is null)
        {
            auto temp = items;
            items = temp.next;
            temp.value.nullify();
            temp.next = null;
        }
    }

    DbRowValueQueueItem head;
    DbRowValueQueueItem tail;
    DbRowValueQueueItem pools;
    size_t _length;
}

private class DbRowValueQueueItem
{
public:
    this(ref DbRowValue value) nothrow @safe
    {
        this.value = value;
        this.next = null;
    }

public:
    DbRowValue value;
    DbRowValueQueueItem next;
}


// Any below codes are private
private:

unittest // DbValue
{
    import pham.utl.test;
    traceUnitTest("unittest db.value.DbValue");

    DbValue vb = DbValue(true);
    assert(vb.value == true);
    assert(vb.type == DbType.boolean);

    DbValue vc = DbValue('x');
    assert(vc.value == "x");
    assert(vc.type == DbType.chars);

    DbValue vi8 = DbValue(byte.max);
    assert(vi8.value == byte.max);
    assert(vi8.type == DbType.int8);

    DbValue vi16 = DbValue(ubyte.max);
    assert(vi16.value == ubyte.max);
    assert(vi16.type == DbType.int16);
    vi16 = DbValue(short.max);
    assert(vi16.value == short.max);
    assert(vi16.type == DbType.int16);

    DbValue vi32 = DbValue(ushort.max);
    assert(vi32.value == ushort.max);
    assert(vi32.type == DbType.int32);
    vi32 = DbValue(int.max);
    assert(vi32.value == int.max);
    assert(vi32.type == DbType.int32);

    DbValue vi64 = DbValue(uint.max);
    assert(vi64.value == uint.max);
    assert(vi64.type == DbType.int64);
    vi64 = DbValue(long.min);
    assert(vi64.value == long.min);
    assert(vi64.type == DbType.int64);
    vi64 = DbValue(1234567890uL);
    assert(vi64.value == 1234567890L);
    assert(vi64.type == DbType.int64);

    DbValue vf32 = DbValue(float.max);
    assert(vf32.value == float.max);
    assert(vf32.type == DbType.float32);

    DbValue vf64 = DbValue(double.max);
    assert(vf64.value == double.max);
    assert(vf64.type == DbType.float64);

    DbValue vs = DbValue("this is a string");
    assert(vs.value == "this is a string");
    assert(vs.type == DbType.string);

    DbValue vsw = DbValue("this is a wstring"w);
    assert(vsw.value == "this is a wstring");
    assert(vsw.type == DbType.string);

    DbValue vsd = DbValue("this is a dstring"d);
    assert(vsd.value == "this is a dstring");
    assert(vsd.type == DbType.string);

    ubyte[] bi = [1,2,3];
    DbValue vbi = DbValue(bi);
    assert(vbi.value == cast(ubyte[])[1,2,3]);
    assert(vbi.type == DbType.binary);
}
