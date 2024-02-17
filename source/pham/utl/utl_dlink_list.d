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

module pham.utl.utl_dlink_list;

public import pham.utl.utl_disposable : DisposingReason;

nothrow @safe:

/**
 * Check if a class or struct pointer has two members "_next" & "_prev"
 */
template isDLink(T)
if (is(T == class) || isPointer(T))
{
    static if (__traits(hasMember, T, "_next") && __traits(hasMember, T, "_prev"))
        enum isDLink = true;
    else
        enum isDLink = false;
}

/**
 * Defines all supported functions for double link list operations
 * Root node is always pointed to last node
 */
mixin template DLinkTypes(T)
if (isDLink!T)
{
    /**
     * Define a DLinkRange type to be used as range for double link list
     */
    struct DLinkRange
    {
    nothrow @safe:

    public:
        this(T rootNode) pure
        {
            this._rootNode = rootNode;
            if (rootNode is null)
            {
                this._currentNode = null;
                this._firstNode = null;
                this._empty = true;
            }
            else
            {
                this._currentNode = cast(T)(rootNode._next);
                this._firstNode = this._currentNode;
                this._empty = false;
            }
        }

        version(none)
        ~this()
        {
            dispose(DisposingReason.destructor);
        }

        void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
        {
            _currentNode = null;
            _firstNode = null;
            _rootNode = null;
            _empty = true;
        }

        void popFront()
        in
        {
            assert(!empty);
        }
        do
        {
            _currentNode = cast(T)(_currentNode._next);
            _empty = _currentNode is _firstNode;
            if (_empty)
                _currentNode = null;
        }

        @property T front()
        {
            return _currentNode;
        }

        @property bool empty() const @nogc pure
        {
            return _empty;
        }

    private:
        T _currentNode;
        T _firstNode;
        T _rootNode;
        bool _empty;
    }

    struct DLinkList
    {
    nothrow @safe:

    public:
        DLinkRange opIndex()
        {
            return DLinkRange(_rootNode);
        }

        /**
         * Check if checkNode has a next node
         * Params:
         *  checkNode = a node to be checked if it has next node
         * Returns:
         *  true if checkNode has a next node, false otherwise
         */
        pragma (inline, true)
        bool hasNext(scope T checkNode) @nogc pure
        {
            return checkNode !is null && checkNode !is checkNode._next;
        }

        /**
         * Check if checkNode has a previous node
         * Params:
         *  checkNode = a node to be checked if it has previous node
         * Returns:
         *  true if checkNode has a previous node, false otherwise
         */
        pragma (inline, true)
        bool hasPrev(scope T checkNode) pure
        {
            return checkNode !is null && checkNode !is checkNode._prev;
        }

        /**
         * Insert insertingNode after atNode
         * Params:
         *  atNode = an anchor node
         *  insertingNode = a node to be inserted
         * Returns:
         *  Return newly inserted node, insertingNode
         */
        T insertAfter(T atNode, T insertingNode) pure
        in
        {
            assert(atNode !is null);
            assert(atNode._next !is null);
        }
        do
        {
            insertingNode._next = atNode._next;
            insertingNode._prev = atNode;
            atNode._next._prev = insertingNode;
            atNode._next = insertingNode;
            if (_rootNode is atNode)
                _rootNode = insertingNode;
            return insertingNode;
        }

        /**
         * Insert insertingNode at the begin
         * Params:
         *  insertingNode = a node to be inserted
         * Returns:
         *  Return newly inserted node, insertingNode
         */
        T insertBegin(T insertingNode) pure
        {
            if (_rootNode is null)
                return insertFirst(insertingNode);
            else
            {
                insertingNode._next = _rootNode;
                insertingNode._prev = _rootNode._prev;
                _rootNode._prev = insertingNode;
                _rootNode = insertingNode;
                return insertingNode;
            }
        }

        /**
         * Insert insertingNode at the end
         * Params:
         *  insertingNode = a node to be inserted
         * Returns:
         *  Return newly inserted node, insertingNode
         */
        T insertEnd(T insertingNode) pure
        {
            if (_rootNode is null)
                return insertFirst(insertingNode);
            else
                return insertAfter(_rootNode, insertingNode);
        }

        /**
         * Return next node of currentNode.
         * Since this is circular double link list, calling this in while loop can run in infinite loop
         * Params:
         *  currentNode = a node that may have next node
         * Returns:
         *  next node of currentNode if any, null otherwise
         */
        pragma (inline, true)
        T next(scope T currentNode) pure
        {
            return currentNode !is currentNode._next ? cast(T)(currentNode._next) : null;
        }

        /**
         * Return previous node of currentNode.
         * Since this is circular double link list, calling this in while loop can run in infinite loop
         * Params:
         *  currentNode = a node that may have previous node
         * Returns:
         *  previous node of currentNode if any, null otherwise
         */
        pragma (inline, true)
        T prev(scope T currentNode) pure
        {
            return currentNode !is currentNode._prev ? cast(T)(currentNode._prev) : null;
        }

        /**
         * Remove removingNode from its double link list
         * Params:
         *  removingNode = a node to be removed
         * Returns:
         *  Return removed node, removingNode
         */
        T remove(T removingNode) pure
        {
            // Only one node?
            if (removingNode._next is removingNode)
                _rootNode = null;
            else
            {
                removingNode._next._prev = removingNode._prev;
                removingNode._prev._next = removingNode._next;
                // removingNode is the last node
                if (removingNode is _rootNode)
                    _rootNode = cast(T)(removingNode._prev);
            }
            removingNode._next = null;
            removingNode._prev = null;
            return removingNode;
        }

        @property bool empty() const @nogc pure
        {
            return _rootNode is null;
        }

        /**
         * Return first node of double link list.
         */
        @property T first() pure
        {
            return _rootNode !is null ? cast(T)(_rootNode._next) : null;
        }

        /**
         * Return last node of double link list.
         */
        @property T last() pure
        {
            return _rootNode;
        }

    private:
        T insertFirst(T insertingNode) pure
        {
            insertingNode._next = insertingNode;
            insertingNode._prev = insertingNode;
            _rootNode = insertingNode;
            return insertingNode;
        }

        T _rootNode;
    }
}


private:

unittest
{
    import std.conv : to;

    class X
    {
    public:
        this(int v)
        {
            this.v = v;
        }

        final override string toString() const nothrow @safe
        {
            return v.to!string();
        }

    public:
        int v;

    private:
        typeof(this) _next;
        typeof(this) _prev;
    }

    mixin DLinkTypes!(X) DLinkXTypes;

    string getStrings(ref DLinkXTypes.DLinkList list)
    {
        string result;
        foreach (x; list[])
            result ~= x.toString();
        return result;
    }

    DLinkXTypes.DLinkList list;
    auto x1 = new X(1);
    list.insertEnd(x1);
    assert(!list.hasNext(x1));
    assert(list.next(x1) is null);
    assert(!list.hasPrev(x1));
    assert(list.prev(x1) is null);
    assert(getStrings(list) == "1");

    auto x3 = new X(3);
    list.insertEnd(x3);
    assert(list.hasNext(x1));
    assert(list.next(x1) is x3);
    assert(list.hasPrev(x3));
    assert(list.prev(x3) is x1);
    assert(getStrings(list) == "13");

    auto x2 = new X(2);
    list.insertAfter(x1, x2);
    assert(list.hasNext(x1));
    assert(list.next(x1) is x2);
    assert(list.hasPrev(x3));
    assert(list.prev(x3) is x2);
    assert(getStrings(list) == "123");

    auto x4 = new X(4);
    list.insertAfter(x3, x4);
    assert(list.hasNext(x3));
    assert(list.next(x3) is x4);
    assert(list.hasPrev(x4));
    assert(list.prev(x4) is x3);
    assert(getStrings(list) == "1234");

    list.remove(x1);
    assert(list.hasNext(x2));
    assert(list.next(x2) is x3);
    assert(list.hasPrev(x3));
    assert(list.prev(x3) is x2);
    assert(getStrings(list) == "234");

    while (!list.empty)
        list.remove(list.last);
    assert(getStrings(list).length == 0);
}
