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

module pham.utl.dlink_list;

nothrow @safe:

template isDLink(T)
if (is(T == class) || isPointer(T))
{
    static if (__traits(hasMember, T, "_next") && __traits(hasMember, T, "_prev"))
        enum isDLink = true;
    else
        enum isDLink = false;
}

mixin template DLinkTypes(T)
if (isDLink!T)
{
    struct Range
    {
    nothrow @safe:

    public:
        this(T lastNode) pure
        {
            this._lastNode = lastNode;
            if (lastNode is null)
                _done = true;
            else
                _nextNode = cast(T)(lastNode._next);
        }

        ~this()
        {
            dispose(false);
        }

        void dispose(bool disposing = true)
        {
            _lastNode = null;
            _nextNode = null;
            _done = true;
        }

        void popFront()
        {
            if (_nextNode !is null)
            {
                _nextNode = cast(T)(_nextNode._next);
                _done = _nextNode is null || _nextNode is _lastNode;
            }
        }

        @property T front()
        {
            return _nextNode;
        }

        @property bool empty() const
        {
            return _done;
        }

    private:
        T _lastNode;
        T _nextNode;
        bool _done;
    }
}

mixin template DLinkFunctions(T)
if (isDLink!T)
{
    pragma (inline, true)
    final bool hasNext(scope T lastNode, scope T checkNode) const nothrow @safe
    {
        return checkNode !is lastNode._next;
    }

    pragma (inline, true)
    final bool hasPrev(scope T lastNode, scope T checkNode) const nothrow @safe
    {
        return checkNode !is lastNode._prev;
    }

    final T insertAfter(T refNode, T newNode) nothrow @safe
    in
    {
        assert(refNode !is null);
        assert(refNode._next !is null);
    }
    do
    {
        newNode._next = refNode._next;
        newNode._prev = refNode;
        refNode._next._prev = newNode;
        refNode._next = newNode;
        return newNode;
    }

    final T insertEnd(ref T lastNode, T newNode) nothrow @safe
    {
        if (lastNode is null)
        {
            newNode._next = newNode;
            newNode._prev = newNode;
        }
        else
            insertAfter(lastNode, newNode);
        lastNode = newNode;
        return newNode;
    }

    final T remove(ref T lastNode, T oldNode) nothrow @safe
    {
        if (oldNode._next is oldNode)
            lastNode = null;
        else
        {
            oldNode._next._prev = oldNode._prev;
            oldNode._prev._next = oldNode._next;
            if (oldNode is lastNode)
                lastNode = cast(T)(oldNode._prev);
        }
        oldNode._next = null;
        oldNode._prev = null;
        return oldNode;
    }
}
