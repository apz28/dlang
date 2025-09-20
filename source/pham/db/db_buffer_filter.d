/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2020 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.db_buffer_filter;

import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_enum_set : toName;
import pham.utl.utl_result : ResultStatus;
public import pham.utl.utl_result : ResultCode;
import pham.db.db_object;

nothrow @safe:

enum DbBufferFilterKind : ubyte
{
    read,
    write,
}

abstract class DbBufferFilter : DbDisposableObject
{
nothrow @safe:

public:
    abstract bool process(scope const(ubyte)[] input, out ubyte[] output);

    static DbBufferFilter chainHead(ref DbBufferFilter head, DbBufferFilter next)
    in
    {
        assert(next !is null);
        assert(next !is head);
        assert(next._next is null);
    }
    do
    {
        if (head is null)
            head = next;
        else
        {
            next._next = head;
            head = next;
        }
        return head;
    }

    static DbBufferFilter chainTail(ref DbBufferFilter head, DbBufferFilter next)
    in
    {
        assert(next !is null);
        assert(next !is head);
        assert(next._next is null);
    }
    do
    {
        if (head is null)
            head = next;
        else
            getLast(head)._next = next;
        return head;
    }

    static DbBufferFilter getLast(DbBufferFilter head) pure
    {
        while (head !is null && head.next !is null)
            head = head.next;
        return head;
    }

    @property bool hasError() const pure
    {
        return errorStatus.isError;
    }

    @property abstract DbBufferFilterKind kind() const pure;

    @property abstract string name() const pure;

    @property DbBufferFilter next() pure
    {
        return _next;
    }

    @property final string processName() const pure
    {
        return name ~ "." ~ toName!DbBufferFilterKind(kind);
    }

public:
    ResultStatus errorStatus;

protected:
    pragma(inline, true)
    final void clearError() pure
    {
        errorStatus.reset();
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        errorStatus.reset();
        _next = null;
        _outputBuffer = null;
        return ResultCode.ok;
    }

    ubyte[] increaseOutputBuffer(size_t nBytes) return
    {
        if (_outputBuffer.length < nBytes)
            _outputBuffer.length = nBytes;
        return _outputBuffer;
    }

protected:
    DbBufferFilter _next;
    ubyte[] _outputBuffer;
}
