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

module pham.db.db_object;

import core.sync.mutex : Mutex;
import std.algorithm : remove;
import std.algorithm.comparison : min;
import std.array : Appender;
import std.ascii : isWhite;
import std.conv : to;
import std.traits : isIntegral, isSomeString, ParameterTypeTuple, Unqual;
import std.uni : sicmp, toUpper;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.dtm.dtm_date : DateTime;
import pham.utl.utl_disposable;
import pham.utl.utl_enum_set : EnumSet;
import pham.utl.utl_object : RAIIMutex, shortClassName;
import pham.utl.utl_result : addLine, ResultIf;
import pham.utl.utl_utf8 : nextUTF8Char;
import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_parser;
import pham.db.db_type;
import pham.db.db_util;


DbIdentitier[] toIdentifiers(const string[] strings) nothrow
{
    auto result = new DbIdentitier[](strings.length);
    foreach (i, s; strings)
        result[i] = DbIdentitier(s);
    return result;
}

enum DbExpirationKind : ubyte
{
    created,
    lastTouched,
}

struct DbExpiration
{
nothrow @safe:

public:
    this(uint maxAge, DbExpirationKind kind)
    {
        this.maxAge = maxAge;
        this.kind = kind;
        this.created = this.lastTouched = DateTime.now;
    }

    bool canEvicted() const
    {
        if (maxAge == 0)
            return false;
            
        return kind == DbExpirationKind.created
            ? ((DateTime.now - created).totalMinutes > maxAge)
            : ((DateTime.now - lastTouched).totalMinutes > maxAge);
    }
    
    void touch()
    {
        this.lastTouched = DateTime.now;
    }

public:
    DateTime created;
    DateTime lastTouched;
    uint maxAge;
    DbExpirationKind kind;
}

struct DbCacheItem(K)
if (isIntegral!K || isSomeString!K)
{
nothrow @safe:

public:
    this(K key, Object item, uint maxAge, DbExpirationKind kind)
    {
        this._key = key;
        this._expiration = DbExpiration(maxAge, kind);
        this.item = item;
    }
    
    bool opEqual(scope const(DbCacheItem) rhs) const
    {
        return rhs._key == this._key;
    }

    size_t toHash() const
    {
        return hashOf(_key);
    }

    bool canEvicted() const
    {
        return _expiration.canEvicted();
    }
    
    V touch(V : Object)()
    {
        this._expiration.touch();
        return cast(V)item;
    }

    V touch(V : Object)(V item, uint maxAge, DbExpirationKind kind)
    {
        this._expiration = DbExpiration(maxAge, kind);
        this.item = item;
        return item;
    }

    @property DateTime created() const
    {
        return _expiration.created;
    }

    @property K key() const
    {
        return _key;
    }

    @property DateTime lastTouched() const
    {
        return _expiration.lastTouched;
    }

    /**
     * Max number of minutes a cached item can be kept
     * The value of zero is unlimit
     * default is 4 hours
     */
    @property uint maxAge() const
    {
        return _expiration.maxAge;
    }
public:
    Object item;

private:
    K _key;
    DbExpiration _expiration;
}

class DbCache(K) : DbDisposableObject
if (isIntegral!K || isSomeString!K)
{
nothrow @safe:

    enum defaultAge = 60 * 4; // 4 hours in minutes
    enum defaultKind = DbExpirationKind.created;
    
public:
    this()
    {
        this.mutex = new Mutex();
    }

    final bool add(V : Object)(K key, V item,
        uint maxAge = defaultAge,
        DbExpirationKind kind = defaultKind)
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        if (auto e = key in items)
        {
            if (!(*e).canEvicted())
                return false;
                
            (*e).touch!V(item, maxAge, kind);
            return true;
        }
            
        items[key] = DbCacheItem!K(key, item, maxAge, kind);
        return true;
    }

    final V addOrReplace(V : Object)(K key, V item,
        uint maxAge = defaultAge,
        DbExpirationKind kind = defaultKind)
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        if (auto e = key in items)
            (*e).touch!V(item, maxAge, kind);
        else    
            items[key] = DbCacheItem!K(key, item, maxAge, kind);
        return item;
    }
    
    final bool find(V : Object)(K key, ref V found)
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        return findImpl!V(key, found) == FindResult.found;
    }
    
    final void remove(K key)
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        items.remove(key);
    }
    
    final bool remove(V : Object)(K key, ref V found)
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        final switch (findImpl!V(key, found))
        {
            case FindResult.found:
                items.remove(key);
                return true;
            case FindResult.unfound:
                return false;
            case FindResult.expired:
                items.remove(key);
                return false;
        }
    }

    @property K[] keys()
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        return items.keys;
    }

    @property size_t length()
    {
        auto raiiMutex = RAIIMutex(mutex);
        
        return items.length;
    }
    
protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @trusted
    {
        items.clear();
        
        if (mutex !is null)
        {
            mutex.destroy();
            mutex = null;
        }
    }
    
    enum FindResult : ubyte
    {
        found,
        unfound,
        expired,
    }
    
    final FindResult findImpl(V : Object)(K key, ref V found)
    {
        if (auto e = key in items)
        {
            if ((*e).canEvicted())
                return FindResult.expired;
                
            found = (*e).touch!V();
            return FindResult.found;
        }
        else
            return FindResult.unfound;
    }

private:
    Mutex mutex;
    DbCacheItem!K[K] items;
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

    bool hasValue(string name, out string value) const nothrow
    {
        value = get(name, null);
        return value.length != 0;
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
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(char)[] rhs) const pure
    {
        return opCmp(rhs) == 0;
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
	    scope (failure) assert(0, "Assume nothrow failed");

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
{
protected:
    void doOptionChanged(string propertyName) nothrow @safe
    {}
}

abstract class DbDisposableObject : DbObject, IDisposable
{
public:
    final void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        if (!_lastDisposingReason.canDispose(disposingReason))
            return;

        _lastDisposingReason = disposingReason;
        doDispose(disposingReason);
    }

    pragma(inline, true)
    @property final override DisposingReason lastDisposingReason() const @nogc nothrow @safe
    {
        return _lastDisposingReason.value;
    }

protected:
    abstract void doDispose(const(DisposingReason) disposingReason) nothrow @safe;

private:
    LastDisposingReason _lastDisposingReason;
}

class DbNameObject : DbObject
{
nothrow @safe:

public:
    final int opCmp(scope const(DbIdentitier) rhsName) const pure
    {
        return _name.opCmp(rhsName);
    }

    final bool opEquals(scope const(DbIdentitier) rhsName) const pure
    {
        return opCmp(rhsName) == 0;
    }

    final override size_t toHash() const
    {
        return _name.toHash();
    }

    alias List = DbNameObjectList!DbNameObject;
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
        version(profile) debug auto p = PerfFunction.create();

        auto e = name in lookupItems;
        return e ? *e : null;
    }

    ///
    final T opIndex(string name) nothrow @safe
    {
        const id = DbIdentitier(name);
        return opIndex(id);
    }

    version(none)
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

    final int apply(scope int delegate(T e) nothrow dg) nothrow
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(this[i]))
                return r;
        }
        return 0;
    }

    final int apply(scope int delegate(size_t index, T e) nothrow dg) nothrow
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(i, this[i]))
                return r;
        }
        return 0;
    }

    typeof(this) clear() nothrow @trusted
    {
        lookupItems.clear();
        sequenceItems.length = 0;
        sequenceItems.assumeSafeAppend();
        flags.reset();
        return this;
    }

    final bool exist(scope const(DbIdentitier) name) const nothrow pure @safe
    {
        version(profile) debug auto p = PerfFunction.create();

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
        version(profile) debug auto p = PerfFunction.create();

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
            res = DbIdentitier(prefix ~ "_" ~ n.to!string());
        }
        while (exist(res));
        return res;
    }

    final T get(const(DbIdentitier) name) @safe
    {
        version(profile) debug auto p = PerfFunction.create();

        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
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
        version(profile) debug auto p = PerfFunction.create();

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

    final ptrdiff_t indexOfSafe(const(DbIdentitier) name) @safe
    {
        const result = indexOf(name);
        if (result < 0)
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
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

    T remove(size_t index) nothrow @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        auto result = this[index];
        result._list = null;
        lookupItems.remove(result.name);
        sequenceItems = sequenceItems.remove(index);
        sequenceItems.assumeSafeAppend();
        if (index < sequenceItems.length)
            flags += Flag.reIndex;
        return result;
    }

    final typeof(this) reserve(const(size_t) capacity) nothrow @trusted
    {
        if (capacity > sequenceItems.length)
        {
            sequenceItems.reserve(capacity);
            sequenceItems.assumeSafeAppend();
        }
        return this;
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
    enum Flag : ubyte
    {
        reIndex
    }

    T[DbIdentitier] lookupItems;
    T[] sequenceItems;
    EnumSet!Flag flags;
}

struct DbIdentitierValue(T)
{
nothrow @safe:

public:
    alias List = DbIdentitierValueList!T;
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

    int opCmp(scope const(DbIdentitier) rhsName) const
    {
        return _name.opCmp(rhsName);
    }

    bool opEquals(scope const(DbIdentitier) rhsName) const
    {
        return opCmp(rhsName) == 0;
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

class DbIdentitierValueList(T) : DbObject
{
@safe:

public:
    alias Pair = DbIdentitierValue!T;

public:
    /**
     * Implements range interface
     */
    static struct Range
    {
    nothrow @safe:

    public:
        alias List = DbIdentitierValueList!T;

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

    final int apply(scope int delegate(scope const ref Pair e) nothrow @safe dg) nothrow
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(this[i]))
                return r;
        }
        return 0;
    }

    final int apply(scope int delegate(size_t index, scope const ref Pair e) nothrow @safe dg) nothrow
    {
        foreach (i; 0..length)
        {
            if (auto r = dg(i, this[i]))
                return r;
        }
        return 0;
    }

    /**
     * Removes all the elements from the array
     */
    typeof(this) clear() nothrow @trusted
    {
        lookupItems.clear();
        sequenceNames.length = 0;
        sequenceNames.assumeSafeAppend();
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
            res = DbIdentitier(prefix ~ "_" ~ n.to!string());
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
    final T get(const(DbIdentitier) name)
    {
        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
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

    DbNameValueValidated isValid(const(DbIdentitier) name, T value) nothrow
    {
        return name.length != 0 ? DbNameValueValidated.ok : DbNameValueValidated.invalidName;
    }

    final DbNameValueValidated isValid(string name, T value) nothrow
    {
        const id = DbIdentitier(name);
        return isValid(id, value);
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

    final DbNameValueValidated putIf(DbIdentitier name, T value) nothrow
    {
        auto result = isValid(name, value);
        if (result == DbNameValueValidated.ok && exist(name))
            result = DbNameValueValidated.duplicateName;

        if (result == DbNameValueValidated.ok)
        {
            auto item = Pair(name, value);
            add(item);
        }

        return result;
    }

    final DbNameValueValidated putIf(string name, T value) nothrow
    {
        auto id = DbIdentitier(name, length);
        return putIf(id, value);
    }

    Pair remove(size_t index) nothrow @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        auto item = this[index];
        item._list = null;
        lookupItems.remove(item.name);
        sequenceNames = sequenceNames.remove(index);
        sequenceNames.assumeSafeAppend();
        if (index < sequenceNames.length)
            reIndex = true;
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

    final typeof(this) reserve(const(size_t) capacity) nothrow @trusted
    {
        if (capacity > sequenceNames.length)
        {
            sequenceNames.reserve(capacity);
            sequenceNames.assumeSafeAppend();
        }
        return this;
    }

    @property final size_t length() const nothrow pure
    {
        return sequenceNames.length;
    }

    /**
     * Returns value of name
     */
    @property final T value(const(DbIdentitier) name)
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
    DbIdentitier[] sequenceNames;
    bool reIndex;
}

/**
 * Returns a string of all elements in the table
 * Ex:
 *      name1=value1,name2=value2
 * Params:
 *      elementSeparator = is the separator character for each element
 *      valueSeparator = is the separator for each name & its value
 * Returns:
 *      string of all elements
 */
string getDelimiterText(T)(DbIdentitierValueList!T list,
    const(char) elementSeparator = ',',
    const(char) valueSeparator = '=') nothrow @safe
if (is(T == const(char)[]) || is(T == string))
{
    scope (failure) assert(0, "Assume nothrow failed");

    if (list.length == 0)
        return null;

    Appender!string result;
    result.reserve(min(list.length * 50, 16_000));
    size_t i;
    foreach (ref e; list[])
    {
        if (i++ != 0)
            result.put(elementSeparator);

        result.put(e.name.value);
        result.put(valueSeparator);
        result.put(e.value);
    }
    return result.data;
}

/**
 * Parse delimiter text into names & values. Beginning and ending spaces will be eliminated.
 * Ex:
 *      name1=value1,name2=value2
 * Params:
 *      values = a string of elements to be broken up
 *      elementSeparators = are the separator characters for each element
 *      valueSeparator = is the separator for each name & its value
 * Returns:
 *      self
 */
ResultIf!(DbIdentitierValueList!T) setDelimiterText(T)(DbIdentitierValueList!T list, string values,
    string elementSeparators = ",",
    char valueSeparator = '=') nothrow @safe
if (is(T == string))
in
{
    assert(elementSeparators.length != 0);
    assert(!isWhite(valueSeparator));
}
do
{
    list.clear();

    string errorMessage;
    size_t p;
    dchar cCode;
    ubyte cCount;

    bool isElementSeparator(const(dchar) c) nothrow @safe
    {
        foreach (i; 0..elementSeparators.length)
        {
            if (c == elementSeparators[i])
                return true;
        }
        return false;
    }

    string readName()
    {
        const begin = p;
        size_t end = values.length, lastSpace;
        while (p < values.length && nextUTF8Char(values, p, cCode, cCount))
        {
            if (isElementSeparator(cCode) || cCode == valueSeparator)
            {
                end = p;
                p += cCount;
                break;
            }
            else if (isWhite(cCode))
                lastSpace = p;
            else
                lastSpace = 0;
            p += cCount;
        }

        return lastSpace != 0 ? values[begin..lastSpace] : values[begin..end];
    }

    string readValue()
    {
        const begin = p;
        size_t end = values.length, lastSpace;
        while (p < values.length && nextUTF8Char(values, p, cCode, cCount))
        {
            if (isElementSeparator(cCode))
            {
                end = p;
                p += cCount;
                break;
            }
            else if (isWhite(cCode))
                lastSpace = p;
            else
                lastSpace = 0;
            p += cCount;
        }

        return lastSpace != 0 ? values[begin..lastSpace] : values[begin..end];
    }

    bool skipSpaces()
    {
        while (p < values.length)
        {
            if (nextUTF8Char(values, p, cCode, cCount))
            {
                if (!isWhite(cCode))
                    break;
            }
            p += cCount;
        }
        return p < values.length;
    }

    while (skipSpaces())
    {
        string value = null;
        string name = readName();
        if (skipSpaces())
            value = readValue();

        // Last element separator?
        if (name.length == 0 && value.length == 0 && p >= values.length)
            break;

        final switch (list.isValid(name, value)) with (DbNameValueValidated)
        {
            case invalidName:
                addLine(errorMessage, "Invalid name: " ~ name);
                break;
            case duplicateName:
                addLine(errorMessage, "Duplicate name: " ~ name);
                break;
            case invalidValue:
                addLine(errorMessage, "Invalid value of " ~ name ~ ": " ~ value);
                break;
            case ok:
                list.put(name, value);
                break;
        }
    }

    return errorMessage.length == 0
        ? ResultIf!(DbIdentitierValueList!T).ok(list)
        : ResultIf!(DbIdentitierValueList!T).error(list, DbErrorCode.parse, errorMessage);
}


// Any below codes are private
private:

unittest // DbIdentitierValueList
{
    import std.conv : to;
    import std.string : indexOf;

    auto list = new DbIdentitierValueList!string();
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

    static immutable delimiterText = "a=1,bcd=2, user id = 3, x=4 ";
    list.setDelimiterText(delimiterText, ",", '=');
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

unittest // DbCache
{
    import pham.utl.utl_array : indexOf;
    
    auto cache = new DbCache!int();
    scope (exit)
        cache.dispose();
        
    cache.add(1, new Object());
    cache.add(2, new Object());
    cache.add(3, new Object());
    cache.add(4, new Object());
    cache.add(5, new Object());
    
    const keys1 = cache.keys;
    assert(cache.length == 5);
    assert(keys1.indexOf(1) >= 0);
    assert(keys1.indexOf(2) >= 0);
    assert(keys1.indexOf(3) >= 0);
    assert(keys1.indexOf(4) >= 0);
    assert(keys1.indexOf(5) >= 0);
    
    Object found;
    assert(cache.find(1, found));
    assert(found !is null);
    assert(cache.find(2, found));
    assert(cache.find(3, found));
    assert(cache.find(4, found));
    assert(cache.find(5, found));
    assert(!cache.find(6, found));
    
    auto obj = new Object();
    cache.addOrReplace(5, obj);
    found = null;
    assert(cache.find(5, found));
    assert(found is obj);
    
    cache.remove(1);
    cache.remove(2);
    cache.remove(3);
    found = null;
    cache.remove(5, found);
    assert(found is obj);
    assert(cache.length == 1);
    assert(cache.keys == [4]);
}
