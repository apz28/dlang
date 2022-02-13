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
public import pham.utl.variant : Variant, VariantType;
import pham.db.type;
import pham.db.convert;

struct DbValue
{
public:
    this(DbType type) nothrow @safe
    {
        this._type = type;
    }

    this(T)(T value, DbType type = DbType.unknown) nothrow @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        this._type = type;
        doAssign!(T, false)(value);
    }

    ref typeof(this) opAssign(T)(T rhs) nothrow return @safe
    {
        doAssign!(T, true)(rhs);
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

    bool opEquals(ref DbValue rhs)
    {
        return type == rhs.type && value == rhs.value;
    }

    static DbValue dbNull(DbType dbType = DbType.unknown) nothrow @safe
    {
        return DbValue(dbType);
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        _value.nullify();
    }

    static DbValue entity(T)(T value, DbType type) nothrow
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong))
    {
        return DbValue(value, type);
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

    @property bool isArray() const nothrow pure @safe
    {
        return (_type & DbType.array) != 0;
    }

    @property bool isNull() const nothrow pure @safe
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
     * Gets maximum size, in bytes of the value
     * used for chars, string, json, xml, binary, struct and array types.
     */
    @property int32 size() @safe
    {
        return hasSize ? cast(int32)value.length : 0;
    }

    /**
     * Gets the DbType of the value
     */
    @property DbType type() const nothrow @safe
    {
        return cast(DbType)(_type & DbTypeMask);
    }

    @property ref typeof(this) type(DbType value) nothrow return @safe
    {
        _type = isArray ? (value | DbType.array) : value;
        return this;
    }

    @property Variant value() @safe
    {
        return _value;
    }

    @property void value(Variant value) nothrow @safe
    {
        doAssignVariant(value);
    }

public:
    alias value this;

package(pham.db):
    Variant _value;
    DbType _type;

private:
    void doAssign(T, bool Assign)(T rhs) nothrow @safe
    {
        alias UT = Unqual!T;

        static if (typeid(T) is typeid(null))
        {
            this._value.nullify();
            version (DbValueTypeSet)
            if (rhsTypeIf != DbType.unknown)
                this._type = rhsTypeIf;
        }
        else static if (is(UT == bool))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.boolean;
        }
        else static if (is(UT == byte))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int8;
        }
        else static if (is(UT == ubyte) || is(UT == short))
        {
            this._value = cast(short)rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int16;
        }
        else static if (is(UT == ushort) || is(UT == int))
        {
            this._value = cast(int)rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int32;
        }
        else static if (is(UT == uint) || is(UT == long) || is(UT == ulong))
        {
            this._value = cast(long)rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int64;
        }
        else static if (is(UT == float))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float32;
        }
        else static if (is(UT == double))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float64;
        }
        else static if (is(UT == real))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = cast(double)rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.float64;
        }
        else static if (is(UT == Date))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.date;
        }
        else static if (is(UT == DbDateTime))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : (rhs.isTZ ? DbType.datetimeTZ : DbType.datetime);
        }
        else static if (is(UT == DbTime))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : (rhs.isTZ ? DbType.timeTZ : DbType.time);
        }
        // Map to DbDateTime
        else static if (is(UT == DateTime))
        {
            this._value = DbDateTime(rhs, 0, rhs.kind);
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.datetime;
        }
        // Map to DbTime
        else static if (is(UT == Time))
        {
            this._value = DbTime(rhs);
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.time;
        }
        else static if (is(UT == UUID))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.uuid;
        }
        else static if (is(UT == char) || is(UT == wchar) || is(UT == dchar))
        {
            this._value = toString(rhs);
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.chars;
        }
        else static if (is(T == string))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.string;
        }
        else static if (is(T == wstring) || is(T == dstring))
        {
            this._value = toString(rhs);
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.string;
        }
        else static if (is(UT == char[]))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.chars;
        }
        else static if (is(UT == ubyte[]))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.binary;
        }
        else static if (is(UT == Decimal32))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal32;
        }
        else static if (is(UT == Decimal64))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal64;
        }
        else static if (is(UT == Decimal128))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.decimal128;
        }
        else static if (is(UT == BigInteger))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.int128;
        }
        else static if (is(UT == DbValue))
        {
            this._value = rhs._value;
            this._type = rhs._type;
        }
        else static if (is(T == struct))
        {
            this._value = rhs;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : DbType.record;
        }
        else static if (isArrayT!T)
        {
            this._value = rhs;
            version (DbValueTypeSet) alias E = ElementType!T;
            version (DbValueTypeSet)
            this._type = rhsTypeIf != DbType.unknown ? rhsTypeIf : (DbType.array | dbTypeOf!E());
        }
        else
            static assert(0, "Not supported type: " ~ T.stringof);
    }

    void doAssignVariant(Variant rhs) nothrow @safe
    {
        this._value = rhs;
        version (DbValueTypeSet)
        {
            if (rhsTypeIf != DbType.unknown)
                this._type = rhsTypeIf;
            else
            {
                final switch (rhs.variantType)
                {
                    case VariantType.null_:
                        break;
                    case VariantType.boolean:
                        this._type = DbType.boolean;
                        break;
                    case VariantType.character:
                    // TODO convert to string
                        this._type = DbType.chars;
                        break;
                    case VariantType.integer:
                        this._type = DbType.int32;
                    // TODO for int16, int64 ....
                        break;
                    case VariantType.float_:
                        this._type = DbType.float64;
                    // TODO for float32, real ....
                        break;
                    case VariantType.enum_:
                        this._type = DbType.int32;
                        break;
                    case VariantType.string:
                        this._type = DbType.string;
                    // TODO for wstring & dstring
                        break;
                    case VariantType.staticArray:
                    case VariantType.dynamicArray:
                        // TODO this._type = (DbType.array | dbTypeOf!E());
                        break;
                    case VariantType.struct_:
                        this._type = DbType.record;
                        break;
                    case VariantType.associativeArray:
                    case VariantType.class_:
                    case VariantType.interface_:
                    case VariantType.union_:
                    case VariantType.delegate_:
                    case VariantType.function_:
                    case VariantType.pointer:
                    case VariantType.unknown:
                        this._value.nullify();
                        this._type = DbType.unknown;
                        break;
                }
            }
        }
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
        return !empty;
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

    DbValue[] opIndex() nothrow return @safe
    {
        return columns;
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

    @property bool empty() const nothrow @safe
    {
        return columns.length == 0;
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
    traceUnitTest!("pham.db.database")("unittest pham.db.value.DbValue");

    DbValue vb = DbValue(true);
    assert(vb.value == true);
    version (DbValueTypeSet) assert(vb.type == DbType.boolean);

    DbValue vc = DbValue('x');
    assert(vc.value == "x");
    version (DbValueTypeSet) assert(vc.type == DbType.chars);

    DbValue vi8 = DbValue(byte.max);
    assert(vi8.value == byte.max);
    version (DbValueTypeSet) assert(vi8.type == DbType.int8);

    DbValue vi16 = DbValue(ubyte.max);
    assert(vi16.value == ubyte.max);
    version (DbValueTypeSet) assert(vi16.type == DbType.int16);
    vi16 = DbValue(short.max);
    assert(vi16.value == short.max);
    version (DbValueTypeSet) assert(vi16.type == DbType.int16);

    DbValue vi32 = DbValue(ushort.max);
    assert(vi32.value == ushort.max);
    version (DbValueTypeSet) assert(vi32.type == DbType.int32);
    vi32 = DbValue(int.max);
    assert(vi32.value == int.max);
    version (DbValueTypeSet) assert(vi32.type == DbType.int32);

    DbValue vi64 = DbValue(uint.max);
    assert(vi64.value == uint.max);
    version (DbValueTypeSet) assert(vi64.type == DbType.int64);
    vi64 = DbValue(long.min);
    assert(vi64.value == long.min);
    version (DbValueTypeSet) assert(vi64.type == DbType.int64);
    vi64 = DbValue(1234567890uL);
    assert(vi64.value == 1234567890L);
    version (DbValueTypeSet) assert(vi64.type == DbType.int64);

    DbValue vf32 = DbValue(float.max);
    assert(vf32.value == float.max);
    version (DbValueTypeSet) assert(vf32.type == DbType.float32);

    DbValue vf64 = DbValue(double.max);
    assert(vf64.value == double.max);
    version (DbValueTypeSet) assert(vf64.type == DbType.float64);

    DbValue vs = DbValue("this is a string");
    assert(vs.value == "this is a string");
    version (DbValueTypeSet) assert(vs.type == DbType.string);

    DbValue vsw = DbValue("this is a wstring"w);
    assert(vsw.value == "this is a wstring");
    version (DbValueTypeSet) assert(vsw.type == DbType.string);

    DbValue vsd = DbValue("this is a dstring"d);
    assert(vsd.value == "this is a dstring");
    version (DbValueTypeSet) assert(vsd.type == DbType.string);

    ubyte[] bi = [1,2,3];
    DbValue vbi = DbValue(bi);
    assert(vbi.value == cast(ubyte[])[1,2,3]);
    version (DbValueTypeSet) assert(vbi.type == DbType.binary);
}
