/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.cp_cipher_buffer;

import pham.utl.utl_array_static : StaticStringBuffer;
import pham.utl.utl_convert : bytesToHexs;
import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_result : ResultCode;

nothrow @safe:

struct CipherBuffer(T)
if (is(T == ubyte) || is(T == byte) || is(T == char))
{
nothrow @safe:

public:
    @disable this(this);

    this(scope const(T)[] values)
    {
        this._data.opAssign(values);
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) return
    {
        _data.opAssign(rhs._data);
        return this;
    }

    ref typeof(this) opAssign(scope const(T)[] rhs) return
    {
        _data.opAssign(rhs);
        return this;
    }

    pragma(inline, true)
    void opIndexOpAssign(string op)(T rhs, size_t index)
    if (op == "&" || op == "|" || op == "^")
    {
        mixin("this._data[index] " ~ op ~ "= rhs;");
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) chopFront(const(size_t) chopLength) return
    {
        _data.chopFront(chopLength);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) chopTail(const(size_t) chopLength) return
    {
        _data.chopTail(chopLength);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) clear() return
    {
        _data.clear();
        return this;
    }

    // For security reason, need to clear the secrete information
    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _data.dispose(disposingReason);
        return ResultCode.ok;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) put(T v) return
    {
        _data.put(v);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) put(scope const(T)[] v) return
    {
        if (v.length)
            _data.put(v);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) removeFront(const(T) removingValue) return
    {
        _data.removeFront(removingValue);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) removeTail(const(T) removingValue) return
    {
        _data.removeTail(removingValue);
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) reverse() return
    {
        _data.reverse();
        return this;
    }

    CipherRawKey!T toRawKey() const
    {
        return CipherRawKey!T(_data[]);
    }

    string toString() const nothrow @trusted
    {
        static if (is(T == char))
            return _data[].idup;
        else
            return cast(string)bytesToHexs(_data[]);
    }

    pragma(inline, true)
    @property bool empty() const @nogc
    {
        return _data.length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc
    {
        return _data.length;
    }

    pragma(inline, true)
    @property const(T)[] value() const return
    {
        return _data[];
    }

    alias this = value;

private:
    enum overheadSize = StaticStringBuffer!(T, 1u).sizeof;
    StaticStringBuffer!(T, 1_024u - overheadSize) _data;
}

struct CipherRawKey(T)
if (is(T == ubyte) || is(T == byte) || is(T == char))
{
nothrow @safe:

public:
    this(this)
    {
        unique();
    }

    this(const(size_t) capacity)
    {
        this._data.reserve(capacity);
    }

    this(scope const(T)[] value)
    {
        this._data = value.dup;
    }

    this(ref typeof(this) value)
    {
        this._data = value._data.dup;
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(scope const(T)[] rhs) return
    {
        this._data.length = rhs.length;
        this._data[] = rhs[];
        return this;
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) return
    {
        this._data.length = rhs._data.length;
        this._data[] = rhs._data[];
        return this;
    }

    pragma(inline, true)
    void opIndexOpAssign(string op)(T rhs, size_t index)
    if (op == "&" || op == "|" || op == "^")
    {
        mixin("this._data[index] " ~ op ~ "= rhs;");
    }

    ref typeof(this) chopFront(const(size_t) chopLength) return
    {
        if (chopLength >= _data.length)
            clear();
        else
            _data = _data[chopLength..$];
        return this;
    }

    ref typeof(this) chopTail(const(size_t) chopLength) return
    {
        if (chopLength >= _data.length)
            clear();
        else
            _data = _data[0.._data.length - chopLength];
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) clear() return
    {
        _data[] = 0;
        _data = null;
        return this;
    }

    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        clear();
        return ResultCode.ok;
    }

    pragma(inline, true)
    bool isValid() const @nogc
    {
        return isValid(_data);
    }

    /**
     * Returns true if v is not empty and not all same value
     */
    static bool isValid(scope const(T)[] v) @nogc
    {
        // Must not empty
        if (v.length == 0)
            return false;

        // Must not all the same value
        if (v.length > 1)
        {
            const first = v[0];
            foreach (i; 1..v.length)
            {
                if (v[i] != first)
                    return true;
            }
            return false;
        }

        return true;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) put(T v) return
    {
        _data ~= v;
        return this;
    }

    //TODO NOT Inline pragma(inline, true)
    ref typeof(this) put(scope const(T)[] v) return
    {
        if (v.length)
            _data ~= v;
        return this;
    }

    ref typeof(this) reverse() return
    {
        import std.algorithm.mutation : swapAt;

        const len = _data.length;
        if (len > 1)
        {
            const last = len - 1;
            const steps = len / 2;
            foreach (i; 0..steps)
                _data.swapAt(i, last - i);
        }
        return this;
    }

    ref typeof(this) removeFront(const(T) removingValue) return
    {
        while (_data.length && _data[0] == removingValue)
            _data = _data[1..$];
        return this;
    }

    ref typeof(this) removeTail(const(T) removingValue) return
    {
        while (_data.length && _data[_data.length - 1] == removingValue)
            _data = _data[0.._data.length - 1];
        return this;
    }

    string toString() const nothrow @trusted
    {
        static if (is(T == char))
            return _data[].idup;
        else
            return cast(string)bytesToHexs(_data[]);
    }

    pragma(inline, true)
    @property bool empty() const @nogc
    {
        return _data.length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc
    {
        return _data.length;
    }

    pragma(inline, true)
    @property const(T)[] value() const return
    {
        return _data;
    }

    alias this = value;

package(pham.cp):
    pragma(inline, true)
    void unique()
    {
        _data = _data.dup;
    }

private:
    T[] _data;
}


// Any below codes are private
private:

unittest // CipherRawKey.isValid
{
    assert(CipherRawKey!ubyte.isValid([9]));
    assert(CipherRawKey!ubyte.isValid([0, 1]));
    assert(CipherRawKey!ubyte.isValid([1, 0, 2]));

    assert(!CipherRawKey!ubyte.isValid([]));
    assert(!CipherRawKey!ubyte.isValid([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
}

nothrow @safe unittest // CipherBuffer
{
    import std.conv : to;
    import std.stdio : writeln;

    alias CharBuffer = CipherBuffer!char;
    alias ByteBuffer = CipherBuffer!ubyte;

    auto cb = CharBuffer("abc");
    assert(cb.length == 3);
    assert(!cb.empty);
    assert(cb[0] == 'a');
    assert(cb.toString() == "abc");

    cb.put('d');
    assert(cb.length == 4);
    assert(cb[3] == 'd');

    cb.put("ef");
    assert(cb.length == 6);
    assert(cb.toString() == "abcdef");

    char binA = 'a';
    binA |= cast(char)('A' - 'a');
    cb = CharBuffer("abcdef");
    cb.opIndexOpAssign!"|"(cast(char)('A' - 'a'), 0);
    assert(cb[0] == binA, (cast(int)(cb[0])).to!string() ~ " vs " ~ (cast(int)binA).to!string());

    binA = 'a';
    binA &= cast(char)(' ' ^ 'A');
    cb = CharBuffer("abcdef");
    cb.opIndexOpAssign!"&"(cast(char)(' ' ^ 'A'), 0);
    assert(cb[0] == binA, (cast(int)(cb[0])).to!string() ~ " vs " ~ (cast(int)binA).to!string());

    cb = CharBuffer("abcdef");

    cb.chopFront(2);
    assert(cb.toString() == "cdef");

    cb.chopTail(1);
    assert(cb.toString() == "cde");

    cb.removeFront('c');
    assert(cb.toString() == "de");

    cb.removeTail('e');
    assert(cb.toString() == "d");

    cb.clear();
    assert(cb.empty);
    assert(cb.length == 0);

    cb.put("xyz");
    auto rawKey = cb.toRawKey();
    assert(rawKey.length == 3);
    assert(rawKey.toString() == "xyz");

    auto bb = ByteBuffer([0x0Au, 0x0Bu]);
    assert(bb.length == 2);
    assert(!bb.empty);
    assert(bb.value[0] == 0x0Au);
    bb.put(0x0Cu);
    assert(bb.length == 3);
    bb.put([0x0Du, 0x0Eu]);
    assert(bb.length == 5);
    assert(bb.value[4] == 0x0Eu);

    bb.clear();
    assert(bb.empty);
    assert(bb.length == 0);
    bb.put([0x01u, 0x02u, 0x03u]);
    bb.dispose();
    assert(bb.empty);
}

nothrow @safe unittest // CipherRawKey
{
    alias CharKey = CipherRawKey!char;
    alias ByteKey = CipherRawKey!ubyte;

    CharKey key1 = CharKey("abcd");
    assert(key1.length == 4);
    assert(!key1.empty);
    assert(key1.toString() == "abcd");

    key1.put('e');
    assert(key1.length == 5);
    assert(key1[4] == 'e');

    key1.put("fg");
    assert(key1.length == 7);
    assert(key1.toString() == "abcdefg");

    key1.opIndexOpAssign!"|"(' ', 0);
    key1.opIndexOpAssign!"&"(cast(char)(' ' ^ key1[0]), 0);

    key1.chopFront(2);
    assert(key1.toString() == "cdefg" || key1.toString() == "Cdefg");

    key1.chopTail(2);
    assert(key1.length == 3);

    key1.removeFront(key1[0]);
    assert(key1.length <= 2);

    key1.clear();
    assert(key1.empty);
    assert(key1.length == 0);

    key1 = CharKey("hello");
    auto key2 = CharKey(key1);
    assert(key2.length == 5);
    assert(key2.toString() == "hello");

    key2 = key1;
    assert(key2 == "hello" || key2 == key1);

    key2.dispose();
    assert(key2.empty);

    ByteKey bkey1 = ByteKey([0x01u, 0x02u, 0x03u]);
    assert(bkey1.length == 3);
    assert(!bkey1.empty);
    assert(bkey1.value[1] == 0x02u);

    bkey1.put(0x04u);
    assert(bkey1.length == 4);
    bkey1.put([0x05u, 0x06u]);
    assert(bkey1.length == 6);

    bkey1.reverse();
    assert(bkey1.value[0] == 0x06u);
    assert(bkey1.value[$ - 1] == 0x01u);

    bkey1.removeFront(0x06u);
    bkey1.removeTail(0x01u);
    assert(bkey1.length == 4);

    bkey1.opIndexOpAssign!"|"(0x01u, 0);
    bkey1.opIndexOpAssign!"&"(0x03u, 1);

    bkey1.clear();
    assert(bkey1.empty);
    bkey1.dispose();
    assert(bkey1.empty);

    ByteKey bkey2 = ByteKey(8);
    assert(bkey2.length == 0);
    assert(bkey2.empty);

    bkey2 = bkey1;
    assert(bkey2.empty);

    bkey2 = ByteKey([0x0Au, 0x0Bu, 0x0Cu]);
    assert(ByteKey.isValid(bkey2));
    assert(!ByteKey.isValid([]));
    assert(!ByteKey.isValid([0x00u, 0x00u, 0x00u]));

    bkey2.unique();
    assert(bkey2.length == 3);
}
