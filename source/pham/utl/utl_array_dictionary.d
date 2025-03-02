/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_array_dictionary;

import std.traits : fullyQualifiedName, isAssignable, Unqual;

debug(debug_pham_utl_utl_array_dictionary)
{
    import std.stdio : writeln;
    int aaCanLog;
}
import pham.utl.utl_array : arrayFree, arrayZeroInit;
import pham.utl.utl_prime;
//import pham.utl.utl_array_append : Appender;

enum DictionaryHashMix : ubyte
{
    none,
    murmurHash2,
    murmurHash3,
}

/**
 * Represents a collection of key/value pairs that are accessible by the key.
 * The order of added items are reserved
 */
struct Dictionary(K, V)
{
    import core.exception : RangeError;
    private alias UK = Unqual!K;
    private alias UV = Unqual!V;
    private enum bool isAssignableKV = isAssignable!K && isAssignable!V;
    private enum ushort bucketInflated = 5;

    static if (is(K == string) || is(K == wstring) || is(K == dstring))
    {
        import pham.utl.utl_trait : ElementTypeOf;

        alias KE = ElementTypeOf!K;
        //pragma(msg, "K=" ~ K.stringof ~ ", KE=" ~ KE.stringof);

        alias CustomHashOf = size_t function(scope const(KE)[]) @nogc nothrow pure @safe;
    }
    else
    {
        alias CustomHashOf = size_t function(ref const(K)) @nogc nothrow pure @safe;
    }

public:
    /**
     * Construct a Dictionary from a build-in associated array
     * Params:
     *  other = source data from a build-in associated array
     *  hashMix = optionally mixing hash value logic
     *  customHashOf = a customized function to calculate hash value from key
     */
    this(OK, OV)(OV[OK] other,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null)
    if (is(OK : K) && is(OV : V))
    {
        //pragma(msg, "this(OK, OV)(buildin." ~ OK.stringof ~ " vs " ~ K.stringof ~ ")");
        //pragma(msg, "this(OK, OV)(buildin." ~ OV.stringof ~ " vs " ~ V.stringof ~ ")");

        opAssignImpl(other, hashMix, customHashOf);
    }

    /**
     * Construct a Dictionary from an other Dictionary with similar types
     * Params:
     *  other = source data from an other Dictionary with similar types
     *  hashMix = optionally mixing hash value logic
     *  customHashOf = a customized function to calculate hash value from key
     */
    this(OK, OV)(Dictionary!(OK, OV) other,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null) nothrow
    if (is(OK : K) && is(OV : V))
    {
        //pragma(msg, "this(OK, OV)(Dictionary." ~ OK.stringof ~ " vs " ~ K.stringof ~ ")");
        //pragma(msg, "this(OK, OV)(Dictionary." ~ OV.stringof ~ " vs " ~ V.stringof ~ ")");

        opAssignImpl(other, hashMix, customHashOf);
    }

    /**
     * Constructs a Dictionary with a given capacity buckets & key-value pairs for appending.
     * Avoid reallocate memory while populating the Dictionary instant
     * Params:
     *  bucketCapacity = reserved number of buckets for appending
     *  entryCapacity = reserved number of key-value pairs for appending
     *  hashMix = optionally mixing hash value logic
     *  customHashOf = a customized function to calculate hash value from key
     */
    this(size_t bucketCapacity, size_t entryCapacity,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null) nothrow @safe
    in
    {
        assert(bucketCapacity >= entryCapacity);
    }
    do
    {
        this.aa = createAA(bucketCapacity, entryCapacity, hashMix, customHashOf);
    }

    /**
     * Supports build-in foreach operator
     */
    static if (V.sizeof <= size_t.sizeof)
    {
        alias opApply = opApplyImpl!(int delegate(V));
        alias opApply = opApplyImpl!(int delegate(const(K), V));
    }
    else
    {
        alias opApply = opApplyImpl!(int delegate(ref V));
        alias opApply = opApplyImpl!(int delegate(const(K), ref V));
    }

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(V)) || is(CallBack : int delegate(ref V))
        || is(CallBack : int delegate(const(K), V)) || is(CallBack : int delegate(const(K), ref V)))
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        if (length)
        {
            static if (is(CallBack : int delegate(V)) || is(CallBack : int delegate(ref V)))
            {
                foreach (ref e; aa.entries)
                {
                    if (const r = callBack(e.value))
                        return r;
                }
            }
            else
            {
                foreach (ref e; aa.entries)
                {
                    if (const r = callBack(e.key, e.value))
                        return r;
                }
            }
        }

        return 0;
    }

    /**
     * Reset this Dictionary instant from a build-in associated array
     * Params:
     *  rhs = source data from a build-in associated array
     */
    ref typeof(this) opAssign(OK, OV)(OV[OK] rhs) return
    if (is(OK : K) && is(OV : V))
    {
        opAssignImpl(rhs);
        return this;
    }

    private void opAssignImpl(OK, OV)(OV[OK] rhs,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null)
    if (is(OK : K) && is(OV : V))
    {
        const ol = rhs.length;
        if (ol || hashMix != DictionaryHashMix.none || customHashOf !is null)
        {
            this.aa = createAA(ol != 0 ? (ol + bucketInflated) : 0, ol, hashMix, customHashOf);
            if (ol)
            {
                foreach (k, v; rhs)
                    this.aa.add(k, v);
            }
        }
        else
            this.aa = null;
    }

    /**
     * Reset this Dictionary instant from an other Dictionary with similar types
     * Params:
     *  rhs = source data from an other Dictionary with similar types
     *        if rhs type is exact with the Dictionary, it will only set the internal implementation
     *        which behaves like class/object assignment (no data copy taken place)
     */
    ref typeof(this) opAssign(OK, OV)(Dictionary!(OK, OV) rhs) nothrow return
    if (is(OK : K) && is(OV : V))
    {
        opAssignImpl(rhs);
        return this;
    }

    private void opAssignImpl(OK, OV)(Dictionary!(OK, OV) rhs,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null) nothrow
    {
        static if (is(OK == K) && is(OV == V))
        {
            if (rhs.aa && rhs.aa.hashMix == hashMix && rhs.aa.customHashOf is customHashOf)
            {
                this.aa = rhs.aa;
                return;
            }
        }

        // Build manually
        const ol = rhs.length;
        if (ol || hashMix != DictionaryHashMix.none || customHashOf !is null)
        {
            this.aa = createAA(ol != 0 ? (ol + rhs.collisionCount + bucketInflated) : 0, ol, hashMix, customHashOf);
            if (ol)
            {
                foreach (ref e; rhs.aa.entries)
                    this.aa.add(e._key, e.value);
            }
        }
        else
            this.aa = null;
    }

    /**
     * Support build-in IN operator
     * Returns null if key does not exist
     * Params:
     *  key = the key of the value to get
     */
    inout(V)* opBinaryRight(string op)(scope const(K) key) inout nothrow return
    if (op == "in")
    {
        return length != 0 ? aa.find(key) : null;
    }

    static if (is(K == string) || is(K == wstring) || is(K == dstring))
    inout(V)* opBinaryRight(string op)(scope const(KE)[] key) inout nothrow return
    if (op == "in")
    {
        return length != 0 ? aa.find(key) : null;
    }

    /**
     * Support build-in EQUAL operator.
     * Returns true if having same length, keys & values
     */
    bool opEquals(OK, OV)(scope const(Dictionary!(OK, OV)) rhs) const nothrow
    if (is(OK : K) && is(OV : V))
    {
        //pragma(msg, "opEquals(OK, OV)(" ~ OK.stringof ~ " vs " ~ K.stringof ~ ")");
        //pragma(msg, "opEquals(OK, OV)(" ~ OV.stringof ~ " vs " ~ V.stringof ~ ")");

        if (this.length != rhs.length)
            return false;

        if (this.length == 0)
            return true;

        foreach (ref e; aa.entries)
        {
            if (auto ov = rhs.aa.find(e._key))
            {
                if (e.value != *ov)
                    return false;
            }
            else
                return false;
        }

        return true;
    }

    /**
     * Returns the value of key.
     * Will throw RangeError if key not found
     * Params:
     *  key = the key of the value to get
     */
    ref V opIndex(scope const(K) key,
        string file = __FILE__, uint line = __LINE__) return
    {
        if (auto v = key in this)
            return *v;

        throw new RangeError(file, line);
    }

    /**
     * Gets or sets the value associated with the specified key
     * Params:
     *  value = the value being added or modified
     *  key = gets or sets the value associated with the specified key
     * Returns:
     *  The value being added
     */
    ref V opIndexAssign()(auto ref V value, K key) return
    {
        if (!aa)
            aa = createAA(0, 0);

        return aa.put(key, value);
    }

    /**
     * Returns a key & value range
     */
    alias opSlice = byKeyValue;

    /**
     * Removes all keys and values
     */
    ref typeof(this) clear() nothrow pure return
    {
        if (length)
            aa.clear();

        return this;
    }

    /**
     * Returns true if the given key is in the Dictionary. Otherwise, it returns false
     * Params:
     *  key = the key of the value to find
     */
    bool containKey(scope const(K) key) const nothrow
    {
        return length != 0 && aa.find(key) !is null;
    }

    /**
     * Returns true if the given key is in the Dictionary and provides its value in Value. Otherwise, it returns false
     * Params:
     *  key = the key of the value to find
     *  value = the variable to hold the found key's value
     */
    static if (isAssignable!V)
    bool containKey(scope const(K) key, ref V value) nothrow
    {
        if (length != 0)
        {
            if (auto f = aa.find(key))
            {
                value = *f;
                return true;
            }
        }

        return false;
    }

    /**
     * Returns a duplicate of the Dictionary
     */
    typeof(this) dup()
    {
        const len = length;
        if (len == 0)
            return typeof(this).init;

        auto result = typeof(this)(len + collisionCount + bucketInflated, len, this.aa.hashMix, this.aa.customHashOf);
        foreach (ref e; this.aa.entries)
            result.aa.add(e.hash, e._key, e.value);
        return result;
    }

    /**
     * Returns the value of key.
     * If the key if not found, defaultValue is returned
     * Params:
     *  key = the key of the value to get
     *  defaultValue = the default value being returned if the key is not found
     */
    inout(V) get(scope const(K) key, lazy inout(V) defaultValue = V.init) inout nothrow // lazy does not infer nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        if (length != 0)
        {
            if (auto f = aa.find(key))
                return *f;
        }

        return defaultValue;
    }

    /**
     * Returns the value at index.
     * If the index is out of bound, defaultValue is returned
     * Params:
     *  index = the location of key-value pair
     *  defaultValue = the default value being returned if the index is out of bound
     */
    inout(V) getAt(size_t index, lazy inout(V) defaultValue = V.init) inout nothrow // lazy does not infer nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        if (index < length)
            return aa.entries[index].value;

        return defaultValue;
    }

    /**
     * Returns the index location if the Dictionary contains an value with the specified key; otherwise, -1
     * Params:
     *  key = the key of the value to locate
     */
    ptrdiff_t indexOf(scope const(K) key) const nothrow pure
    {
        return length != 0 ? aa.indexOf(key) : -1;
    }

    /**
     * Reorganizes the Dictionary in place so that lookups are more efficient.
     * Rehash is effective when there were a lot of removed keys
     * Returns a reference to the Dictionary.
     */
    ref typeof(this) rehash() nothrow pure return @safe
    {
        if (length)
            aa.rehash();

        return this;
    }

    /**
     * Removes the key-value pair with the specified key from the Dictionary.
     * Returns true if the key if found, false otherwise
     * Params:
     *  key = the key of the element to remove
     */
    static if (isAssignableKV)
    bool remove(scope const(K) key)
    {
        return length != 0 ? aa.remove(key) : false;
    }

    /**
     * Removes the key-value pair with the specified key from the Dictionary and assign it to value.
     * Returns true if the key if found, false otherwise
     * Params:
     *  key = the key of the value to remove
     *  value = the variable to hold the removed key's value
     */
    static if (isAssignableKV)
    bool remove(scope const(K) key, ref V value)
    {
        return length != 0 ? aa.remove(key, value) : false;
    }

    /**
     * Removes the key-value pair with the specified index from the Dictionary.
     * Returns true if index is within range, false otherwise
     * Params:
     *  index = the index of the element to remove
     */
    static if (isAssignableKV)
    bool removeAt(size_t index)
    {
        return index < length ? aa.removeAt(index) : false;
    }

    /**
     * Removes the key-value pair with the specified index from the Dictionary and assign it to value.
     * Returns true if index is within range, false otherwise
     * Params:
     *  index = the index of the element to remove
     *  value = the variable to hold the removed key's element
     */
    static if (isAssignableKV)
    bool removeAt(size_t index, ref V value)
    {
        return index < length ? aa.removeAt(index, value) : false;
    }

    /**
     * Replaces the key-value pair with the specified index from the Dictionary.
     * Returns true if index is within range and key is not duplicate, false otherwise
     * Params:
     *  index = the index of the element to replace
     *  key = the key of the element to replace
     *  value = the value of the element to replace
     */
    static if (isAssignableKV)
    bool replaceAt(size_t index, K key, V value)
    {
        return index < length ? aa.replaceAt(index, key, value) : false;
    }

    /**
     * Looks up key; if it exists returns corresponding value else evaluates value, adds it to the Dictionary and returns it
     * Params:
     *  key = the key of the element to lookup/add
     *  createValue = the value being added if key is not found
     */
    ref V require(K key, lazy V createValue = V.init) nothrow return // lazy does not infer nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        if (!aa)
            aa = createAA(0, 0);

        return aa.require(key, createValue);
    }

    /**
     * Reserve a Dictionary with a given capacity buckets & key-value pairs for appending.
     * Avoid reallocate memory while populating the Dictionary instant
     * Params:
     *  bucketCapacity = reserved number of buckets for appending
     *  entryCapacity = reserved number of key-value pairs for appending
     */
    void reserve(size_t bucketCapacity, size_t entryCapacity) nothrow @safe
    in
    {
        assert(bucketCapacity >= entryCapacity);
    }
    do
    {
        if (aa)
            aa.reserve(bucketCapacity, entryCapacity);
        else
            aa = createAA(bucketCapacity, entryCapacity);
    }

    /**
     * Returns a hash value of the Dictionary
     */
    size_t toHash() const nothrow scope
    {
        return length != 0 ? aa.toHash() : 0u;
    }

    /**
     * Looks up key; if it exists applies the update delegate else evaluates the create delegate and adds it to the Dictionary
     * Params:
     *  key = the key of the element to lookup/add
     *  createVal = a delegate to create new value if the key is not found
     *  updateVal = a delegate being called when the key is found
     */
    ref V update(C, U)(K key, scope C createVal, scope U updateVal) return
    if ((is(C : V delegate()) || is(C : V function()))
        && (is(U : void delegate(ref V)) || is(U : void function(ref V))))
    {
        if (!aa)
            aa = createAA(0, 0);

        return aa.update(key, createVal, updateVal);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the keys of the Dictionary
     */
    @property auto byKey() inout @nogc nothrow pure @trusted
    {
        return Range!(RangeKind.key)(cast(Impl*)aa, 0);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the keys & values of the Dictionary
     */
    @property auto byKeyValue() inout @nogc nothrow pure @trusted
    {
        return Range!(RangeKind.keyValue)(cast(Impl*)aa, 0);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the values of the Dictionary
     */
    @property auto byValue() inout @nogc nothrow pure @trusted
    {
        return Range!(RangeKind.value)(cast(Impl*)aa, 0);
    }

    /**
     * The current capacity that the Dictionary can hold entries
     */
    @property size_t capacity() const @nogc nothrow pure @safe
    {
        return aa ? aa.capacity : 0;
    }

    /**
     * The number of keys that have collision
     */
    @property uint collisionCount() const @nogc nothrow pure @safe
    {
        return aa ? aa.collisionCount : 0;
    }

    /**
     * Returns true if Dictionary has no elements, otherwise false
     */
    @property bool empty() const @nogc nothrow pure @safe
    {
        return aa is null || aa.length == 0;
    }

    /**
     * Returns current mixing hash value logic
     */
    @property DictionaryHashMix hashMix() const @nogc nothrow pure @safe
    {
        return aa ? aa.hashMix : DictionaryHashMix.none;
    }

    /**
     * Changes the mixing hash value logic
     * Only valid operation if the Dictionary has no elements
     * Params:
     *  newHashMix = new mixing hash value logic
     */
    @property ref typeof(this) hashMix(DictionaryHashMix newHashMix) nothrow @safe
    in
    {
        assert(length == 0);
    }
    do
    {
        if (length == 0)
        {
            if (aa)
                aa.hashMix = newHashMix;
            else if (newHashMix != DictionaryHashMix.none)
                aa = createAA(0, 0, newHashMix);
        }
        return this;
    }

    /**
     * Returns the key array
     */
    @property const(K)[] keys() inout nothrow
    {
        import std.array : array;

        return this.byKey.array;
    }

    /**
     * Returns number of elements in the Dictionary
     */
    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure @safe
    {
        return aa ? aa.length : 0;
    }

    /**
     * The maximum collision that a lookup needs to travel to find a key (hash collision)
     */
    @property uint maxCollision() const @nogc nothrow pure @safe
    {
        return aa ? aa.maxCollision : 0;
    }

    /**
     * Returns the value array
     */
    @property V[] values() inout nothrow
    {
        import std.array : array;

        return this.byValue.array;
    }

private:
    alias Bucket = ptrdiff_t;
    alias Index = ptrdiff_t;

    static struct Entry
    {
    private:
        Index nextCollision; // Next Entry index of collision chain; -1 is end of chain
        size_t hash; // Hash value of _key
        UK _key;

    public:
        @property const(K) key() const nothrow @safe
        {
            return _key;
        }

        V value;
    }

    static struct Impl
    {
        this(const(size_t) bucketCapacity, const(size_t) entryCapacity,
            DictionaryHashMix hashMix, CustomHashOf customHashOf) nothrow
        {
            this._hashMix = hashMix;
            this.customHashOf = customHashOf;
            this.buckets = allocBuckets(calcDim(bucketCapacity, 0));
            if (entryCapacity)
                this.entries.reserve(entryCapacity);
        }

        // only called from building an empty AA, works even when assignment isn't
        // valid for the given value type.
        pragma(inline, true)
        void add(ref K key, ref V value)
        {
            add(calcHash(key), key, value);
        }

        void add(const(size_t) hash, ref K key, ref V value)
        {
            assert(hash != 0);

            uint keyCollision;
            auto bucket = findSlotInsert(hash, keyCollision);
            if (grow())
                bucket = findSlotInsert(hash, keyCollision);

            const entryPos = addEntry(hash, key, value);
            attachEntryToBucket(bucket, entryPos, keyCollision);
        }

        pragma(inline, true)
        size_t addEntry(const(size_t) hash, ref K key, ref V value)
        {
            entries ~= Entry(-1, hash, key, value);
            return entries.length;
        }

        pragma(inline, true)
        void attachEntryToBucket(const(Index) bucket, const(Index) entryPos, const(uint) collision) nothrow pure @safe
        in
        {
            assert(entries[entryPos - 1].hash != 0);
        }
        do
        {
            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", entries[entryPos - 1].key,
                ", bucket=", bucket, ", entryPos=", entryPos, ")");

            entries[entryPos - 1].nextCollision = buckets[bucket] - 1;
            buckets[bucket] = entryPos;

            if (collision)
            {
                debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__,
                    ".", K.stringof, "(buckets.length=", buckets.length, ", entries.length=", entries.length,
                    ", collision=", collision, ", collisionCount=", collisionCount+1, ")");

                if (this.maxCollision < collision)
                    this.maxCollision = collision;

                this.collisionCount++;
            }
        }

        pragma(inline, true)
        size_t calcBucket(const(size_t) hash) const @nogc nothrow pure @safe
        {
            return hash % buckets.length;
        }

        pragma(inline, true)
        size_t calcHash(ref const(K) key) const nothrow pure @safe
        {
            if (customHashOf)
                return customHashOf(key);
            else
            {
                const size_t hash = hashOf(key);
                return hash != 0 ? calcHashFinal(hash) : calcHashFinal(1u);
            }
        }

        static if (is(K == string) || is(K == wstring) || is(K == dstring))
        {
            pragma(inline, true)
            size_t calcHash(scope const(KE)[] key) const nothrow pure @safe
            {
                if (customHashOf)
                    return customHashOf(key);
                else
                {
                    const size_t hash = hashOf(key);
                    return hash != 0 ? calcHashFinal(hash) : calcHashFinal(1u);
                }
            }
        }

        pragma(inline, true)
        size_t calcHashFinal(const(size_t) hash) const @nogc nothrow pure @safe
        {
            return _hashMix == DictionaryHashMix.none
                ? hash
                : _hashMix == DictionaryHashMix.murmurHash3
                    ? mixMurmurHash3(hash)
                    : mixMurmurHash2(hash);
        }

        void clear() nothrow pure @safe
        {
            // clear all data, but don't change bucket array length
            arrayZeroInit(buckets);
            entries = [];
            collisionCount = maxCollision = 0;
        }

        inout(V)* find(ref const(K) key) inout return
        {
            Index index, bucket;
            uint keyCollision;
            auto entry = findSlotLookup(calcHash(key), key, index, bucket, keyCollision);
            return entry ? &entry.value : null;
        }

        static if (is(K == string) || is(K == wstring) || is(K == dstring))
        inout(V)* find(scope const(KE)[] key) inout return
        {
            Index index, bucket;
            uint keyCollision;
            auto entry = findSlotLookup(calcHash(key), key, index, bucket, keyCollision);
            return entry ? &entry.value : null;
        }

        // find the first slot to insert a value with hash
        Index findSlotInsert(const(size_t) hash, out uint keyCollision) const @nogc nothrow pure @safe
        {
            keyCollision = 0;
            const bucket = calcBucket(hash);
            if (buckets[bucket] != 0)
            {
                auto index = buckets[bucket] - 1;
                while (index >= 0)
                {
                    keyCollision++;
                    index = entries[index].nextCollision;
                }
            }
            return bucket;
        }

        // lookup a key
        inout(Entry)* findSlotLookup(const(size_t) hash, ref const(K) key, out Index index, out Index bucket, out uint keyCollision) inout @nogc nothrow pure @safe
        {
            keyCollision = 0;
            bucket = calcBucket(hash);
            index = buckets[bucket] - 1;

            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key,
                ", bucket=", bucket, ", entryPos=", index + 1, ", entries.length=", entries.length, ")");

            return index >= 0
                ? isIndexedKey(index, hash, key, keyCollision)
                    ? &entries[index]
                    : null
                : null;
        }

        static if (is(K == string) || is(K == wstring) || is(K == dstring))
        inout(Entry)* findSlotLookup(const(size_t) hash, scope const(KE)[] key, out Index index, out Index bucket, out uint keyCollision) inout @nogc nothrow pure @safe
        {
            keyCollision = 0;
            bucket = calcBucket(hash);
            index = buckets[bucket] - 1;

            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key,
                ", bucket=", bucket, ", entryPos=", index + 1, ", entries.length=", entries.length, ")");

            return index >= 0
                ? isIndexedKey(index, hash, key, keyCollision)
                    ? &entries[index]
                    : null
                : null;
        }

        pragma(inline, true)
        bool grow()
        {
            const newDim = calcDim(entries.length + collisionCount + bucketInflated, buckets.length);
            if (newDim > buckets.length)
            {
                resize(newDim);
                return true;
            }
            else
                return false;
        }

        ptrdiff_t indexOf(ref const(K) key) const nothrow pure
        {
            Index index, bucket;
            uint keyCollision;
            return findSlotLookup(calcHash(key), key, index, bucket, keyCollision) !is null
                ? index
                : -1;
        }

        //pragma(inline, true)
        bool isIndexedKey(ref Index index, const(size_t) hash, ref const(K) key, ref uint keyCollision) const @nogc nothrow pure @safe
        {
            do
            {
                auto e = &entries[index];
                if (e.hash == hash && e._key == key)
                    return true;

                keyCollision++;
                index = e.nextCollision;

                debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key,
                    ", entryPos=", index + 1, ", entries.length=", entries.length, ")");
            }
            while (index >= 0);
            return false;
        }

        static if (is(K == string) || is(K == wstring) || is(K == dstring))
        {
            //pragma(inline, true)
            bool isIndexedKey(ref Index index, const(size_t) hash, scope const(KE)[] key, ref uint keyCollision) const @nogc nothrow pure @safe
            {
                do
                {
                    auto e = &entries[index];
                    if (e.hash == hash && e._key == key)
                        return true;

                    keyCollision++;
                    index = e.nextCollision;

                    debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key,
                        ", entryPos=", index + 1, ", entries.length=", entries.length, ")");
                }
                while (index >= 0);
                return false;
            }
        }

        ref V put(ref K key, ref V value) return
        {
            Index index, bucket;
            uint keyCollision;
            const h = calcHash(key);
            auto entry = findSlotLookup(h, key, index, bucket, keyCollision);
            if (entry)
            {
                static if (isAssignable!V)
                {
                    entry.value = value;
                    return entry.value;
                }
                else
                    assert(0, fullyQualifiedName!V ~ " is not assignable"); // Runtime error only
            }
            else
            {
                if (grow())
                    bucket = findSlotInsert(h, keyCollision);

                const entryPos = addEntry(h, key, value);
                attachEntryToBucket(bucket, entryPos, keyCollision);
                return entries[entryPos - 1].value;
            }
        }

        void refill() nothrow @safe
        {
            collisionCount = maxCollision = 0;
            foreach (ei, ref e; entries)
            {
                uint keyCollision;
                const bucket = findSlotInsert(e.hash, keyCollision);
                attachEntryToBucket(bucket, ei + 1, keyCollision);
            }
        }

        void rehash() nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "()");

            const newDim = calcDim(entries.length + collisionCount + bucketInflated, 0);
            if (newDim != buckets.length)
            {
                resize(newDim);
            }
            else
            {
                arrayZeroInit(buckets);
                refill();
            }
        }

        static if (isAssignableKV)
        bool remove(ref const(K) key)
        {
            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key, ")");

            Index index, bucket;
            uint keyCollision;
            auto entry = findSlotLookup(calcHash(key), key, index, bucket, keyCollision);
            return entry !is null
                ? removeAt(index)
                : false;
        }

        static if (isAssignableKV)
        bool remove(ref const(K) key, ref V value)
        {
            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", key, ")");

            Index index, bucket;
            uint keyCollision;
            auto entry = findSlotLookup(calcHash(key), key, index, bucket, keyCollision);
            return entry !is null
                ? removeAt(index, value)
                : false;
        }

        static if (isAssignableKV)
        bool removeAt(const(Index) index)
        {
            import core.memory : GC;

            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "(key=", entries[index].key,
                ", bucket=", calcBucket(entries[index].hash), ", entryPos=", index + 1, ")");

            // Hookup next entry
            // Must do this action before updating entries's index
            removeEntryFromBucket(index);

            // Update tail entries's index
            foreach (i; index + 1..entries.length)
            {
                entries[i - 1] = entries[i];
                updateBucketIndex(i, -1);
            }

            // Reduce the length
            entries.length = entries.length - 1;

            // Shrink if too many have been removed
            if (fakePure({ return (entries.length < buckets.length / 3) && !GC.inFinalizer; }))
                shrink();

            return true;
        }

        static if (isAssignableKV)
        bool removeAt(const(Index) index, ref V value)
        {
            value = entries[index].value;
            return removeAt(index);
        }

        static auto ref fakePure(F)(scope F fun) nothrow pure @trusted
        {
            mixin("alias PureFun = " ~ F.stringof ~ " pure;");
            return (cast(PureFun)fun)();
        }

        void removeEntryFromBucket(const(Index) index) nothrow @safe
        {
            const entry = &entries[index];
            const bucket = calcBucket(entry.hash);

            // Match head, just re-attach next as head
            if (buckets[bucket] == index + 1)
            {
                buckets[bucket] = entry.nextCollision + 1;
                return;
            }

            debug size_t count;
            auto i = buckets[bucket] - 1;
            while (true)
            {
                auto e = &entries[i];
                if (e.nextCollision == index)
                {
                    e.nextCollision = entry.nextCollision;
                    return;
                }
                i = e.nextCollision;

                debug
                {
                    if (++count > entries.length)
                        assert(0, "Concurrent use");
                }
            }
        }

        static if (isAssignableKV)
        bool replaceAt(const(Index) index, ref K key, ref V value)
        {
            auto entry = &entries[index];

            if (entry._key != key)
            {
                Index indexDup, bucket;
                uint keyCollision;
                const h = calcHash(key);
                // Duplicate?
                if (findSlotLookup(h, key, indexDup, bucket, keyCollision) !is null)
                    return false;

                removeEntryFromBucket(index);
                entry.hash = h;
                entry._key = key;
                attachEntryToBucket(bucket, index + 1, keyCollision);
            }

            entry.value = value;
            return true;
        }

        ref V require(ref K key, lazy V createValue) return
        {
            Index index, bucket;
            uint keyCollision;
            const h = calcHash(key);
            auto entry = findSlotLookup(h, key, index, bucket, keyCollision);
            if (entry is null)
            {
                if (grow())
                    bucket = findSlotInsert(h, keyCollision);

                entries ~= Entry(-1, h, key, createValue);
                attachEntryToBucket(bucket, entries.length, keyCollision);
                return entries[$ - 1].value;
            }
            else
                return entry.value;
        }

        void reserve(size_t bucketCapacity, size_t entryCapacity)
        {
            bucketCapacity = calcDim(bucketCapacity, 0);
            if (buckets.length < bucketCapacity)
                resize(bucketCapacity);
            if (entries.capacity < entryCapacity)
                entries.reserve(entryCapacity);
        }

        void resize(const(size_t) newDim) nothrow pure @safe
        {
            debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe) debug writeln(__FUNCTION__, "(buckets.length=",
                buckets.length, ", newDim=", newDim, ")");

            auto oldBuckets = buckets;

            buckets = allocBuckets(newDim);
            refill();

            // safe to free b/c impossible to reference
            arrayFree!Bucket(oldBuckets);
        }

        void shrink()
        {
            //debug(debug_pham_utl_utl_array_dictionary) if (!__ctfe && aaCanLog) debug writeln(__FUNCTION__, "()");

            const newDim = calcDim(entries.length + collisionCount + bucketInflated, 0);
            if (newDim < buckets.length)
                resize(newDim);
        }

        size_t toHash() const nothrow scope
        {
            size_t result;
            foreach (ref entry; entries)
            {
                result += hashOf(hashOf(entry.value), hashOf(entry._key));
            }
            return result;
        }

        ref V update(C, U)(ref K key, scope C createValue, scope U updateValue) return
        {
            Index index, bucket;
            uint keyCollision;
            const h = calcHash(key);
            auto entry = findSlotLookup(h, key, index, bucket, keyCollision);
            if (entry is null)
            {
                if (grow())
                    bucket = findSlotInsert(h, keyCollision);

                entries ~= Entry(-1, h, key, createValue());
                attachEntryToBucket(bucket, entries.length, keyCollision);
                return entries[$ - 1].value;
            }
            else
            {
                updateValue(entry.value);
                return entry.value;
            }
        }

        void updateBucketIndex(const(Index) index, const(int) shiftCount) nothrow @safe
        {
            const entry = &entries[index];
            const bucket = calcBucket(entry.hash);

            if (buckets[bucket] == index + 1)
            {
                buckets[bucket] += shiftCount;
                return;
            }

            // Iterate to find the index for adjustment
            debug size_t count;
            auto i = buckets[bucket] - 1;
            while (true)
            {
                auto e = &entries[i];
                if (e.nextCollision == index)
                {
                    e.nextCollision += shiftCount;
                    return;
                }
                i = e.nextCollision;

                debug
                {
                    if (++count > entries.length)
                        assert(0, "Concurrent use");
                }
            }
        }

        pragma(inline, true)
        @property size_t capacity() const @nogc nothrow pure @safe
        {
            return buckets.length;
        }

        @property DictionaryHashMix hashMix() const @nogc nothrow pure @safe
        {
            return _hashMix;
        }

        @property void hashMix(DictionaryHashMix newHashMix) @nogc nothrow pure @safe
        {
            if (entries.length == 0)
                _hashMix = newHashMix;
        }

        pragma(inline, true)
        @property size_t length() const @nogc nothrow pure @safe
        {
            return entries.length;
        }

        Bucket[] buckets; // Based 1 index
        Entry[] entries;
        CustomHashOf customHashOf;
        uint collisionCount, maxCollision;
        DictionaryHashMix _hashMix;
    }

    enum RangeKind
    {
        key,
        value,
        keyValue,
    }

    static struct Range(RangeKind kind)
    {
        this(Impl* impl, size_t idx) @nogc nothrow pure @safe
        {
            this.impl = impl;
            this.idx = idx;
        }

        void popFront() @nogc nothrow @safe
        in
        {
            assert(!empty);
        }
        do
        {
            idx++;
        }

        auto save() @nogc nothrow @safe
        {
            return this;
        }

        pragma(inline, true)
        @property bool empty() const @nogc nothrow @safe
        {
            return impl is null || idx >= impl.entries.length;
        }

        static if (kind == RangeKind.key)
        {
            @property const(K) front()
            {
                assert(!empty);

                return impl.entries[idx]._key;
            }
        }
        else static if (kind == RangeKind.value)
        {
            @property ref V front() @nogc nothrow return @safe
            {
                assert(!empty);

                return impl.entries[idx].value;
            }
        }
        else static if (kind == RangeKind.keyValue)
        {
            @property ref Entry front() @nogc nothrow return @safe
            {
                assert(!empty);

                return impl.entries[idx];
            }
        }
        else
            static assert(0);

    private:
        Impl* impl;
        size_t idx;
    }

    static Bucket[] allocBuckets(const(size_t) dim) nothrow pure @trusted
    in
    {
        assert(isPrime(dim));
    }
    do
    {
        import core.memory : GC;

        if (__ctfe)
            return new Bucket[](dim);
        else
        {
            enum attr = GC.BlkAttr.NO_INTERIOR;
            const sz = dim * Bucket.sizeof;
            return (cast(Bucket*)GC.calloc(sz, attr))[0..dim];
        }
    }

    static size_t calcDim(const(size_t) requiredLength, const(size_t) bucketLength) @nogc nothrow pure @safe
    {
        return bucketLength > requiredLength
            ? bucketLength
            : bucketLength == 0
                ? getPrimeLength(requiredLength != 0 ? requiredLength : 8)
                : expandPrimeLength(bucketLength);
    }

    Impl* createAA(const(size_t) bucketCapacity, const(size_t) entryCapacity,
        DictionaryHashMix hashMix = DictionaryHashMix.none,
        CustomHashOf customHashOf = null) nothrow @safe
    in
    {
        assert(bucketCapacity >= entryCapacity);
    }
    do
    {
        return new Impl(bucketCapacity, entryCapacity, hashMix, customHashOf);
    }

private:
    Impl* aa;
}

/**
 * Constructs a build-in associated array from a Dictionary
 * Params:
 *  dictionary = a source Dictionary
 */
auto asAA(K, V)(Dictionary!(K, V) dictionary)
{
    if (dictionary.length)
    {
        V[K] result;
        foreach (ref e; dictionary[])
        {
            result[e._key] = e.value;
        }
        return result;
    }

    return V[K].init;
}

/**
 * Constructs a Dictionary from a build-in associated array
 * Params:
 *  aa = a source build-in associated array
 *  hashMix = optionally mix hash value with specific logic
 *  customHashOf = a customized function to calculate hash value from key
 */
auto asAA(K, V)(V[K] aa,
    DictionaryHashMix hashMix = DictionaryHashMix.none,
    Dictionary!(K, V).CustomHashOf customHashOf = null)
{
    return Dictionary!(K, V)(aa, hashMix, customHashOf);
}

// Final mix of MurmurHash2
pragma(inline, true)
size_t mixMurmurHash2(size_t hash) @nogc nothrow pure @safe
{
    static if (size_t.sizeof == 4)
    {
        hash ^= hash >> 13;
        hash *= 0x5bd1e995;
        hash ^= hash >> 15;
        return hash;
    }
    else static if (size_t.sizeof == 8)
    {
        hash ^= hash >> 47;
        hash *= 0xc6a4a7935bd1e995;
        hash ^= hash >> 47;
        return hash;
    }
    else
        static assert(0);
}

// Final mix of MurmurHash3
pragma(inline, true)
size_t mixMurmurHash3(size_t hash) @nogc nothrow pure @safe
{
    static if (size_t.sizeof == 4)
    {
        hash ^= hash >> 16;
        hash *= 0x85ebca6b;
        hash ^= hash >> 13;
        hash *= 0xc2b2ae35;
        hash ^= hash >> 16;
        return hash;
    }
    else static if (size_t.sizeof == 8)
    {
        hash ^= hash >> 33;
        hash *= 0xff51afd7ed558ccd;
        hash ^= hash >> 33;
        hash *= 0xc4ceb9fe1a85ec53;
        hash ^= hash >> 33;
        return hash;
    }
    else
        static assert(0);
}


private:

unittest // Dictionary
{
    Dictionary!(string, int) aa;
    aa["one"] = 1;
    aa["two"] = 2;
    aa["three"] = 3;
    assert(aa.length == 3);
    auto p = "one" in aa;
    assert(p);
    assert(*p == 1);
    p = "two" in aa;
    assert(p);
    assert(*p == 2);
    p = "three" in aa;
    assert(p);
    assert(*p == 3);
    p = "unknown" in aa;
    assert(p is null);
    string[] keys;
    keys.reserve(aa.length);
    auto h = aa;
    foreach(k; h.byKey)
    {
        assert(h[k] == aa[k]);
        keys ~= k;
    }
    assert(keys == ["one", "two", "three"]);
}

unittest // Dictionary
{
    auto buildAAAtCompiletime()
    {
        Dictionary!(string, int) h = ["hello": 5];
        return h;
    }
    static h = buildAAAtCompiletime();
    auto aa = h.asAA;
    h["there"] = 4;
    aa["D is the best"] = 3;
}

unittest // Dictionary
{
    static struct Foo
    {
        ubyte x;
        double d;
    }
    static Dictionary!(Foo, int) utaa = [Foo(1, 2.0) : 5];
    assert(utaa[Foo(1, 2.0)] == 5);
}

unittest // Dictionary
{
    immutable(string)[string] iaa0 = ["l" : "left"];
    Dictionary!(string, immutable(string)) h0 = iaa0;

    immutable struct S { int x; }
    S[string] iaa1 = ["10" : S(10)];
    Dictionary!(string, S) h1 = iaa1;
}

unittest // Dictionary testKeysValues1()
{
    import std.conv : to;
    import std.stdio : writeln;

    static struct T
    {
        byte b;
        static size_t count;
        this(this) nothrow @safe { ++count; }
    }

    T.count = 0;
    Dictionary!(int, T) aa;
    T t;
    aa[0] = t;
    aa[1] = t;
    //debug writeln("line=", __LINE__, ", count=", T.count);
    assert(T.count <= 5, T.count.to!string);
    auto vals = aa.values;
    assert(vals.length == 2);
    //debug writeln("line=", __LINE__, ", count=", T.count);
    assert(T.count <= 13, T.count.to!string);

    T.count = 0;
    Dictionary!(T, int) aa2;
    aa2[t] = 0;
    //debug writeln("line=", __LINE__, ", count=", T.count);
    assert(T.count <= 2, T.count.to!string);
    aa2[t] = 1;
    //debug writeln("line=", __LINE__, ", count=", T.count);
    assert(T.count <= 3, T.count.to!string);
    auto keys = aa2.keys;
    assert(keys.length == 1);
    //debug writeln("line=", __LINE__, ", count=", T.count);
    assert(T.count <= 7, T.count.to!string);
}

nothrow pure unittest // Dictionary testKeysValues2()
{
    Dictionary!(string, int) aa;

    assert(aa.keys.length == 0);
    assert(aa.values.length == 0);

    aa["hello"] = 3;
    assert(aa["hello"] == 3);
    aa["hello"]++;
    assert(aa["hello"] == 4);

    assert(aa.length == 1);

    const(string)[] keys = aa.keys;
    assert(keys.length == 1);
    assert(keys[0] == "hello");

    int[] values = aa.values;
    assert(values.length == 1);
    assert(values[0] == 4);

    aa["foo"] = 1;
    aa["bar"] = 2;
    aa["batz"] = 3;

    assert(aa.keys.length == 4);
    assert(aa.values.length == 4);
    aa.rehash();
    assert(aa.length == 4);
    assert(aa["hello"] == 4);
    assert(aa["batz"] == 3);

    foreach (a; aa.keys)
    {
        assert(a.length != 0);
        assert(a.ptr != null);
    }

    foreach (v; aa.values)
    {
        assert(v != 0);
    }
}

@safe unittest // Dictionary testGet1()
{
    Dictionary!(string, int) aa;
    int a;
    foreach (val; aa.byKeyValue)
    {
        ++aa[val.key];
        a = val.value;
    }
}

unittest // Dictionary testGet2()
{
    static class T
    {
        static size_t count;
        this() { ++count; }
    }

    T.count = 0;
    Dictionary!(string, T) aa;

    auto a = new T;
    aa["foo"] = a;
    assert(T.count == 1);
    auto b = aa.get("foo", new T);
    assert(T.count == 1);
    assert(b is a);
    auto c = aa.get("bar", new T);
    assert(T.count == 2);
    assert(c !is a);

    //Obviously get doesn't add.
    assert("bar" !in aa);
}

unittest // Dictionary testRequire1()
{
    static class T
    {
        static size_t count;
        this() { ++count; }
    }

    T.count = 0;
    Dictionary!(string, T) aa;

    auto a = new T;
    aa["foo"] = a;
    assert(T.count == 1);
    auto b = aa.require("foo", new T);
    assert(T.count == 1);
    assert(b is a);
    auto c = aa.require("bar");
    assert(T.count == 1);
    assert(c is null);
    assert("bar" in aa);
    auto d = aa.require("bar", new T);
    assert(d is null);
    auto e = aa.require("baz", new T);
    assert(T.count == 2);
    assert(e !is a);

    assert("baz" in aa);

    bool created = false;
    auto f = aa.require("qux", { created = true; return new T; }());
    assert(created == true);

    T g;
    auto h = aa.require("qux", { g = new T; return g; }());
    assert(g !is h);
}

unittest // Dictionary testRequire2()
{
    static struct S
    {
        int value;
    }

    Dictionary!(string, S) aa;

    aa.require("foo").value = 1;
    assert(aa == Dictionary!(string, S)(["foo" : S(1)]));

    aa["bar"] = S(2);
    auto a = aa.require("bar", S(3));
    assert(a == S(2));

    auto b = aa["bar"];
    assert(b == S(2));

    S* c = &aa.require("baz", S(4));
    assert(c is &aa["baz"]);
    assert(*c == S(4));

    assert("baz" in aa);

    auto d = aa["baz"];
    assert(d == S(4));
}

pure unittest // Dictionary testRequire3()
{
    Dictionary!(string, string) aa;

    auto a = aa.require("foo", "bar");
    assert("foo" in aa);
}

unittest // Dictionary testUpdate1()
{
    static class C {}
    Dictionary!(string, C) aa;

    C orig = new C;
    aa["foo"] = orig;

    C newer;
    C older;

    void test(string key)
    {
        aa.update(key, { newer = new C; return newer; }, (ref C c) { older = c; newer = new C; c = newer; });
    }

    test("foo");
    assert(older is orig);
    assert(newer is aa["foo"]);

    test("bar");
    assert(newer is aa["bar"]);
}

version(none)
unittest // Dictionary testUpdate2()
{
    static class C {}
    Dictionary!(string, C) aa;

    auto created = false;
    auto updated = false;

    class Creator
    {
        C opCall()
        {
            created = true;
            return new C();
        }
    }

    class Updater
    {
        C opCall(ref C)
        {
            updated = true;
            return new C();
        }
    }

    aa.update("foo", new Creator, new Updater);
    assert(created);
    aa.update("foo", new Creator, new Updater);
    assert(updated);
}

@safe unittest // Dictionary testByKey1()
{
    static struct BadValue
    {
        int x;
        this(this) @system { *(cast(ubyte*)(null) + 100000) = 5; } // not @safe
        alias x this;
    }

    Dictionary!(int, BadValue) aa;

    // FIXME: Should be @system because of the postblit
    if (false)
        auto x = aa.byKey.front;
}

nothrow pure unittest // Dictionary testByKey2()
{
    Dictionary!(int, int) a;
    foreach (i; a.byKey)
    {
        assert(false);
    }
    foreach (i; a.byValue)
    {
        assert(false);
    }
}

pure unittest // Dictionary testByKey3()
{
    auto a = Dictionary!(int, string)([ 1:"one", 2:"two", 3:"three" ]);
    auto b = a.dup;
    assert(b == Dictionary!(int, string)([ 1:"one", 2:"two", 3:"three" ]));

    int[] c;
    foreach (k; a.byKey)
    {
        c ~= k;
    }

    assert(c.length == 3);
    assert(c[0] == 1 || c[1] == 1 || c[2] == 1);
    assert(c[0] == 2 || c[1] == 2 || c[2] == 2);
    assert(c[0] == 3 || c[1] == 3 || c[2] == 3);
}

nothrow pure unittest // Dictionary testByKey4()
{
    string[] keys = ["a", "b", "c", "d", "e", "f"];

    // Test forward range capabilities of byKey
    {
        Dictionary!(string, int) aa;
        foreach (key; keys)
            aa[key] = 0;

        auto keyRange = aa.byKey();
        auto savedKeyRange = keyRange.save;

        // Consume key range once
        size_t keyCount = 0;
        while (!keyRange.empty)
        {
            aa[keyRange.front]++;
            keyCount++;
            keyRange.popFront();
        }

        foreach (key; keys)
        {
            assert(aa[key] == 1);
        }
        assert(keyCount == keys.length);

        // Verify it's possible to iterate the range the second time
        keyCount = 0;
        while (!savedKeyRange.empty)
        {
            aa[savedKeyRange.front]++;
            keyCount++;
            savedKeyRange.popFront();
        }

        foreach (key; keys)
        {
            assert(aa[key] == 2);
        }
        assert(keyCount == keys.length);
    }

    // Test forward range capabilities of byValue
    {
        size_t[string] aa;
        foreach (i; 0..keys.length)
        {
            aa[keys[i]] = i;
        }

        auto valRange = aa.byValue();
        auto savedValRange = valRange.save;

        // Consume value range once
        int[] hasSeen;
        hasSeen.length = keys.length;
        while (!valRange.empty)
        {
            assert(hasSeen[valRange.front] == 0);
            hasSeen[valRange.front]++;
            valRange.popFront();
        }

        foreach (sawValue; hasSeen) { assert(sawValue == 1); }

        // Verify it's possible to iterate the range the second time
        hasSeen = null;
        hasSeen.length = keys.length;
        while (!savedValRange.empty)
        {
            assert(!hasSeen[savedValRange.front]);
            hasSeen[savedValRange.front] = true;
            savedValRange.popFront();
        }

        foreach (sawValue; hasSeen) { assert(sawValue); }
    }
}

pure nothrow unittest // Dictionary issue5842()
{
    Dictionary!(string, string) test;
    test["test1"] = "test1";
    test.remove("test1");
    test.rehash;
    test["test3"] = "test3"; // causes divide by zero if rehash broke the AA
}

/// expanded test for 5842: increase AA size past the point where the AA
/// stops using binit, in order to test another code path in rehash.
pure nothrow unittest // Dictionary issue5842Expanded()
{
    import std.conv : to;

    //debug(debug_pham_utl_utl_array_dictionary) aaCanLog++;

    Dictionary!(int, int) aa;
    foreach (int i; 0..100)
        aa[i] = i;
    assert(aa.length == 100);
    foreach (int i; 0..100)
        assert(i in aa);
    foreach (int i; 0..50)
        assert(aa.remove(i), i.to!string);
    foreach (int i; 50..100)
        assert(i in aa);
    foreach (int i; 50..100)
        assert(aa.remove(i), i.to!string);
    assert(aa.length == 0, aa.length.to!string);
    aa.rehash();
    aa[1] = 1;
    aa[2] = 2;
    aa[3] = 3;
    assert(aa.length == 3, aa.length.to!string);
    assert(aa.removeAt(1));
    assert(aa.removeAt(1));
    assert(1 in aa);
    assert(aa.length == 1, aa.length.to!string);

    //debug(debug_pham_utl_utl_array_dictionary) aaCanLog--;
}

pure unittest // Dictionary issue5925()
{
    auto a = Dictionary!(int, int)([4:0]);
    auto b = Dictionary!(int, int)([4:0]);
    assert(a == b);
}

/// test for bug 8583: ensure Slot and aaA are on the same page wrt value alignment
pure unittest // Dictionary issue8583()
{
    auto aa0 = Dictionary!(byte, string)([byte(0): "zero"]);
    auto aa1 = Dictionary!(uint[3], string)([cast(uint[3])[1,2,3]: "onetwothree"]);
    auto aa2 = Dictionary!(uint[3], ushort)([cast(uint[3])[9,8,7]: ushort(987)]);
    auto aa3 = Dictionary!(uint[4], ushort)([cast(uint[4])[1,2,3,4]: ushort(1234)]);
    auto aa4 = Dictionary!(uint[5], string)([cast(uint[5])[1,2,3,4,5]: "onetwothreefourfive"]);

    assert(aa0.byValue.front == "zero");
    assert(aa1.byValue.front == "onetwothree");
    assert(aa2.byValue.front == 987);
    assert(aa3.byValue.front == 1234);
    assert(aa4.byValue.front == "onetwothreefourfive");
}

version(none)
nothrow pure unittest // Dictionary issue9052()
{
    static struct Json
    {
        Dictionary!(string, Json) aa;
        void opAssign(Json) {}
        size_t length() const { return aa.length; }
        // This length() instantiates AssociativeArray!(string, const(Json)) to call AA.length(), and
        // inside ref Slot opAssign(Slot p); (which is automatically generated by compiler in Slot),
        // this.value = p.value would actually fail, because both side types of the assignment
        // are const(Json).
    }
}

unittest // Dictionary issue9119()
{
    Dictionary!(string, int) aa;
    assert(aa.byKeyValue.empty);

    aa["a"] = 1;
    aa["b"] = 2;
    aa["c"] = 3;

    auto pairs = aa.byKeyValue;

    auto savedPairs = pairs.save;
    size_t count = 0;
    while (!pairs.empty)
    {
        assert(pairs.front.key in aa);
        assert(pairs.front.value == aa[pairs.front.key]);
        count++;
        pairs.popFront();
    }
    assert(count == aa.length);

    // Verify that saved range can iterate over the AA again
    count = 0;
    while (!savedPairs.empty)
    {
        assert(savedPairs.front.key in aa);
        assert(savedPairs.front.value == aa[savedPairs.front.key]);
        count++;
        savedPairs.popFront();
    }
    assert(count == aa.length);
}

nothrow pure unittest // Dictionary issue9852()
{
    // Original test case (revised, original assert was wrong)
    Dictionary!(string, int) a;
    a["foo"] = 0;
    a.remove("foo");
    version(none) assert(a == null); // should not crash

    Dictionary!(string, int) b;
    version(none) assert(b is null);
    assert(a == b); // should not deref null
    assert(b == a); // ditto

    Dictionary!(string, int) c;
    c["a"] = 1;
    assert(a != c); // comparison with empty non-null AA
    assert(c != a);
    assert(b != c); // comparison with null AA
    assert(c != b);
}

unittest // Dictionary issue10381()
{
    alias II = Dictionary!(int, int);
    II aa1 = II([0 : 1]);
    II aa2 = II([0 : 1]);
    II aa3 = II([0 : 2]);
    assert(aa1 == aa2); // Passes
    assert(typeid(II).equals(&aa1, &aa2));
    assert(!typeid(II).equals(&aa1, &aa3));
}

version(none)
nothrow pure unittest // Dictionary issue10720()
{
    static struct NC
    {
        @disable this(this) { }
    }

    Dictionary!(string, NC) aa;
    static assert(!is(aa.nonExistingField));
}

/// bug 11761: test forward range functionality
pure unittest // Dictionary issue11761()
{
    auto aa = Dictionary!(string, int)(["a": 1]);

    void testFwdRange(R, T)(R fwdRange, T testValue)
    {
        assert(!fwdRange.empty);
        assert(fwdRange.front == testValue);
        version(none) static assert(is(typeof(fwdRange.save) == typeof(fwdRange)));

        auto saved = fwdRange.save;
        fwdRange.popFront();
        assert(fwdRange.empty);

        assert(!saved.empty);
        assert(saved.front == testValue);
        saved.popFront();
        assert(saved.empty);
    }

    testFwdRange(aa.byKey, "a");
    testFwdRange(aa.byValue, 1);
    //testFwdRange(aa.byPair, tuple("a", 1));
}

version(none)
nothrow pure unittest // Dictionary issue13078()
{
    shared Dictionary!(string, string[]) map;
    map.rehash();
}

unittest // Dictionary issue14104()
{
    alias K = const(ubyte)*;
    Dictionary!(K, size_t) aa;
    immutable key = cast(K)(cast(size_t) uint.max + 1);
    aa[key] = 12;
    assert(key in aa);
}

unittest // Dictionary issue14626()
{
    static struct S
    {
        Dictionary!(string, string) aa;
        inout(string) key() inout { return aa.byKey().front; }
        inout(string) val() inout { return aa.byValue().front; }
        auto keyval() inout { return aa.byKeyValue().front; }
    }

    S s = S(Dictionary!(string, string)(["a":"b"]));
    assert(s.key() == "a");
    assert(s.val() == "b");
    assert(s.keyval().key == "a");
    assert(s.keyval().value == "b");

    version(none)
    void testInoutKeyVal(inout(string) key)
    {
        Dictionary!(typeof(key), inout(string)) aa;

        foreach (i; aa.byKey()) {}
        foreach (i; aa.byValue()) {}
        foreach (i; aa.byKeyValue()) {}
    }

    const Dictionary!(int, int) caa;
    version(none) static assert(is(typeof(caa.byValue().front) == const int));
}

/// test duplicated keys in AA literal
/// https://issues.dlang.org/show_bug.cgi?id=15290
unittest // Dictionary issue15290()
{
    Dictionary!(int, string) aa = Dictionary!(int, string)([ 0: "a", 0: "b" ]);
    assert(aa.length == 1);
    assert(aa.keys == [ 0 ]);
}

unittest // Dictionary issue15367()
{
    void f1() {}
    void f2() {}

    // TypeInfo_Delegate.getHash
    Dictionary!(void delegate(), int) aa;
    assert(aa.length == 0);
    aa[&f1] = 1;
    assert(aa.length == 1);
    aa[&f1] = 1;
    assert(aa.length == 1);

    auto a1 = [&f2, &f1];
    auto a2 = [&f2, &f1];

    // TypeInfo_Delegate.equals
    for (auto i = 0; i < 2; i++)
        assert(a1[i] == a2[i]);
    assert(a1 == a2);

    // TypeInfo_Delegate.compare
    for (auto i = 0; i < 2; i++)
        assert(a1[i] <= a2[i]);
    assert(a1 <= a2);
}

/// test AA as key
/// https://issues.dlang.org/show_bug.cgi?id=16974
unittest // Dictionary issue16974()
{
    Dictionary!(int, int) a = Dictionary!(int, int)([1 : 2]), a2 = Dictionary!(int, int)([1 : 2]);

    alias daa = Dictionary!(Dictionary!(int, int), int);

    assert(daa([a : 3]) == daa([a : 3]));
    assert(daa([a : 3]) == daa([a2 : 3]));

    assert(typeid(a).getHash(&a) == typeid(a).getHash(&a));
    assert(typeid(a).getHash(&a) == typeid(a).getHash(&a2));
}

/// test safety for alias-this'd AA that have unsafe opCast
/// https://issues.dlang.org/show_bug.cgi?id=18071
unittest // Dictionary issue18071()
{
    static struct Foo
    {
        Dictionary!(int, int) aa;
        auto opCast() pure nothrow @nogc
        {
            *cast(uint*)0xdeadbeef = 0xcafebabe;// unsafe
            return null;
        }
        alias aa this;
    }

    Foo f;
    () @safe { assert(f.byKey.empty); }();
}

/// Test that `require` works even with types whose opAssign
/// doesn't return a reference to the receiver.
/// https://issues.dlang.org/show_bug.cgi?id=20440
unittest // Dictionary issue20440()
{
    static struct S
    {
        int value;
        auto opAssign(S s) {
            this.value = s.value;
            return this;
        }
    }
    Dictionary!(S, S) aa;
    assert(aa.require(S(1), S(2)) == S(2));
    assert(aa[S(1)] == S(2));
}

///
unittest // Dictionary issue21442()
{
    import core.memory : GC;

    Dictionary!(size_t, size_t) glob;

    class Foo
    {
        size_t count;

        this (size_t entries) @safe
        {
            this.count = entries;
            foreach (idx; 0..entries)
                glob[idx] = idx;
        }

        ~this () @safe
        {
            foreach (idx; 0..this.count)
                glob.remove(idx);
        }
    }

    void bar () @safe
    {
        Foo f = new Foo(16);
    }

    bar();
    GC.collect(); // Needs to happen from a GC collection
}

/// Verify iteration with const.
unittest // Dictionary testIterationWithConst()
{
    auto aa = Dictionary!(int, int)([1:2, 3:4]);
    foreach (const t; aa.byKeyValue)
    {
        auto k = t.key;
        auto v = t.value;
    }
}

@safe unittest // Dictionary testStructArrayKey()
{
    struct S
    {
        int i;
    const @safe nothrow:
        hash_t toHash() { return 0; }
        bool opEquals(const S) { return true; }
        int opCmp(const S) { return 0; }
    }

    Dictionary!(const(S)[], int) aa = Dictionary!(const(S)[], int)([[S(11)] : 13]);
    assert(aa[[S(12)]] == 13);
}

pure unittest // Dictionary miscTests1()
{
    Dictionary!(int, string) key1 = Dictionary!(int, string)([1 : "true",  2 : "false"]);
    Dictionary!(int, string) key2 = Dictionary!(int, string)([1 : "false", 2 : "true"]);
    Dictionary!(int, string) key3;

    // AA lits create a larger hashtable
    Dictionary!(Dictionary!(int, string), int) aa1 = Dictionary!(Dictionary!(int, string), int)([key1 : 100, key2 : 200, key3 : 300]);

    // Ensure consistent hash values are computed for key1
    assert((key1 in aa1) !is null);

    // Manually assigning to an empty AA creates a smaller hashtable
    Dictionary!(Dictionary!(int, string), int) aa2;
    aa2[key1] = 100;
    aa2[key2] = 200;
    aa2[key3] = 300;

    assert(aa1 == aa2);

    // Ensure binary-independence of equal hash keys
    Dictionary!(int, string) key2a;
    key2a[1] = "false";
    key2a[2] = "true";

    assert(aa1[key2a] == 200);
}

unittest // Dictionary foreach
{
    Dictionary!(int, int) aa1;
    foreach (v; aa1)
        assert(false);
    foreach (k, v; aa1)
        assert(false);

    static struct S
    {
        size_t a;
        size_t b;
    }

    Dictionary!(int, S) aa2;
    foreach (ref v; aa2)
        assert(false);
    foreach (k, ref v; aa2)
        assert(false);
}

unittest // Dictionary miscTests2()
{
    Dictionary!(int, int) aa;
    assert(aa.byKey.empty);
    assert(aa.byValue.empty);
    assert(aa.byKeyValue.empty);

    size_t n;
    aa = [0 : 3, 1 : 4, 2 : 5];
    foreach (k, v; aa)
    {
        n += k;
        assert(k >= 0 && k < 3);
        assert(v >= 3 && v < 6);
    }
    assert(n == 3);
    n = 0;

    foreach (v; aa)
    {
        n += v;
        assert(v >= 3 && v < 6);
    }
    assert(n == 12);

    n = 0;
    foreach (k, v; aa)
    {
        ++n;
        break;
    }
    assert(n == 1);

    n = 0;
    foreach (v; aa)
    {
        ++n;
        break;
    }
    assert(n == 1);
}

unittest // Dictionary remove()
{
    Dictionary!(int, int) aa;
    assert(!aa.remove(0));
    aa[0] = 1;
    assert(aa.remove(0));
    assert(!aa.remove(0));
    aa[1] = 2;
    assert(!aa.remove(0));
    assert(aa.remove(1));

    assert(aa.length == 0);
    assert(aa.byKey.empty);
}

/// test zero sized value (hashset)
unittest // Dictionary testZeroSizedValue()
{
    alias V = void[0];
    Dictionary!(int, V) aa, aa2;
    aa[0] = V.init;
    assert(aa.length == 1);
    assert(aa.byKey.front == 0);
    assert(aa.byValue.front == V.init);
    aa[1] = V.init;
    assert(aa.length == 2);
    aa[0] = V.init;
    assert(aa.length == 2);
    assert(aa.remove(0));
    aa[0] = V.init;
    assert(aa.length == 2);
    aa2[0] = V.init;
    aa2[1] = V.init;
    assert(aa == aa2);
}

unittest // Dictionary testTombstonePurging()
{
    Dictionary!(int, int) aa;
    foreach (i; 0..6)
        aa[i] = i;
    foreach (i; 0..6)
        assert(aa.remove(i));
    foreach (i; 6..10)
        aa[i] = i;
    assert(aa.length == 4);
    foreach (i; 6..10)
        assert(i in aa);
}

unittest // Dictionary clear
{
    Dictionary!(int, int) aa;
    assert(aa.length == 0);
    foreach (i; 0..100)
        aa[i] = i * 2;
    assert(aa.length == 100);
    auto aa2 = aa;
    assert(aa2.length == 100);
    aa.clear();
    assert(aa.length == 0);
    assert(aa2.length == 0);

    aa2[5] = 6;
    assert(aa.length == 1);
    assert(aa[5] == 6);
}

unittest // Dictionary replaceAt
{
    Dictionary!(int, string) aa;

    aa[1] = "1";
    aa[2] = "2";
    aa[3] = "3";
    assert(aa.replaceAt(1, 2, "20"));
    assert(!aa.replaceAt(3, 3, "30"));
    assert(!aa.replaceAt(1, 3, "30"));
    assert(aa.length == 3);
    assert(aa.keys == [1, 2, 3]);
    assert(aa.values == ["1", "20", "3"]);
}

unittest // Dictionary removeAt
{
    Dictionary!(int, string) aa;

    aa[1] = "1";
    aa[2] = "2";
    aa[3] = "3";
    assert(aa.removeAt(1));
    assert(!aa.removeAt(3));
    assert(aa.length == 2);
    assert(aa.keys == [1, 3]);
    assert(aa.values == ["1", "3"]);

    assert(aa.removeAt(1));
    assert(aa.length == 1);
    assert(aa.keys == [1]);
    assert(aa.values == ["1"]);

    assert(aa.removeAt(0));
    assert(aa.length == 0);
    assert(aa.keys == []);
    assert(aa.values == []);
}

unittest // asAA
{
    auto srcAA = ["1":1, "3":3, "9":9];

    // To Dictionary
    auto dstAA1 = srcAA.asAA();
    assert(dstAA1.length == 3);
    assert(dstAA1.capacity == 11);
    assert(dstAA1["9"] == 9);

    auto dstAA2 = srcAA.asAA();
    assert(dstAA2 == dstAA1);
    assert(dstAA2.keys == dstAA1.keys);

    // To build-in associated array
    auto dstAA = dstAA1.asAA();
    assert(dstAA.length == 3);
    assert(dstAA["9"] == 9);
}

unittest // Create/Clone from empty
{
    int[int] aa;
    Dictionary!(int, int) dd;

    auto dd1 = Dictionary!(int, int)(aa);
    auto dd2 = Dictionary!(int, int)(dd);
    assert(dd1.empty == dd2.empty);
    assert(dd1.length == dd2.length);

    dd1 = aa;
    dd2 = dd;
    assert(dd1.empty == dd2.empty);
    assert(dd1.length == dd2.length);

    dd1 = dd.dup();
    dd2 = dd.dup();
    assert(dd1.empty == dd2.empty);
    assert(dd1.length == dd2.length);
}

unittest // Dictionary indexOf
{
    Dictionary!(int, int) aa;
    assert(aa.indexOf(1) == -1);
    aa[2] = 1;
    assert(aa.indexOf(2) == 0);
    assert(aa.indexOf(1) == -1);
}

unittest // Dictionary containKey
{
    int v = 100;
    Dictionary!(int, int) aa;
    assert(!aa.containKey(1));
    assert(!aa.containKey(1, v));
    assert(v == 100); // still stay the same
    aa[2] = 1;
    assert(aa.containKey(2));
    assert(aa.containKey(2, v));
    assert(v == 1);
    assert(!aa.containKey(1));
    assert(!aa.containKey(1, v));
    assert(v == 1); // still stay the same
}

unittest // Dictionary reserve
{
    int v;
    Dictionary!(int, int) aa;
    aa[2] = 5;
    aa[3] = 6;
    aa.reserve(100, 90);
    aa[4] = 7;
    assert(aa.length == 3);
    assert(aa.containKey(2, v));
    assert(v == 5);
    assert(aa.containKey(3, v));
    assert(v == 6);
    assert(aa.containKey(4, v));
    assert(v == 7);
    assert(aa.keys == [2, 3, 4]);
}
