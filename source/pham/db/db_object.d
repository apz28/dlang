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

module pham.db.object;

import std.algorithm : remove;
import std.algorithm.comparison : min;
import std.array : Appender;
import std.ascii : isWhite;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.traits : ParameterTypeTuple, Unqual;
import std.uni : sicmp, toUpper;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.utf8 : utf8NextChar;
import pham.utl.array : IndexedArray;
import pham.utl.enum_set : EnumSet;
import pham.utl.object : DisposableState, IDisposable, shortClassName;
import pham.db.exception;
import pham.db.message;
import pham.db.parser;
import pham.db.type;
import pham.db.util;

/**
 * Returns a string of all elements in the table
 * Ex:
 *      name1=value1,name2=value2
 * Params:
 *      elementSeparator = is the separator string for each element
 *      valueSeparator = is the separator for each name & its value
 * Returns:
 *      string of all elements
 */
string getDelimiterText(T)(DbNameValueList!T list,
    char elementSeparator = ',',
    char valueSeparator = '=') nothrow @safe
if (is(T == const(char)[]) || is(T == string))
{
    if (list.length == 0)
        return "";

    auto buffer = Appender!string();
    buffer.reserve(min(list.length * 50, 16000));
    size_t i;
    foreach (ref e; list[])
    {
        if (i++ != 0)
            buffer.put(elementSeparator);

        assumeWontThrow(buffer.put(e.name.value));
        buffer.put(valueSeparator);
        buffer.put(e.value);
    }
    return buffer.data;
}

/**
 * Parse delimiter text into names & values. Beginning and ending spaces will be eliminated.
 * Ex:
 *      name1=value1,name2=value2
 * Params:
 *      values = a string of elements to be broken up
 *      elementSeparator = is the separator string for each element
 *      valueSeparator = is the separator for each name & its value
 * Returns:
 *      self
 */
DbNameValueList!T setDelimiterText(T)(DbNameValueList!T list, string values,
    char elementSeparator = ',',
    char valueSeparator = '=') nothrow @safe
if (is(T == string))
in
{
    assert(!isWhite(elementSeparator) && !isWhite(valueSeparator));
}
do
{
    list.clear();

    size_t p = 0;
    size_t cnt;
    dchar c;

    bool skipSpaces()
    {
        while (p < values.length)
        {
            const prev = p;
            c = utf8NextChar(values, p, cnt);
            if (!isWhite(c))
            {
                p = prev;
                return true;
            }
        }
        return false;
    }

    string readName()
    {
        const begin = p;
        size_t end = values.length;
        size_t lastSpace = 0;
        while (p < values.length)
        {
            const prev = p;
            c = utf8NextChar(values, p, cnt);
            if (c == elementSeparator || c == valueSeparator)
            {
                end = prev;
                break;
            }
            else if (isWhite(c))
                lastSpace = prev;
            else
                lastSpace = 0;
        }
        if (lastSpace != 0)
            return values[begin..lastSpace];
        else
            return values[begin..end];
    }

    string readValue()
    {
        const begin = p;
        size_t end = values.length;
        size_t lastSpace = 0;
        while (p < values.length)
        {
            const prev = p;
            c = utf8NextChar(values, p, cnt);
            if (c == elementSeparator)
            {
                end = prev;
                break;
            }
            else if (isWhite(c))
                lastSpace = prev;
            else
                lastSpace = 0;
        }
        if (lastSpace != 0)
            return values[begin..lastSpace];
        else
            return values[begin..end];
    }

    while (skipSpaces())
    {
        string value = "";
        string name = readName();
        if (skipSpaces())
            value = readValue();
        list.put(name, value);
    }

    return list;
}

DbIdentitier[] toIdentifiers(const string[] strings) nothrow
{
    DbIdentitier[] result = new DbIdentitier[](strings.length);
    foreach (i, s; strings)
        result[i] = DbIdentitier(s);
    return result;
}

struct DbCustomAttributeList
{
@safe:

public:
    string opIndex(string name) const @nogc nothrow pure
    {
        return get(name, null);
    }

    ref typeof(this) opIndexAssign(string value, string name) nothrow pure return
    {
        put(name, value);
        return this;
    }

    ref typeof(this) clear() nothrow pure return @trusted
    {
        _values.clear();
        return this;
    }

    string get(string name, string notFoundValue) const @nogc nothrow pure
    in
    {
        assert(name.length != 0);
    }
    do
    {
        if (auto e = name in _values)
            return *e;
        else
            return notFoundValue;
    }

    string put(string name, string value) nothrow pure
    in
    {
        assert(name.length != 0);
    }
    do
    {
        if (value.length)
            _values[name] = value;
        else
            _values.remove(name);
        return value;
    }

    @property bool empty() const nothrow pure
    {
        return _values.length == 0;
    }

    @property size_t length() const nothrow pure
    {
        return _values.length;
    }

    @property const(string[string]) values() const nothrow pure
    {
        return _values;
    }

private:
    string[string] _values;
}

struct DbIdentitier
{
nothrow @safe:

public:
    this(string value) pure
    {
        this(value, -1);
    }

    auto ref opOpAssign(string op)(in DbIdentitier value) return
    if (op == "~" || op == "+")
    {
        _s ~= value.s;
        return this;
    }

    auto ref opOpAssign(string op)(string value) return
    if (op == "~" || op == "+")
    {
        _s ~= value;
        return this;
    }

    auto ref opOpAssign(string op)(char value) return
    if (op == "~" || op == "+")
    {
        _s ~= value;
        return this;
    }

    bool opCast(B: bool)() const pure
    {
        return _s.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbIdentitier opCast(T)() const
    if (is(Unqual!T == DbIdentitier))
    {
        return this;
    }

    int opCmp(scope const(DbIdentitier) rhs) const pure
    {
        return sicmp(_s, rhs._s);
    }

    int opCmp(scope const(char)[] rhs) const pure
    {
        return sicmp(_s, rhs);
    }

    bool opEquals(scope const(DbIdentitier) rhs) const pure
    {
        return sicmp(_s, rhs._s) == 0;
    }

    bool opEquals(scope const(char)[] rhs) const pure
    {
        return sicmp(_s, rhs) == 0;
    }

    size_t toHash() const pure
    {
        return hashOf(ivalue);
    }

    string toString() const pure
    {
        return _s;
    }

    @property string ivalue() const pure
    {
	    scope (failure) assert(0);

        return toUpper(_s);
    }

    @property size_t length() const pure
    {
        return _s.length;
    }

    @property string value() const pure
    {
        return _s;
    }

    alias value this;

private:
    this(string value, ptrdiff_t index) pure
    {
        this._s = value;
        this._index = index;
    }

private:
    string _s;
    ptrdiff_t _index;
}

abstract class DbObject
{}

abstract class DbDisposableObject : DbObject, IDisposable
{
 nothrow @safe:

public:
    final void disposal(bool disposing)
    {
        _disposing++;
        doDispose(disposing);
    }

    final void dispose()
    {
        _disposing++;
        doDispose(true);
    }

    @property final DisposableState disposingState() const
    {
        if (_disposing == 0)
            return DisposableState.none;
        else if (_disposing > 0)
            return DisposableState.disposing;
        else
            return DisposableState.destructing;
    }

protected:
    abstract void doDispose(bool disposing);

private:
    byte _disposing;
}

class DbNameObject : DbObject
{
nothrow @safe:

public:
    alias List = DbNameObjectList!DbNameObject;

public:
    final int opCmp(scope const(DbIdentitier) otherName) const pure
    {
        return _name.opCmp(otherName);
    }

    final bool opEquals(scope const(DbIdentitier) otherName) const pure
    {
        return _name.opEquals(otherName);
    }

    final override size_t toHash() const
    {
        return _name.toHash();
    }

    @property final List list() pure @trusted
    {
        return cast(List)_list;
    }

    @property final DbIdentitier name() const pure
    {
        return _name;
    }

protected:
    final void updateName(DbIdentitier newName)
    {
        if (this._name != newName)
        {
            auto oldName = this._name;
            this._name._s = newName._s;

            if (list !is null)
                list.nameChanged(this, oldName);
        }
    }

    final void updateName(string newName)
    {
        const id = DbIdentitier(newName, _name._index);
        updateName(id);
    }

protected:
    void* _list;
    DbIdentitier _name;
}

class DbNameObjectList(T) : DbObject
if(is(T : DbNameObject))
{
public:
    /**
     * Implements range interface
     */
    static struct Range
    {
    nothrow @safe:

    public:
        alias List = DbNameObjectList!T;

    public:
        this(List list) pure
        {
            this._list = list;
            this._index = 0;
        }

        pragma(inline, true)
        void popFront()
        {
            _index++;
        }

        auto save()
        {
            return this;
        }

        pragma(inline, true)
        @property bool empty() const pure
        {
            return _index >= _list.length;
        }

        pragma(inline, true)
        @property T front()
        in
        {
            assert(!empty);
        }
        do
        {
            return _list[_index];
        }

        @property size_t index() const pure
        {
            return _index;
        }

    private:
        List _list;
        size_t _index;
    }

public:
    // Does not work for infer type & attributes (nothrow @safe)
    version (none)
    int opApply(Dg)(scope Dg dg)
    if (ParameterTypeTuple!Dg.length == 1)
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(this[i]))
                return r;
        }
        return 0;
    }

    // Does not work for infer type & attributes (nothrow @safe)
    version (none)
    int opApply(Dg)(scope Dg dg)
    if (ParameterTypeTuple!Dg.length == 2)
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(i, this[i]))
                return r;
        }
        return 0;
    }

    /**
     * Returns range interface
     */
    Range opIndex() nothrow @safe
    {
        return Range(this);
    }

    /**
     * Returns item at index
     */
    final T opIndex(size_t index) nothrow @safe
    in
    {
        assert(index < length);
    }
    do
    {
        return sequenceItems[index];
    }

    /**
     * Returns item with matching name
     */
    final T opIndex(scope const(DbIdentitier) name) nothrow @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        auto e = name in lookupItems;
        return e ? *e : null;
    }

    ///
    final T opIndex(string name) nothrow @safe
    {
        const id = DbIdentitier(name);
        return opIndex(id);
    }

    version (none)
    final typeof(this) opIndexAssign(T item) nothrow @safe
    in
    {
        assert(item.name.length != 0);
    }
    do
    {
        addOrSet(item);
        return this;
    }

    typeof(this) clear() nothrow pure @trusted
    {
        lookupItems.clear();
        sequenceItems.clear();
        flags.reset();
        return this;
    }

    final bool exist(scope const(DbIdentitier) name) const nothrow pure @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        const e = name in lookupItems;
        return e !is null;
    }

    final bool exist(string name) const nothrow pure @safe
    {
        const id = DbIdentitier(name);
        return exist(id);
    }

    final bool find(scope const(DbIdentitier) name, out T item) nothrow @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        auto e = name in lookupItems;
        if (e !is null)
        {
            item = *e;
            return true;
        }
        else
        {
            item = null;
            return false;
        }
    }

    final bool find(string name, out T item) nothrow @safe
    {
        const id = DbIdentitier(name);
        return find(id, item);
    }

    final DbIdentitier generateUniqueName(string prefix) const nothrow pure @safe
    {
        DbIdentitier res;
        size_t n = length;
        do
        {
            ++n;
            res = DbIdentitier(prefix ~ "_" ~ to!string(n));
        }
        while (exist(res));
        return res;
    }

    final T get(scope const(DbIdentitier) name) @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(msg, 0, null);
        }
        return result;
    }

    final T get(string name) @safe
    {
        const id = DbIdentitier(name);
        return get(id);
    }

    final ptrdiff_t indexOf(scope const(DbIdentitier) name) nothrow pure @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        if (flags.on(Flag.reIndex))
            reIndexItems();

        auto e = name in lookupItems;
        if (e !is null)
            return (*e)._name._index;
        else
            return -1;
    }

    final ptrdiff_t indexOf(string name) nothrow pure @safe
    {
        const id = DbIdentitier(name);
        return indexOf(id);
    }

    final ptrdiff_t indexOfSafe(scope const(DbIdentitier) name) @safe
    {
        const result = indexOf(name);
        if (result < 0)
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(msg, 0, null);
        }
        return result;
    }

    final ptrdiff_t indexOfSafe(string name) @safe
    {
        const id = DbIdentitier(name);
        return indexOfSafe(id);
    }

    final typeof(this) put(T item) nothrow @safe
    in
    {
        assert(item.name.length != 0);
    }
    do
    {
        addOrSet(item);
        return this;
    }

    final T remove(scope const(DbIdentitier) name) nothrow @safe
    {
        const i = indexOf(name);
        if (i >= 0)
            return remove(i);
        else
            return T.init;
    }

    final T remove(string name) nothrow @safe
    {
        const id = DbIdentitier(name);
        return remove(id);
    }

    T remove(size_t index) nothrow @safe
    in
    {
        assert(index < length);
    }
    do
    {
        auto result = this[index];
        result._list = null;
        lookupItems.remove(result.name);
        sequenceItems.removeAt(index);
        if (index < sequenceItems.length)
            flags += Flag.reIndex;
        return result;
    }

    @property final size_t length() const nothrow pure @safe
    {
        return sequenceItems.length;
    }

protected:
    //alias List = DbNameObjectList!DbNameObject;

    void add(T item) nothrow @trusted
    {
        item._list = cast(void*)this;
        item._name._index = length;
        lookupItems[item.name] = item;
        sequenceItems ~= item;
    }

    void addOrSet(T item) nothrow @trusted
    {
        const i = indexOf(item.name);
        if (i >= 0)
        {
            item._list = cast(void*)this;
            lookupItems[item.name] = item;
            sequenceItems[i] = item;
        }
        else
            add(item);
    }

    void nameChanged(T item, scope const(DbIdentitier) oldName) nothrow @safe
    {
        lookupItems.remove(oldName);
        lookupItems[item.name] = item;
    }

    final void reIndexItems() nothrow pure @safe
    {
        foreach (i, e; sequenceItems)
        {
            e._name._index = i;
        }
    }

protected:
    enum Flag : byte
    {
        reIndex
    }

    T[DbIdentitier] lookupItems;
    IndexedArray!(T, 30) sequenceItems;
    EnumSet!Flag flags;
}

struct DbNameValue(T)
{
nothrow @safe:

public:
    alias List = DbNameValueList!T;
    //pragma(msg, List);

public:
    this(DbIdentitier name, T value)
    in
    {
        assert(name.length != 0);
    }
    do
    {
        this._name = name;
        this.value = value;
    }

    this(string name, T value)
    in
    {
        assert(name.length != 0);
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        this(id, value);
    }

    int opCmp(scope const(DbIdentitier) otherName) const
    {
        return _name.opCmp(otherName);
    }

    bool opEquals(scope const(DbIdentitier) otherName) const
    {
        return _name.opEquals(otherName);
    }

    size_t toHash() const
    {
        return _name.toHash();
    }

    /* Properties */

    @property List list()
    {
        return _list;
    }

    @property DbIdentitier name() const
    {
        return _name;
    }

public:
    T value;

private:
    List _list;
    DbIdentitier _name;
}

class DbNameValueList(T) : DbObject
{
@safe:

public:
    alias Pair = DbNameValue!T;

public:
    /**
     * Implements range interface
     */
    static struct Range
    {
    nothrow @safe:

    public:
        alias List = DbNameValueList!T;

    public:
        this(List list) pure
        {
            this._list = list;
            this._index = 0;
        }

        pragma(inline, true)
        void popFront() pure
        {
            ++_index;
        }

        auto save() nothrow
        {
            return this;
        }

        pragma(inline, true)
        @property bool empty() const pure
        {
            return _index >= _list.length;
        }

        pragma(inline, true)
        @property ref Pair front() pure
        in
        {
            assert(_index < _list.length);
        }
        do
        {
            return _list[_index];
        }

        @property size_t index() const pure
        {
            return _index;
        }

    private:
        List _list;
        size_t _index;
    }

public:
    version (none)
    int opApply(scope int delegate(ref Pair e) dg)
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(this[i]))
                return r;
        }
        return 0;
    }

    version (none)
    int opApply(scope int delegate(size_t i, ref Pair e) dg)
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(i, this[i]))
                return r;
        }
        return 0;
    }

    /**
     * Returns range interface
     */
    Range opIndex() nothrow
    {
        return Range(this);
    }

    /**
     * Returns item at index
     */
    final ref Pair opIndex(size_t index) nothrow
    in
    {
        assert(index < length);
    }
    do
    {
        auto name = sequenceNames[index];
        assert(exist(name));
        auto e = name in lookupItems;
        return *e;
    }

    final typeof(this) opIndexAssign(Pair item) nothrow
    in
    {
        assert(item.name.length != 0);
    }
    do
    {
        addOrSet(item);
        return this;
    }

    /**
     * Removes all the elements from the array
     */
    typeof(this) clear() nothrow @trusted
    {
        lookupItems.clear();
        sequenceNames.clear();
        reIndex = false;
        return this;
    }

    /**
     * Returns true if name is in list; otherwise false
     *  Params:
     *      name = a name to be search for
     */
    final bool exist(in DbIdentitier name) const nothrow
    {
        auto e = name in lookupItems;
        return e !is null;
    }

    final bool exist(string name) const nothrow
    {
        const id = DbIdentitier(name);
        return exist(id);
    }

    final bool find(scope const(DbIdentitier) name, out T item) const nothrow
    {
        if (auto e = name in lookupItems)
        {
            item = (*e).value;
            return true;
        }
        else
        {
            item = T.init;
            return false;
        }
    }

    final bool find(string name, out T item) const nothrow
    {
        const id = DbIdentitier(name);
        return find(id, item);
    }

    final DbIdentitier generateUniqueName(string prefix) const nothrow
    {
        DbIdentitier res;
        size_t n = length;
        do
        {
            ++n;
            res = DbIdentitier(prefix ~ "_" ~ to!string(n));
        }
        while (exist(res));
        return res;
    }

    /**
     * Returns value of name if name is in list; otherwise null
     *  Params:
     *      name = is the name to look for
     *  Returns:
     *      string value of name
     */
    final T get(scope const(DbIdentitier) name)
    {
        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(msg, 0, null);
        }
        return result;
    }

    final T get(string name)
    {
        const id = DbIdentitier(name);
        return get(id);
    }

    final ptrdiff_t indexOf(scope const(DbIdentitier) name) nothrow
    {
        if (reIndex)
        {
            reIndexItems();
            reIndex = false;
        }

        auto e = name in lookupItems;
        if (e !is null)
            return (*e)._name._index;
        else
            return -1;
    }

    final ptrdiff_t indexOf(string name) nothrow
    {
        const id = DbIdentitier(name);
        return indexOf(id);
    }

    final typeof(this) put(DbIdentitier name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        auto item = Pair(name, value);
        addOrSet(item);
        return this;
    }

    final typeof(this) put(string name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        auto id = DbIdentitier(name, length);
        return put(id, value);
    }

    final bool putIf(DbIdentitier name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        if (!exist(name))
        {
            auto item = Pair(name, value);
            add(item);
            return true;
        }
        else
            return false;
    }

    final bool putIf(string name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        auto id = DbIdentitier(name, length);
        return putIf(id, value);
    }

    Pair remove(size_t index) nothrow
    in
    {
        assert(index < length);
    }
    do
    {
        auto item = this[index];
        item._list = null;
        lookupItems.remove(item.name);
        sequenceNames.removeAt(index);
        reIndex = index < sequenceNames.length;
        return item;
    }

    /**
     * Remove a string-name, name, from list
     * Params:
     *  name = is the name
     */
    final Pair remove(in DbIdentitier name) nothrow
    {
        const i = indexOf(name);
        if (i >= 0)
            return remove(i);
        else
            return Pair.init;
    }

    final Pair remove(string name) nothrow
    {
        const id = DbIdentitier(name);
        return remove(id);
    }

    @property size_t length() const nothrow pure
    {
        return sequenceNames.length;
    }

    /**
     * Returns value of name
     */
    @property final T value(scope const(DbIdentitier) name)
    {
        return get(name);
    }

    /**
     * Returns value of name
     */
    @property final T value(string name)
    {
        const id = DbIdentitier(name);
        return value(id);
    }

    @property final typeof(this) value(DbIdentitier name, T value)
    {
        return put(name, value);
    }

    @property final typeof(this) value(string name, T value)
    {
        DbIdentitier id = DbIdentitier(name);
        return put(id, value);
    }

protected:
    void add(ref Pair item) nothrow
    {
        item._list = this;
        item._name._index = length;
        lookupItems[item.name] = item;
        sequenceNames ~= item.name;
    }

    void addOrSet(ref Pair item) nothrow
    {
        if (exist(item.name))
        {
            item._list = this;
            lookupItems[item.name] = item;
        }
        else
            add(item);
    }

    void nameChanged(ref Pair item, scope const(DbIdentitier) oldName) nothrow
    {
        lookupItems.remove(oldName);
        lookupItems[item.name] = item;

        foreach (i, e; sequenceNames)
        {
            if (e == oldName)
            {
                sequenceNames[i] = item.name;
                break;
            }
        }
    }

    void reIndexItems() nothrow
    {
        foreach (i, n; sequenceNames)
        {
            auto e = n in lookupItems;
            (*e)._name._index = i;
        }
    }

protected:
    Pair[DbIdentitier] lookupItems;
    IndexedArray!(DbIdentitier, 30) sequenceNames;
    bool reIndex;
}


// Any below codes are private
private:

unittest // DbNameValueList
{
    import std.conv : to;
    import std.string : indexOf;
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.object.DbNameValueList");

    auto list = new DbNameValueList!string();
    list.put("a", "1");
    list.put("bcd", "2");
    list.put("x", "3");

    assert(list.length == 3, list.getDelimiterText(',', '='));
    assert(list.exist("a"));
    assert(list.exist("bcd"));
    assert(list.exist("x"));

    assert(!list.exist(""));
    assert(!list.exist("b"));
    assert(!list.exist("z"));

    assert(list.get("a") == "1");
    assert(list.get("bcd") == "2");
    assert(list.get("x") == "3");

    string s = list.getDelimiterText(',', '=');
    assert(s.indexOf("a=1") >= 0, s);
    assert(s.indexOf("bcd=2") >= 0, s);
    assert(s.indexOf("x=3") >= 0, s);

    list.put("x", null);
    assert(list.length == 3, list.getDelimiterText(',', '='));
    assert(list.exist("x"));
    assert(list.get("x") is null);

    immutable delimiterText = "a=1,bcd=2, user id = 3, x=4 ";
    list.setDelimiterText(delimiterText, ',', '=');
    assert(list.length == 4, list.getDelimiterText(',', '='));
    assert(list.get("a") == "1", list.get("a"));
    assert(list.get("bcd") == "2", list.get("bcd"));
    assert(list.get("user id") == "3", list.get("user id"));
    assert(list.indexOf("a") == 0);
    assert(list.indexOf("bcd") == 1);
    assert(list.indexOf("user id") == 2);
    assert(list.indexOf("x") == 3);
    list.remove("bcd");
    assert(list.length == 3);
    assert(list.indexOf("a") == 0);
    assert(list.indexOf("user id") == 1);
    assert(list.indexOf("x") == 2);
    list.remove("x");
    assert(list.length == 2);
    assert(list.indexOf("a") == 0);
    assert(list.indexOf("user id") == 1);
    list.remove("a");
    assert(list.length == 1);
    assert(list.indexOf("user id") == 0);
    assert(!list.exist("bcd"));
    assert(!list.exist("x"));
    assert(!list.exist("a"));
}

unittest // DbNameObjectList
{
    import std.string : indexOf;
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.object.DbNameObjectList");

    static class DbNameObjectTest : DbNameObject
    {
    public:
        int value;
        this(string name, int value)
        {
            this._name = DbIdentitier(name);
            this.value = value;
        }
    }

    auto list = new DbNameObjectList!DbNameObjectTest();

    list.put(new DbNameObjectTest("a", 1));
    list.put(new DbNameObjectTest("bcd", 2));
    list.put(new DbNameObjectTest("x", 3));

    assert(list.length == 3);
    assert(list.exist("a") && list.exist("A"));
    assert(list.exist("bcd") && list.exist("BCD"));
    assert(list.exist("x") && list.exist("X"));

    assert(!list.exist(""));
    assert(!list.exist("b"));
    assert(!list.exist("z"));

    assert(list.get("a").value == 1 && list.get("A").value == 1);
    assert(list.get("bcd").value == 2 && list.get("BCD").value == 2);
    assert(list.get("x").value == 3 && list.get("X").value == 3);

    list.put(new DbNameObjectTest("x", -1));
    assert(list.length == 3);
    assert(list.exist("x"));
    assert(list.get("x").value == -1);
}

unittest // DbCustomAttributeList
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.object.DbCustomAttributeList");

    DbCustomAttributeList v;

    v["name1"] = "value1";
    v["nameNull"] = "";
    assert(v["name1"] == "value1");
    assert(v["nameNull"] is null);
    assert(v.length == 1);
    assert(!v.empty);
    v["name1"] = null;
    assert(v.length == 0);
    assert(v.empty);
}
