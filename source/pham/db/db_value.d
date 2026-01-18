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

module pham.db.db_value;

import std.conv : to;
import std.math : isNaN;
import std.range.primitives: ElementType;
import std.traits : isArrayT = isArray, Unqual;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_result : ResultCode;
import pham.var.var_coerce;
import pham.var.var_coerce_dec_decimal;
import pham.var.var_coerce_pham_date_time;
import pham.var.var_variant : variantNoLengthMarker;
public import pham.var.var_variant : Variant, VariantType;
import pham.db.db_convert;
import pham.db.db_type;

alias valueNoSizeMarker = variantNoLengthMarker;

struct DbValue
{
public:
    this(DbType type) nothrow @safe
    {
        this._type = type;
    }

    this(T)(T value, DbType type = DbType.unknown) @safe
    {
        version(profile) debug auto p = PerfFunction.create();

        version(DbValueTypeSet)
        {
            if (type == DbType.unknown)
                doAssign!true(value);
            else
            {
                this._type = type;
                doAssign!false(value);
            }
        }
        else
        {
            this._type = type;
            doAssign!false(value);
        }
    }

    ref typeof(this) opAssign(T)(T rhs) return @safe
    {
        version(DbValueTypeSet)
        {
            if (this._type == DbType.unknown)
                doAssign!true(rhs);
            else
                doAssign!false(rhs);
        }
        else
            doAssign!false(rhs);
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

    bool opEquals(const DbValue rhs) const @safe
    {
        return this._type == rhs._type && this._value == rhs._value;
    }

    static DbValue dbNull(DbType dbType = DbType.unknown) nothrow @safe
    {
        auto result = DbValue(dbType);
        result.nullify();
        return result;
    }

    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        _value.nullify();
        _type = DbType.unknown;
        return ResultCode.ok;
    }

    static DbValue entity(T)(T value, DbType type) nothrow
    if (is(Unqual!T == int) || is(Unqual!T == uint) || is(Unqual!T == long) || is(Unqual!T == ulong))
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
    if (is(Unqual!T == int) || is(Unqual!T == uint) || is(Unqual!T == long) || is(Unqual!T == ulong))
    {
        this._value = value;
        this._type = type;
    }

    /**
     * Gets element DbType of an array value
     */
    @property DbType elementType() const nothrow pure @safe
    {
        return cast(DbType)(_type & DbTypeMask);
    }

    /**
     * Set element DbType of an array value
     */
    @property ref typeof(this) elementType(DbType value) nothrow return @safe
    {
        _type = DbType.array | value;
        return this;
    }

    /**
     * Returns indicator if value can return its' size
     */
    @property bool hasSize() const nothrow pure @safe
    {
        return isDbTypeHasSize(type) || isArray;
    }

    @property bool isArray() const nothrow pure @safe
    {
        return (_type & DbType.array) != 0;
    }

    @property bool isNull() const nothrow pure @safe
    {
        return _value.isNull || (isDbTypeHasZeroSizeAsNull(_type) && size == 0);
    }

    /**
     * Gets size or length of the value
     * chars, string, json, xml, binary and array types is length
     * struct is size
     * If instance does not have size, return valueNoSizeMarker (-1)
     */
    @property ptrdiff_t size() const nothrow pure @safe
    {
        return hasSize
            ? (_type == DbType.record ? _value.typeSize : _value.length)
            : valueNoSizeMarker;
    }

    /**
     * Gets the DbType of the value
     */
    @property DbType type() const nothrow pure @safe
    {
        return _type;
    }

    @property ref typeof(this) type(DbType value) nothrow pure return @safe
    {
        _type = value;
        return this;
    }

    @property Variant value() nothrow @safe
    {
        return _value;
    }

    @property void value(Variant value) nothrow @safe
    {
        version(DbValueTypeSet)
        {
            if (this._type == DbType.unknown)
                doAssignVariant!true(value);
            else
                doAssignVariant!false(value);
        }
        else
            doAssignVariant!false(value);
    }

    alias this = value;

package(pham.db):
    Variant _value;
    DbType _type;

private:
    void doAssign(bool setType, T)(T rhs) @safe
    {
        alias UT = Unqual!T;

        static if (typeid(T) is typeid(null))
        {
            this._value.nullify();
        }
        else static if (is(UT == bool))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == byte))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == ubyte) || is(UT == short))
        {
            this._value = cast(short)rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == ushort) || is(UT == int))
        {
            this._value = cast(int)rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == uint) || is(UT == long) || is(UT == ulong))
        {
            this._value = cast(long)rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == float))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == double))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == real))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = cast(double)rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == DbDate))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == DbDateTime))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == DbTime))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        // Map to DbDateTime
        else static if (is(UT == DateTime))
        {
            this._value = DbDateTime.toDbDateTime(rhs);
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        // Map to DbTime
        else static if (is(UT == Time))
        {
            this._value = DbTime.toDbTime(rhs);
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == UUID))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == char) || is(UT == wchar) || is(UT == dchar))
        {
            auto s = rhs.to!string();
            this._value = s;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(T == string))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(T == wstring) || is(T == dstring))
        {
            this._value = rhs.to!string();
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == char[]))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == ubyte[]))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == Decimal32))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == Decimal64))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == Decimal128))
        {
            if (rhs.isNaN)
                this._value.nullify();
            else
                this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == BigInteger))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (is(UT == DbValue))
        {
            this._value = rhs._value;
            this._type = rhs._type;
        }
        else static if (is(UT == struct))
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else static if (isArrayT!T)
        {
            this._value = rhs;
            static if (setType)
                this._type = dbTypeOf!UT();
        }
        else
            static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
    }

    void doAssignVariant(bool setType)(Variant rhs) nothrow @safe
    {
        this._value = rhs;

        static if (setType)
        {
            final switch (rhs.variantType)
            {
                case VariantType.null_:
                    break;
                case VariantType.boolean:
                    this._type = dbTypeOf!bool();
                    break;
                case VariantType.character:
                    this._type = dbTypeOf!char();
                    break;
                case VariantType.integer:
                    const variantTypeSize = rhs.typeSize;
                    this._type = variantTypeSize == 2
                        ? dbTypeOf!short
                        : (variantTypeSize == 4 ? dbTypeOf!int : dbTypeOf!long);
                    break;
                case VariantType.float_:
                    const variantTypeSize = rhs.typeSize;
                    this._type = variantTypeSize == 4 ? dbTypeOf!float : dbTypeOf!double;
                    break;
                case VariantType.enum_:
                    this._type = dbTypeOf!int;
                    break;
                case VariantType.string:
                    this._type = dbTypeOf.string;
                    // TODO convert wstring & dstring to string?
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
                    break;
            }
        }
    }
}

struct DbRowValue
{
public:
    this(size_t columnLength, size_t row) nothrow @safe
    {
        // Allow empty row
        if (columnLength)
            this._columnValues.length = columnLength;
        this._row = row;
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
        return _columnValues;
    }

    ref DbValue opIndex(size_t index) nothrow return @safe
    in
    {
        assert(index < length);
    }
    do
    {
        return _columnValues[index];
    }

    ref typeof(this) opIndexAssign(DbValue value, size_t index) return @safe
    in
    {
        assert(index < length);
    }
    do
    {
        _columnValues[index] = value;
        return this;
    }

    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        if (_columnValues)
        {
            foreach (ref c; _columnValues)
                c.nullify();
        }

        _columnValues = null;
        _row = 0;
        return ResultCode.ok;
    }

    void nullify() nothrow @safe
    {
        foreach (ref c; _columnValues)
            c.nullify();
    }

    @property bool empty() const nothrow @safe
    {
        return _columnValues.length == 0;
    }

    @property size_t length() const nothrow @safe
    {
        return _columnValues.length;
    }

    @property size_t row() const nothrow @safe
    {
        return _row;
    }

private:
    DbValue[] _columnValues;
    size_t _row;
}

struct DbRowValueQueue
{
public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    bool opCast(To: bool)() const nothrow @safe
    {
        return _length != 0;
    }

    void clear() nothrow @safe
    {
        while (length)
            dequeueItem();
    }

    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        clearItems(head);
        clearItems(pools);
        tail = null;
        _length = 0;
        return ResultCode.ok;
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

private:
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
    static struct VStruct
    {
        int x;
        float y;
    }

    auto dbNull = DbValue.dbNull();
    assert(dbNull.type == DbType.unknown);
    assert(dbNull.isNull);

    DbValue vn = DbValue(null, DbType.unknown);
    assert(vn.type == DbType.unknown);
    assert(vn.size == valueNoSizeMarker);
    assert(vn.isNull);

    DbValue vb = DbValue(true, DbType.boolean);
    assert(vb.value == true);
    assert(vb.type == DbType.boolean);
    assert(vb.size == valueNoSizeMarker);
    assert(!vb.isNull);

    DbValue vc = DbValue('x', DbType.stringFixed);
    assert(vc.value == "x");
    assert(vc.type == DbType.stringFixed);
    assert(vc.size == 1);
    assert(!vc.isNull);

    DbValue vi8 = DbValue(byte.max, DbType.int8);
    assert(vi8.value == byte.max);
    assert(vi8.type == DbType.int8);
    assert(vi8.size == valueNoSizeMarker);
    assert(!vi8.isNull);

    DbValue vi16 = DbValue(ubyte.max, DbType.int16);
    assert(vi16.value == ubyte.max);
    assert(vi16.type == DbType.int16);
    assert(vi16.size == valueNoSizeMarker);
    assert(!vi16.isNull);
    vi16 = DbValue(short.max, DbType.int16);
    assert(vi16.value == short.max);
    assert(vi16.type == DbType.int16);
    assert(vi16.size == valueNoSizeMarker);
    assert(!vi16.isNull);

    DbValue vi32 = DbValue(ushort.max, DbType.int32);
    assert(vi32.value == ushort.max);
    assert(vi32.type == DbType.int32);
    assert(vi32.size == valueNoSizeMarker);
    assert(!vi32.isNull);
    vi32 = DbValue(int.max, DbType.int32);
    assert(vi32.value == int.max);
    assert(vi32.type == DbType.int32);
    assert(vi32.size == valueNoSizeMarker);
    assert(!vi32.isNull);

    DbValue vi64 = DbValue(uint.max, DbType.int64);
    assert(vi64.value == uint.max);
    assert(vi64.type == DbType.int64);
    assert(vi64.size == valueNoSizeMarker);
    assert(!vi64.isNull);
    vi64 = DbValue(long.min, DbType.int64);
    assert(vi64.value == long.min);
    assert(vi64.type == DbType.int64);
    assert(vi64.size == valueNoSizeMarker);
    assert(!vi64.isNull);
    vi64 = DbValue(1234567890uL, DbType.int64);
    assert(vi64.value == 1234567890L);
    assert(vi64.type == DbType.int64);
    assert(vi64.size == valueNoSizeMarker);
    assert(!vi64.isNull);

    DbValue vf32 = DbValue(float.max, DbType.float32);
    assert(vf32.value == float.max);
    assert(vf32.type == DbType.float32);
    assert(vf32.size == valueNoSizeMarker);
    assert(!vf32.isNull);

    DbValue vf64 = DbValue(double.max, DbType.float64);
    assert(vf64.value == double.max);
    assert(vf64.type == DbType.float64);
    assert(vf64.size == valueNoSizeMarker);
    assert(!vf64.isNull);

    DbValue vss = DbValue("this is a string", DbType.stringVary);
    assert(vss.value == "this is a string");
    assert(vss.type == DbType.stringVary);
    assert(vss.size == "this is a string".length);
    assert(!vss.isNull);
    vss = DbValue("", DbType.stringVary);
    assert(vss.value == "");
    assert(vss.type == DbType.stringVary);
    assert(vss.size == 0);
    //assert(!vss.isNull); // TODO need to work out for this empty type?

    DbValue vsw = DbValue("this is a wstring"w, DbType.stringVary);
    assert(vsw.value == "this is a wstring");
    assert(vsw.type == DbType.stringVary);
    assert(vsw.size == "this is a wstring".length);
    assert(!vsw.isNull);

    DbValue vsd = DbValue("this is a dstring"d, DbType.stringVary);
    assert(vsd.value == "this is a dstring");
    assert(vsd.type == DbType.stringVary);
    assert(vsd.size == "this is a dstring".length);
    assert(!vsd.isNull);

    ubyte[] bi = [1,2,3];
    DbValue vbi = DbValue(bi, DbType.binaryVary);
    assert(vbi.value == cast(ubyte[])[1,2,3]);
    assert(vbi.type == DbType.binaryVary);
    assert(vbi.size == [1,2,3].length);
    assert(!vbi.isNull);

    VStruct vs = VStruct(1, 1.2f);
    DbValue vsi = DbValue(vs, DbType.record);
    assert(vsi.value == VStruct(1, 1.2f));
    assert(vsi.type == DbType.record);
    assert(vsi.size == VStruct.sizeof);
    assert(!vsi.isNull);
}
