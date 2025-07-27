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

nothrow @safe:


struct CipherBuffer(T)
if (is(T == ubyte) || is(T == byte) || is(T == char))
{
@safe:

public:
    @disable this(this);

    this(scope const(T)[] values) nothrow pure
    {
        this.data.opAssign(values);
    }

    ~this() nothrow pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) nothrow pure return
    {
        data.opAssign(rhs.data);
        return this;
    }

    ref typeof(this) opAssign(scope const(T)[] values) nothrow pure return
    {
        data.opAssign(values);
        return this;
    }

    //pragma(inline, true)
    ref typeof(this) chopFront(const(size_t) chopLength) nothrow pure return
    {
        data.chopFront(chopLength);
        return this;
    }

    //pragma(inline, true)
    ref typeof(this) chopTail(const(size_t) chopLength) nothrow pure return
    {
        data.chopTail(chopLength);
        return this;
    }

    ref typeof(this) clear() nothrow pure return
    {
        data.clear();
        return this;
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        data.dispose(disposingReason);
    }

    ref typeof(this) put(T v) nothrow pure return
    {
        data.put(v);
        return this;
    }

    ref typeof(this) put(scope const(T)[] v) nothrow pure return
    {
        data.put(v);
        return this;
    }

    ref typeof(this) removeFront(const(T) removingValue) nothrow pure return
    {
        data.removeFront(removingValue);
        return this;
    }

    ref typeof(this) removeTail(const(T) removingValue) nothrow pure return
    {
        data.removeTail(removingValue);
        return this;
    }

    ref typeof(this) reverse() @nogc nothrow pure return
    {
        data.reverse();
        return this;
    }

    CipherRawKey!T toRawKey() const nothrow pure
    {
        return CipherRawKey!T(data[]);
    }

    string toString() const nothrow pure @trusted
    {
        static if (is(T == char))
            return data[].idup;
        else
            return cast(string)bytesToHexs(data[]);
    }

public:
    private enum overheadSize = StaticStringBuffer!(T, 1u).sizeof;
    StaticStringBuffer!(T, 1_024u - overheadSize) data;
    alias this = data;
}

struct CipherRawKey(T)
if (is(T == ubyte) || is(T == byte) || is(T == char))
{
nothrow @safe:

public:
    this(this) pure
    {
        unique();
    }

    this(const(size_t) capacity) pure
    {
        this._data.reserve(capacity);
    }

    this(scope const(T)[] value) pure
    {
        this._data = value.dup;
    }

    this(ref typeof(this) value) pure
    {
        this._data = value._data.dup;
    }

    ref typeof(this) opAssign(scope const(T)[] rhs) pure return
    {
        this._data.length = rhs.length;
        this._data[] = rhs[];
        return this;
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this._data.length = rhs._data.length;
        this._data[] = rhs._data[];
        return this;
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) chopFront(const(size_t) chopLength) pure return
    {
        if (chopLength >= _data.length)
            clear();
        else
            _data = _data[chopLength..$];
        return this;
    }

    ref typeof(this) chopTail(const(size_t) chopLength) pure return
    {
        if (chopLength >= _data.length)
            clear();
        else
            _data = _data[0.._data.length - chopLength];
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    pragma(inline, true)
    bool isValid() const @nogc pure
    {
        return isValid(_data);
    }

    /**
     * Returns true if v is not empty and not all same value
     */
    static bool isValid(scope const(T)[] v) @nogc pure
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

    ref typeof(this) reverse() pure return
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

    ref typeof(this) removeFront(const(T) removingValue) pure return
    {
        while (_data.length && _data[0] == removingValue)
            _data = _data[1..$];
        return this;
    }

    ref typeof(this) removeTail(const(T) removingValue) pure return
    {
        while (_data.length && _data[_data.length - 1] == removingValue)
            _data = _data[0.._data.length - 1];
        return this;
    }

    pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return _data.length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc pure
    {
        return _data.length;
    }

    pragma(inline, true)
    @property const(T)[] value() const pure
    {
        return _data;
    }

    alias this = value;

package(pham.cp):
    pragma(inline, true)
    void clear() pure
    {
        _data[] = 0;
        _data = null;
    }

    pragma(inline, true)
    void unique() pure
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
