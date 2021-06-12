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

module pham.db.buffer_filter;

version (unittest) import pham.utl.test;
import pham.utl.enum_set : toName;
import pham.db.dbobject;

nothrow @safe:

enum DbBufferFilterKind : byte
{
    read,
    write
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
        return errorCode != 0 || errorMessage.length != 0;
    }

    @property abstract DbBufferFilterKind kind() const;

    @property abstract string name() const;

    @property DbBufferFilter next() pure
    {
        return _next;
    }

    @property final string processName() const
    {
        return name ~ "." ~ toName!DbBufferFilterKind(kind);
    }

public:
    string errorMessage;
    int errorCode;

protected:
    pragma(inline, true)
    final void clearError()
    {
        errorMessage = null;
        errorCode = 0;
    }

    override void doDispose(bool disposing)
    {
        _next = null;
        _outputBuffer = null;
        errorMessage = null;
        errorCode = 0;
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
