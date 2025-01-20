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

import core.atomic : cas;
import core.sync.mutex : Mutex;
import core.time : Duration, dur;
import std.algorithm : remove;
import std.algorithm.comparison : min;
import std.ascii : isWhite;
import std.conv : to;
import std.traits : isIntegral, isSomeString, ParameterTypeTuple, Unqual;
import std.uni : sicmp, toUpper;

debug(debug_pham_db_db_object) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.dtm.dtm_date : DateTime;
import pham.utl.utl_array : removeAt;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_disposable;
import pham.utl.utl_enum_set : EnumSet;
import pham.utl.utl_object : RAIIMutex, shortClassName;
import pham.utl.utl_result : addLine, ResultIf;
import pham.utl.utl_timer;
import pham.utl.utl_utf8 : nextUTF8Char, UTF8Iterator;
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

/**
 * Determine which based time to be used for checking to remove
 * a object from cache
 */
enum DbExpirationKind : ubyte
{
    /// Based on creation time
    created,

    /// Based on the last used
    lastTouched,
}

struct DbExpiration
{
nothrow @safe:

public:
    this(Duration maxAge, DbExpirationKind kind)
    {
        this.maxAge = maxAge;
        this.kind = kind;
        this.created = this.lastTouched = DateTime.utcNow;
    }

    /**
     * Return true if this cache object can be removed
     */
    bool canEvicted(scope const(DateTime) utcNow) const
    {
        if (maxAge <= Duration.zero)
            return false;

        return kind == DbExpirationKind.created
            ? ((utcNow - created).totalMinutes > maxAge.total!"minutes")
            : ((utcNow - lastTouched).totalMinutes > maxAge.total!"minutes");
    }

    /**
     * Update last used time to current time
     */
    void touch()
    {
        this.lastTouched = DateTime.utcNow;
    }

public:
    DateTime created;
    DateTime lastTouched;
    Duration maxAge;
    DbExpirationKind kind;
}

struct DbCacheItem(K)
if (isIntegral!K || isSomeString!K)
{
nothrow @safe:

public:
    /**
     * Construct a cache object
     *  key = a cached key
     *  item = a cached object
     *  maxAge = the maximum duration a cached object stayed in cache
     *           a zero/nagetive value is unlimit
     *  kind = which based time (created or last used) being used for checking cache lifetime
     */
    this(K key, Object item, Duration maxAge, DbExpirationKind kind)
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

    /**
     * Return true if this cache object can be removed
     */
    pragma(inline, true)
    bool canEvicted(scope const(DateTime) utcNow) const
    {
        return _expiration.canEvicted(utcNow);
    }

    /**
     * Update last used time to current time
     */
    pragma(inline, true)
    V touch(V : Object)()
    {
        this._expiration.touch();
        return cast(V)item;
    }

    /**
     * Update this cache item with new cached object
     * Params:
     *  item = an object being cached
     *  maxAge = the maximum duration a cached object stayed in cache
     *           a zero/nagetive value is unlimit
     *  kind = which based time (created or last used) being used for checking cache lifetime
     */
    V touch(V : Object)(V item, Duration maxAge, DbExpirationKind kind)
    {
        this._expiration = DbExpiration(maxAge, kind);
        this.item = item;
        return item;
    }

    /**
     * Time of a object put into cache
     */
    @property DateTime created() const
    {
        return _expiration.created;
    }

    /**
     * Cached key
     */
    @property K key() const
    {
        return _key;
    }

    /**
     * Last time of cached object being used
     */
    @property DateTime lastTouched() const
    {
        return _expiration.lastTouched;
    }

    /**
     * Maximum duration a cached object stayed in cache
     * The value of zero/negative is unlimit
     */
    @property Duration maxAge() const
    {
        return _expiration.maxAge;
    }
public:
    /**
     * Cached object
     */
    Object item;

private:
    K _key;
    DbExpiration _expiration;
}

class DbCache(K) : DbDisposableObject
if (isIntegral!K || isSomeString!K)
{
nothrow @safe:

    enum defaultMaxAge = dur!"hours"(8);
    enum defaultKind = DbExpirationKind.created;

public:
    this(Timer secondTimer)
    {
        this.secondTimer = secondTimer;
        this.mutex = new Mutex();
    }

    final bool add(V : Object)(K key, V item,
        Duration maxAge = defaultMaxAge,
        DbExpirationKind kind = defaultKind)
    {
        registerWithTimer();

        auto raiiMutex = RAIIMutex(mutex);

        if (auto e = key in items)
        {
            if (!(*e).canEvicted(DateTime.utcNow))
                return false;

            (*e).touch!V(item, maxAge, kind);
            return true;
        }

        items[key] = DbCacheItem!K(key, item, maxAge, kind);
        return true;
    }

    final V addOrReplace(V : Object)(K key, V item,
        Duration maxAge = defaultMaxAge,
        DbExpirationKind kind = defaultKind)
    {
        registerWithTimer();

        auto raiiMutex = RAIIMutex(mutex);

        if (auto e = key in items)
            (*e).touch!V(item, maxAge, kind);
        else
            items[key] = DbCacheItem!K(key, item, maxAge, kind);
        return item;
    }

    final size_t cleanupInactives() @safe
    {
        auto inactives = removeInactives();

        version(none)
        foreach (inactive; inactives)
            inactive.dispose();

        return inactives.length;
    }

    final bool find(V : Object)(K key, ref V found)
    {
        auto raiiMutex = RAIIMutex(mutex);

        return findImpl!V(key, found) == FindResult.found;
    }

    final bool remove(K key)
    {
        auto raiiMutex = RAIIMutex(mutex);

        return items.remove(key);
    }

    final bool remove(V : Object)(K key, ref V found)
    {
        auto raiiMutex = RAIIMutex(mutex);

        final switch (findImpl!V(key, found))
        {
            case FindResult.found:
                return items.remove(key);
            case FindResult.unfound:
                return false;
            case FindResult.expired:
                items.remove(key);
                return false;
        }
    }

    @property final const(K)[] keys()
    {
        auto raiiMutex = RAIIMutex(mutex);

        return items.keys;
    }

    @property final size_t length()
    {
        auto raiiMutex = RAIIMutex(mutex);

        return items.length;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @trusted
    {
        unregisterWithTimer();
        secondTimer = null;

        items.clear();

        if (mutex !is null)
        {
            mutex.destroy();
            mutex = null;
        }
    }

    final void doTimer(TimerEvent event)
    {
        cleanupInactives();
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
            if ((*e).canEvicted(DateTime.utcNow))
                return FindResult.expired;

            found = (*e).touch!V();
            return FindResult.found;
        }
        else
            return FindResult.unfound;
    }

    final void registerWithTimer()
    {
        if (cas(&timerAdded, false, true) && secondTimer !is null)
            secondTimer.addEvent(TimerEvent(timerName(), dur!"minutes"(1), &doTimer));
    }

    final DbCacheItem!K[] removeInactives()
    {
        auto raiiMutex = RAIIMutex(mutex);

        if (items.length == 0)
            return null;

        const utcNow = DateTime.utcNow;
        DbCacheItem!K[] result;
        result.reserve(items.length / 2);

        // Get all inactive ones
        foreach (ref item; items.byValue)
        {
            if (item.canEvicted(utcNow))
                result ~= item;
        }

        // Remove from cache list
        foreach (ref item; result)
            items.remove(item.key);

        return result;
    }

    final string timerName() nothrow pure @trusted
    {
        import pham.utl.utl_object : toString;

        static immutable string prefix = "DbCache_";
        auto buffer = Appender!string(prefix.length + size_t.sizeof * 2);
        buffer.put(prefix);
        return toString!16(buffer, cast(size_t)(cast(void*)this)).data;
    }

    final unregisterWithTimer()
    {
        if (cas(&timerAdded, true, false) && secondTimer !is null)
            secondTimer.removeEvent(timerName());
    }

private:
    Mutex mutex;
    Dictionary!(K, DbCacheItem!K) items;
    Timer secondTimer;
    bool timerAdded;
}

struct DbCustomAttributeList
{
nothrow @safe:

public:
    string opIndex(string name)
    {
        return values.get(name);
    }

    ref typeof(this) opIndexAssign(string value, string name) return
    {
        this.put(name, value);
        return this;
    }

    bool hasValue(string name, out string value)
    {
        value = values.get(name);
        return value.length != 0;
    }

    string put(string name, string value)
    in
    {
        assert(name.length != 0);
    }
    do
    {
        if (value.length)
            values[name] = value;
        else
            values.remove(name);
        return value;
    }

    @property bool empty() const nothrow
    {
        return values.empty;
    }

    @property size_t length() const nothrow
    {
        return values.length;
    }

    Dictionary!(string, string) values;
    alias values this;
}

struct DbIdentitier
{
nothrow @safe:

public:
    this(string value) pure
    {
        this._s = value;
    }

    auto ref opOpAssign(string op)(DbIdentitier value) return
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

    bool opCast(B: bool)() const
    {
        return _s.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbIdentitier opCast(T)() const
    if (is(Unqual!T == DbIdentitier))
    {
        return this;
    }

    int opCmp(scope const(DbIdentitier) rhs) const
    {
        return sicmp(_s, rhs._s);
    }

    int opCmp(scope const(char)[] rhs) const
    {
        return sicmp(_s, rhs);
    }

    bool opEquals(scope const(DbIdentitier) rhs) const
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(char)[] rhs) const
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const
    {
        return hashOf(ivalue);
    }

    string toString() const
    {
        return _s;
    }

    @property string ivalue() const
    {
	    scope (failure) assert(0, "Assume nothrow failed");

        return toUpper(_s);
    }

    @property size_t length() const
    {
        return _s.length;
    }

    @property string value() const
    {
        return _s;
    }

    alias value this;

private:
    string _s;
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
    final int opCmp(scope const(DbIdentitier) rhsName) const
    {
        return _name.opCmp(rhsName);
    }

    final bool opEquals(scope const(DbIdentitier) rhsName) const
    {
        return opCmp(rhsName) == 0;
    }

    final override size_t toHash() const
    {
        return _name.toHash();
    }

    final void updateName(DbIdentitier newName)
    {
        updateNameImpl(newName);
    }

    final void updateName(string newName)
    {
        updateNameImpl(DbIdentitier(newName));
    }

    alias List = DbNameObjectList!DbNameObject;
    @property final List list() pure @trusted
    {
        return cast(List)_list;
    }

    @property final DbIdentitier name() const
    {
        return _name;
    }

protected:
    //pragma(inline, true)
    final void updateNameImpl(DbIdentitier newName)
    {
        if (_name != newName)
        {
            auto oldName = _name;
            _name._s = newName._s;

            if (auto lst = list)
                lst.nameChanged(this, oldName);
        }
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
        @property bool empty() const
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

        @property size_t index() const
        {
            return _index;
        }

    private:
        List _list;
        size_t _index;
    }

public:
    alias opApply = opApplyImpl!(int delegate(T));
    alias opApply = opApplyImpl!(int delegate(size_t, T));

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(size_t, T)))
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "()");

        static if (is(CallBack : int delegate(T)))
        {
            foreach (ref e; sequenceItems)
            {
                if (const r = callBack(e.item))
                    return r;
            }
        }
		else
        {
            foreach (i; 0..sequenceItems.length)
            {
                if (const r = callBack(i, sequenceItems[i].item))
                    return r;
            }
        }
        return 0;
    }

    /**
     * Returns range interface
     */
    Range opIndex() nothrow @safe
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "()");

        return Range(this);
    }

    /**
     * Returns item at index
     */
    final T opIndex(size_t index) const nothrow @trusted
    in
    {
        assert(index < sequenceItems.length);
    }
    do
    {
        return cast()sequenceItems[index].item;
    }

    /**
     * Returns item with matching name
     */
    final T opIndex(scope const(DbIdentitier) name) const nothrow @safe
    {
        return opIndexImpl(name);
    }

    final T opIndex(string name) const nothrow @safe
    {
        return opIndexImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final T opIndexImpl(scope const(DbIdentitier) name) const nothrow @trusted
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const i = indexOf(name);
        return i >= 0 ? cast()sequenceItems[i].item : null;
    }

    typeof(this) clear() nothrow @trusted
    {
        lookupNames.clear();
        sequenceItems.length = 0;
        sequenceItems.assumeSafeAppend();
        return this;
    }

    final bool exist(scope const(DbIdentitier) name) const nothrow @safe
    {
        return existImpl(name);
    }

    final bool exist(string name) const nothrow @safe
    {
        return existImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final bool existImpl(scope const(DbIdentitier) name) const nothrow @safe
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const e = name in lookupNames;
        return e !is null;
    }

    final bool find(scope const(DbIdentitier) name, out T item) const nothrow @safe
    {
        return findImpl(name, item);
    }

    final bool find(string name, out T item) const nothrow @safe
    {
        return findImpl(DbIdentitier(name), item);
    }

    pragma(inline, true)
    private final bool findImpl(scope const(DbIdentitier) name, out T item) const nothrow @trusted
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const i = indexOf(name);
        if (i >= 0)
        {
            item = cast()sequenceItems[i].item;
            return true;
        }
        else
        {
            item = null;
            return false;
        }
    }

    final DbIdentitier generateUniqueName(string prefix) const nothrow @safe
    {
        DbIdentitier result;
        size_t n = length;
        do
        {
            ++n;
            result = DbIdentitier(prefix ~ "_" ~ n.to!string());
        }
        while (exist(result));
        return result;
    }

    final T get(const(DbIdentitier) name) const @safe
    {
        return getImpl(name);
    }

    final T get(string name) const @safe
    {
        return getImpl(DbIdentitier(name));
    }

    //pragma(inline, true)
    private final T getImpl(const(DbIdentitier) name) const @safe
    {
        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
        }
        return result;
    }

    final ptrdiff_t indexOf(scope const(DbIdentitier) name) const nothrow @safe
    {
        return indexOfImpl(name);
    }

    final ptrdiff_t indexOf(string name) const nothrow @safe
    {
        return indexOfImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final ptrdiff_t indexOfImpl(scope const(DbIdentitier) name) const nothrow @safe
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const e = name in lookupNames;
        const ptrdiff_t result = e !is null ? (*e) : -1;

        debug(debug_pham_db_db_object) debug writeln("\t", "result=", result, ", length=", length);

        return result;
    }

    final ptrdiff_t indexOfSafe(const(DbIdentitier) name) const @safe
    {
        return indexOfSafeImpl(name);
    }

    final ptrdiff_t indexOfSafe(string name) const @safe
    {
        return indexOfSafeImpl(DbIdentitier(name));
    }

    //pragma(inline, true)
    private final ptrdiff_t indexOfSafeImpl(const(DbIdentitier) name) const @safe
    {
        const result = indexOf(name);
        if (result < 0)
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
        }
        return result;
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

    T remove(const(size_t) index) nothrow @trusted
    in
    {
        assert(index < sequenceItems.length);
    }
    do
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(index=", index, ")");

        auto result = sequenceItems[index];
        result.item._list = null;
        lookupNames.remove(result.item.name);
        sequenceItems.removeAt(index);
        sequenceItems.assumeSafeAppend();
        if (index < sequenceItems.length)
            reIndexItems(index);
        return result.item;
    }

    final T remove(scope const(DbIdentitier) name) nothrow @safe
    {
        return removeImpl(name);
    }

    final T remove(string name) nothrow @safe
    {
        return removeImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final T removeImpl(scope const(DbIdentitier) name) nothrow @safe
    {
        const i = indexOf(name);
        return i >= 0 ? remove(i) : null;
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

    @property final size_t length() const nothrow @safe
    {
        return sequenceItems.length;
    }

protected:
    struct SequenceItem
    {
        T item;
        ptrdiff_t index;
    }

    void add(T item) nothrow @trusted
    {
        const lastIndex = sequenceItems.length;
        item._list = cast(void*)this;
        lookupNames[item.name] = lastIndex;
        sequenceItems ~= SequenceItem(item, lastIndex);

        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(item._name=", item._name, ", index=", lastIndex, ", length=", length, ")");
    }

    void addOrSet(T item) nothrow @trusted
    {
        const i = indexOf(item.name);
        if (i >= 0)
        {
            debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(item._name=", item._name, ", index=", i, ", length=", length, ")");

            item._list = cast(void*)this;
            //lookupNames[item.name] = i;
            sequenceItems[i] = SequenceItem(item, i);
        }
        else
            add(item);
    }

    void nameChanged(T item, scope const(DbIdentitier) oldName) nothrow @safe
    {
        const oldIndex = indexOf(oldName);
        lookupNames.remove(oldName);
        lookupNames[item.name] = oldIndex;
    }

    final void reIndexItems(const(size_t) beginIndex) nothrow @safe
    in
    {
        assert(beginIndex <= sequenceItems.length);
    }
    do
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(beginIndex=", beginIndex,
            ", sequenceItems.length=", sequenceItems.length, ")");

        foreach (i, ref e; sequenceItems[beginIndex..$])
        {
            const newIndex = beginIndex + i;
            e.index = newIndex;
            lookupNames[e.item.name] = newIndex;
            
            debug(debug_pham_db_db_object) debug writeln("\t", "e.item.name=", e.item.name, ", newIndex=", newIndex);            
        }
    }

protected:
    size_t[DbIdentitier] lookupNames;
    SequenceItem[] sequenceItems;
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
        this._name = DbIdentitier(name);
        this.value = value;
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
    ptrdiff_t _index; // Since it is a struct, index can be declared here
}

class DbIdentitierValueList(T) : DbObject
{
@safe:

public:
    alias DbIdentitierValuePair = DbIdentitierValue!T;

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
        void popFront()
        {
            ++_index;
        }

        auto save()
        {
            return this;
        }

        pragma(inline, true)
        @property bool empty() const
        {
            return _index >= _list.length;
        }

        pragma(inline, true)
        @property DbIdentitierValuePair front()
        in
        {
            assert(_index < _list.length);
        }
        do
        {
            return _list[_index];
        }

        @property size_t index() const
        {
            return _index;
        }

    private:
        List _list;
        size_t _index;
    }

public:
    alias opApply = opApplyImpl!(int delegate(ref DbIdentitierValuePair));
    alias opApply = opApplyImpl!(int delegate(size_t, ref DbIdentitierValuePair));

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(ref DbIdentitierValuePair)) || is(CallBack : int delegate(size_t, ref DbIdentitierValuePair)))
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "()");

        static if (is(CallBack : int delegate(ref DbIdentitierValuePair)))
        {
            foreach (ref e; sequenceItems)
            {
                if (const r = callBack(e))
                    return r;
            }
        }
		else
        {
            foreach (i; 0..sequenceItems.length)
            {
                if (const r = callBack(i, sequenceItems[i]))
                    return r;
            }
        }
        return 0;
    }

    /**
     * Returns range interface
     */
    Range opIndex() nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "()");

        return Range(this);
    }

    /**
     * Returns item at index
     */
    final DbIdentitierValuePair opIndex(size_t index) const nothrow @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        return cast()sequenceItems[index];
    }

    /**
     * Removes all the elements from the array
     */
    typeof(this) clear() nothrow @trusted
    {
        lookupNames.clear();
        sequenceItems.length = 0;
        sequenceItems.assumeSafeAppend();
        return this;
    }

    /**
     * Returns true if name is in list; otherwise false
     *  Params:
     *      name = a name to be search for
     */
    final bool exist(scope const(DbIdentitier) name) const nothrow
    {
        return existImpl(name);
    }

    final bool exist(string name) const nothrow
    {
        return existImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final bool existImpl(scope const(DbIdentitier) name) const nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const e = name in lookupNames;
        return e !is null;
    }

    final bool find(scope const(DbIdentitier) name, out T item) const nothrow
    {
        return findImpl(name, item);
    }

    final bool find(string name, out T item) const nothrow
    {
        return findImpl(DbIdentitier(name), item);
    }

    pragma(inline, true)
    private final bool findImpl(scope const(DbIdentitier) name, out T item) const nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const i = indexOf(name);
        if (i >= 0)
        {
            item = sequenceItems[i].value;
            return true;
        }
        else
        {
            item = T.init;
            return false;
        }
    }

    final DbIdentitier generateUniqueName(string prefix) const nothrow
    {
        DbIdentitier result;
        size_t n = length;
        do
        {
            ++n;
            result = DbIdentitier(prefix ~ "_" ~ n.to!string());
        }
        while (exist(result));
        return result;
    }

    /**
     * Returns value of name if name is in list; otherwise null
     *  Params:
     *      name = is the name to look for
     *  Returns:
     *      string value of name
     */
    final T get(const(DbIdentitier) name) const
    {
        return getImpl(name);
    }

    final T get(string name) const
    {
        return getImpl(DbIdentitier(name));
    }

    //pragma(inline, true)
    private final T getImpl(const(DbIdentitier) name) const
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        T result;
        if (!find(name, result))
        {
            auto msg = DbMessage.eInvalidName.fmtMessage(name, shortClassName(this));
            throw new DbException(0, msg);
        }
        return result;
    }

    final ptrdiff_t indexOf(scope const(DbIdentitier) name) const nothrow
    {
        return indexOfImpl(name);
    }

    final ptrdiff_t indexOf(string name) const nothrow
    {
        return indexOfImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final ptrdiff_t indexOfImpl(scope const(DbIdentitier) name) const nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const e = name in lookupNames;
        const ptrdiff_t result = e !is null ? (*e) : -1;

        debug(debug_pham_db_db_object) debug writeln("\t", "r=", result, ", length=", length);

        return result;
    }

    final DbNameValueValidated isValid(const(DbIdentitier) name, T value) const nothrow
    {
        return isValidImpl(name, value);
    }

    final DbNameValueValidated isValid(string name, T value) const nothrow
    {
        return isValidImpl(DbIdentitier(name), value);
    }

    protected DbNameValueValidated isValidImpl(const(DbIdentitier) name, T value) const nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        return name.length != 0 ? DbNameValueValidated.ok : DbNameValueValidated.invalidName;
    }

    final typeof(this) put(DbIdentitier name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        return putImpl(name, value);
    }

    final typeof(this) put(string name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        return putImpl(DbIdentitier(name), value);
    }

    pragma(inline, true)
    private final typeof(this) putImpl(DbIdentitier name, T value) nothrow
    in
    {
        assert(name.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        auto item = DbIdentitierValuePair(name, value);
        addOrSet(item);
        return this;
    }

    final DbNameValueValidated putIf(DbIdentitier name, T value) nothrow
    {
        return putIfImpl(name, value);
    }

    final DbNameValueValidated putIf(string name, T value) nothrow
    {
        return putIfImpl(DbIdentitier(name), value);
    }

    pragma(inline, true)
    private final DbNameValueValidated putIfImpl(DbIdentitier name, T value) nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        auto result = isValid(name, value);
        if (result == DbNameValueValidated.ok && exist(name))
            result = DbNameValueValidated.duplicateName;

        if (result == DbNameValueValidated.ok)
        {
            auto item = DbIdentitierValuePair(name, value);
            add(item);
        }

        return result;
    }

    DbIdentitierValuePair remove(const(size_t) index) nothrow @trusted
    in
    {
        assert(index < sequenceItems.length);
    }
    do
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(index=", index, ")");

        auto item = sequenceItems[index];
        item._list = null;
        lookupNames.remove(item.name);
        sequenceItems.removeAt(index);
        sequenceItems.assumeSafeAppend();
        if (index < sequenceItems.length)
            reIndexItems(index);
        return item;
    }

    /**
     * Remove a string-name, name, from list
     * Params:
     *  name = is the name
     */
    final DbIdentitierValuePair remove(scope const(DbIdentitier) name) nothrow
    {
        return removeImpl(name);
    }

    final DbIdentitierValuePair remove(string name) nothrow
    {
        return removeImpl(DbIdentitier(name));
    }

    pragma(inline, true)
    private final DbIdentitierValuePair removeImpl(scope const(DbIdentitier) name) nothrow
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(name=", name, ")");

        const i = indexOf(name);
        return i >= 0 ? remove(i) : DbIdentitierValuePair.init;
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

    @property final size_t length() const nothrow
    {
        return sequenceItems.length;
    }

    /**
     * Returns value of name
     */
    @property final T value(const(DbIdentitier) name) const
    {
        return get(name);
    }

    /**
     * Returns value of name
     */
    @property final T value(string name) const
    {
        return get(name);
    }

    @property final typeof(this) value(DbIdentitier name, T value)
    {
        return put(name, value);
    }

    @property final typeof(this) value(string name, T value)
    {
        return put(name, value);
    }

protected:
    void add(ref DbIdentitierValuePair item) nothrow
    {
        const lastIndex = sequenceItems.length;
        item._list = this;
        item._index = lastIndex;
        lookupNames[item.name] = lastIndex;
        sequenceItems ~= item;

        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(item._name=", item._name, ", index=", lastIndex, ", length=", length, ")");
    }

    void addOrSet(ref DbIdentitierValuePair item) nothrow
    {
        const i = indexOf(item.name);
        if (i >= 0)
        {
            debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(item._name=", item._name, ", index=", i, ", length=", length, ")");

            item._list = this;
            item._index = i;
            //lookupNames[item.name] = i;
            sequenceItems[i] = item;
        }
        else
            add(item);
    }

    version(none)
    void nameChanged(ref DbIdentitierValuePair item, scope const(DbIdentitier) oldName) nothrow
    {
        lookupNames.remove(oldName);
        lookupNames[item.name] = item.index;
    }

    final void reIndexItems(const(size_t) beginIndex) nothrow
    in
    {
        assert(beginIndex <= sequenceItems.length);
    }
    do
    {
        debug(debug_pham_db_db_object) debug writeln(__FUNCTION__, "(beginIndex=", beginIndex,
            ", sequenceItems.length=", sequenceItems.length, ")");

        foreach (i, ref e; sequenceItems[beginIndex..$])
        {
            const newIndex = beginIndex + i;
            e._index = newIndex;
            lookupNames[e.name] = newIndex;
            
            debug(debug_pham_db_db_object) debug writeln("\t", "e.name=", e.name, ", newIndex=", newIndex);            
        }
    }

protected:
    size_t[DbIdentitier] lookupNames;
    DbIdentitierValuePair[] sequenceItems;
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

    auto result = Appender!string(min(list.length * 50, 16_000));
    foreach (e; list)
    {
        if (result.length)
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
        UTF8Iterator interator;
        const begin = p;
        size_t end = values.length, lastSpace;
        while (p < values.length && nextUTF8Char(values, p, interator.code, interator.count))
        {
            if (interator.code == valueSeparator || isElementSeparator(interator.code))
            {
                end = p;
                p += interator.count;
                break;
            }
            else if (isWhite(interator.code))
                lastSpace = p;
            else
                lastSpace = 0;
            p += interator.count;
        }

        return lastSpace != 0 ? values[begin..lastSpace] : values[begin..end];
    }

    string readValue()
    {
        UTF8Iterator interator;
        const begin = p;
        size_t end = values.length, lastSpace;
        while (p < values.length && nextUTF8Char(values, p, interator.code, interator.count))
        {
            if (isElementSeparator(interator.code))
            {
                end = p;
                p += interator.count;
                break;
            }
            else if (isWhite(interator.code))
                lastSpace = p;
            else
                lastSpace = 0;
            p += interator.count;
        }

        return lastSpace != 0 ? values[begin..lastSpace] : values[begin..end];
    }

    bool skipSpaces()
    {
        UTF8Iterator interator;
        while (p < values.length)
        {
            if (nextUTF8Char(values, p, interator.code, interator.count))
            {
                if (!isWhite(interator.code))
                    break;
            }
            p += interator.count;
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

    debug(debug_pham_db_db_object) debug writeln("unittest.DbIdentitierValueList");

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

    debug(debug_pham_db_db_object) debug writeln("unittest.DbNameObjectList");

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
    debug(debug_pham_db_db_object) debug writeln("unittest.DbCustomAttributeList");

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

    debug(debug_pham_db_db_object) debug writeln("unittest.DbCache");

    auto cache = new DbCache!int(null);
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
