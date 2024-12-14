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

import core.exception : RangeError;
import core.memory : GC;
import std.algorithm : min, max;
import std.array : array;
import std.traits : isIntegral;

version = usePrimeFirstSlot;

debug(debug_pham_utl_utl_array_dictionary) import std.stdio : writeln;
import pham.utl.utl_array : arrayFree, arrayZeroInit, removeAt;
version(usePrimeFirstSlot) import pham.utl.utl_prime;
//import pham.utl.utl_array_append : Appender;

/**
 * Represents a collection of key/value pairs that are accessible by the key.
 * The order of added items are reserved
 */
struct Dictionary(K, V)
{
public:
    /**
     * Construct a Dictionary from a build-in associated array
     * Params:
     *  other = source data from a build-in associated array
     */
    this(OK, OV)(OV[OK] other)
    if (is(OK : K) && is(OV : V))
    {
        //pragma(msg, "this(OK, OV)(buildin." ~ OK.stringof ~ " vs " ~ K.stringof ~ ")");
        //pragma(msg, "this(OK, OV)(buildin." ~ OV.stringof ~ " vs " ~ V.stringof ~ ")");

        opAssign(other);
    }

    /**
     * Construct a Dictionary from an other Dictionary with similar types
     * Params:
     *  other = source data from an other Dictionary with similar types
     */
    this(OK, OV)(Dictionary!(OK, OV) other) nothrow
    if (is(OK : K) && is(OV : V))
    {
        //pragma(msg, "this(OK, OV)(Dictionary." ~ OK.stringof ~ " vs " ~ K.stringof ~ ")");
        //pragma(msg, "this(OK, OV)(Dictionary." ~ OV.stringof ~ " vs " ~ V.stringof ~ ")");

        opAssign(other);
    }

    /**
     * Constructs an Dictionary with a given capacity elements for appending.
     * Avoid reallocate memory while populating the Dictionary instant
     * Params:
     *  capacity = reserved number of elements for appending.
     */
    this(size_t capacity) nothrow @safe
    {
        this.aa = new Impl(capacity);
    }

    /**
     * Supports build in foreach operator
     */
    alias opApply = opApplyImpl!(int delegate(V));
    alias opApply = opApplyImpl!(int delegate(const(K), V));

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(V)) || is(CallBack : int delegate(const(K), V)))
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        if (length)
        {
            static if (is(CallBack : int delegate(V)))
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
        const ol = rhs.length;
        if (ol)
        {
            this.aa = new Impl(ol);
            foreach (k, v; rhs)
                this.aa.add(k, v);
        }
        else
            this.aa = null;

        return this;
    }

    /**
     * Reset this Dictionary instant from an other Dictionary with similar types
     * Params:
     *  rhs = source data from an other Dictionary with similar types
     *        if rhs type is exact with the dictionary, it will only set the internal implementation
     *        which behaves like class/object assignment (no data copy taken place)
     */
    ref typeof(this) opAssign(OK, OV)(Dictionary!(OK, OV) rhs) nothrow return
    if (is(OK : K) && is(OV : V))
    {
        static if(is(OK == K) && is(OV == V))
        {
            this.aa = rhs.aa;
        }
        else
        {
            // build manually
            const ol = rhs.length;
            if (ol)
            {
                this.aa = new Impl(ol);
                foreach (ref e; rhs.aa.entries)
                    this.aa.add(e.key, e.value);
            }
            else
                this.aa = null;
        }

        return this;
    }

    /**
     * Support build-in IN operator
     * Returns null if key does not exist
     * Params:
     *  key = the key of the value to get
     */
    V* opBinaryRight(string op : "in")(scope const(K) key) nothrow return
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
        //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) debug writeln(__FUNCTION__, "(this.length=", this.length, ", rhs.length=", rhs.length, ")");
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
    ref V opIndex(const(K) key,
        string file = __FILE__, uint line = __LINE__) return
    {
        if(auto v = key in this)
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
    ref V opIndexAssign(V value, K key) return
    {
        if (!aa)
            aa = new Impl(0);

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
     * Returns a duplicate of the dictionary
     */
    typeof(this) dup()
    {
        auto result = typeof(this)(length);
        if (length)
        {
            foreach (ref e; this.aa.entries)
            {
                auto ee = Entry(e.hash, 0, e._key, e.value);
                result.aa.add(ee);
            }
        }
        return result;
    }


    /**
     * Returns the value of key.
     * If the key if not found, defaultValue is returned
     * Params:
     *  key = the key of the value to get
     *  defaultValue = the default value being returned if the key is not found
     */
    V get(const(K) key, lazy V defaultValue = V.init)
    {
        if (length != 0)
        {
            if (auto f = aa.find(key))
                return *f;
            else
                return defaultValue;
        }
        else
            return defaultValue;
    }

    /**
     * Reorganizes the dictionary in place so that lookups are more efficient.
     * Rehash is effective when there were a lot of removed keys
     * Returns a reference to the dictionary.
     */
    ref typeof(this) rehash() nothrow pure return @safe
    {
        if (length)
            aa.rehash();

        return this;
    }

    /**
     * Removes the value with the specified key from the dictionary.
     * Returns true if the key if found, false otherwise
     * Params:
     *  key = the key of the element to remove
     */
    bool remove(const(K) key)
    {
        return length != 0 ? aa.remove(key) : false;
    }

    /**
     * Removes the value with the specified index from the dictionary.
     * Returns true if the index is within range, false otherwise
     * Params:
     *  index = the index of the element to remove
     */
    bool removeAt(size_t index)
    {
        return index < length ? aa.removeAt(index) : false;
    }

    /**
     * Looks up key; if it exists returns corresponding value else evaluates value, adds it to the dictionary and returns it
     * Params:
     *  key = the key of the element to lookup/add
     *  value = the value being added if key is not found
     */
    ref V require(K key, lazy V value = V.init) return
    {
        if (!aa)
            aa = new Impl(0);

        return aa.require(key, value);
    }

    /**
     * Returns a hash value of the dictionary
     */
    size_t toHash() const nothrow scope
    {
        return length != 0 ? aa.toHash() : 0u;
    }

    /**
     * Looks up key; if it exists applies the update delegate else evaluates the create delegate and adds it to the dictionary
     * Params:
     *  key = the key of the element to lookup/add
     *  createVal = a delegate to create new value if the key is not found
     *  updateVal = a delegate being called when the key is found
     */
    ref V update(C, U)(K key, scope C createVal, scope U updateVal) return
    if (is(C : V delegate()) && is(U : void delegate(ref V)))
    {
        if (!aa)
            aa = new Impl(0);

        return aa.update(key, createVal, updateVal);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the keys of the dictionary
     */
    @property auto byKey() @nogc nothrow pure
    {
        return Range!(RangeKind.key)(aa, 0);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the keys & values of the dictionary
     */
    @property auto byKeyValue() @nogc nothrow pure
    {
        return Range!(RangeKind.keyValue)(aa, 0);
    }

    /**
     * Returns a forward range suitable for use as a foreach which will iterate over the values of the dictionary
     */
    @property auto byValue() @nogc nothrow pure
    {
        return Range!(RangeKind.value)(aa, 0);
    }

    /**
     * The current capacity that the dictionary can hold entries
     */
    @property size_t capacity() const @nogc nothrow pure @safe
    {
        return aa ? aa.buckets.length : 0;
    }

    /**
     * The maximum collision count that a lookup needs to travel to find a key
     */
    @property size_t collision() const @nogc nothrow pure @safe
    {
        return aa ? aa.collision : 0;
    }

    /**
     * Returns the key array
     */
    @property const(K)[] keys() nothrow
    {
        return this.byKey.array;
    }

    /**
     * Returns number of values in the dictionary
     */
    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure @safe
    {
        return aa ? aa.entries.length : 0;
    }

    /**
     * Returns the value array
     */
    @property V[] values() nothrow
    {
        return this.byValue.array;
    }

private:
    enum INDEX_EMPTY = 0;
    enum INDEX_REMOVED = size_t.max;

    static struct Bucket
    {
    @nogc nothrow pure:

        size_t position; // Based 1 index

        pragma(inline, true)
        @property bool empty() const @safe
        {
            return position == INDEX_EMPTY;
        }

        pragma(inline, true)
        @property bool filled() const @safe
        {
            return position != INDEX_EMPTY && position != INDEX_REMOVED;
        }
    }

    static struct Entry
    {
    private:
        size_t hash; // Must be first
        size_t bucketIndex;
        K _key;

    public:
        @property const(K) key() const nothrow @safe
        {
            return _key;
        }

        V value;
    }

    static struct Impl
    {
        this(const(size_t) capacity)
        {
            this.buckets = allocBuckets(calcDim(capacity, 0));
            version(usePrimeFirstSlot) this.bucketPrime = getMaxPrime(this.buckets.length - 1);
            if (capacity)
                this.entries.reserve(capacity);
        }

        // only called from building an empty AA, works even when assignment isn't
        // valid for the given value type.
        void add(ref K key, ref V value)
        {
            size_t collision;
            const h = calcHash(key);
            auto i = findSlotInsert(h, collision);
            if (grow())
                i = findSlotInsert(h, collision);

            set(&buckets[i], addEntry(h, i, key, value), collision);
        }

        void add(ref Entry entry)
        {
            assert(entry.hash != 0);

            size_t collision;
            auto i = findSlotInsert(entry.hash, collision);
            if (grow())
                i = findSlotInsert(entry.hash, collision);

            entry.bucketIndex = i;
            entries ~= entry;
            set(&buckets[i], entries.length, collision);
        }

        pragma(inline, true)
        size_t addEntry(size_t hash, size_t bucketIndex, ref K key, ref V value)
        {
            entries ~= Entry(hash, bucketIndex, key, value);
            return entries.length;
        }

        static Bucket[] allocBuckets(const(size_t) dim) nothrow pure @trusted
        {
            const mask = dim - 1;
            assert((dim & mask) == 0); // must be a power of 2

            if (__ctfe)
                return new Bucket[](dim);
            else
            {
                enum attr = GC.BlkAttr.NO_INTERIOR;
                const sz = dim * Bucket.sizeof;
                return (cast(Bucket*)GC.calloc(sz, attr))[0..dim];
            }
        }

        void clear() nothrow pure @safe
        {
            // clear all data, but don't change bucket array length
            arrayZeroInit(buckets);
            entries = [];
            collision = 0;
        }

        inout(V)* find(ref const(K) key) inout return
        {
            const h = calcHash(key);
            const loc = findSlotLookup(h, key);
            return loc ? &entries[loc.position - 1].value : null;
        }

        // find the first slot to insert a value with hash
        size_t findSlotInsert(const(size_t) hash, out size_t collision) inout @nogc nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "()");

            collision = 0;
            const lmask = mask;
            version(usePrimeFirstSlot)
                const first = hash % bucketPrime;
            else
                const first = hash & lmask;
            for (size_t i = first, j = 1; ; ++j)
            {
                if (!buckets[i].filled)
                    return i;

                collision++;
                i = (i + j) & lmask;
            }
        }

        // lookup a key
        inout(Bucket)* findSlotLookup(const(size_t) hash, ref const(K) key) inout @nogc nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "()");

            size_t collision;
            const lmask = mask;
            version(usePrimeFirstSlot)
                const first = hash % bucketPrime;
            else
                const first = hash & lmask;
            for (size_t i = first, j = 1; ; ++j)
            {
                auto loc = &buckets[i];
                if (loc.filled && isIndexedKey(loc, hash, key))
                    return loc;
                else if (loc.empty || (collision > this.collision && !loc.filled))
                    return null;

                collision++;
                i = (i + j) & lmask;
            }
        }

        // lookup a key
        size_t findSlotLookupOrInsert(const(size_t) hash, ref const(K) key, out size_t collision) inout @nogc nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "()");

            collision = 0;
            const lmask = mask;
            version(usePrimeFirstSlot)
                const first = hash % bucketPrime;
            else
                const first = hash & lmask;
            for (size_t i = first, j = 1; ; ++j)
            {
                auto loc = &buckets[i];
                if ((loc.filled && isIndexedKey(loc, hash, key)) || loc.empty || (collision > this.collision && !loc.filled))
                    return i;

                collision++;
                i = (i + j) & lmask;
            }
        }

        pragma(inline, true)
        bool grow()
        {
            const newDim = calcDim(entries.length + 1, buckets.length);
            if (newDim > buckets.length)
            {
                resize(newDim);
                return true;
            }
            else
                return false;
        }

        pragma(inline, true)
        bool isIndexedKey(scope const(Bucket*) loc, const(size_t) hash, ref const(K) key) inout @nogc nothrow pure @safe
        {
            auto e = &entries[loc.position - 1];
            return e.hash == hash && e._key == key;
        }

        //static if(__traits(compiles, { V x; x = V.init; }))
        ref V put(ref K key, ref V value) return
        {
            size_t entryPos;
            size_t collision;
            const h = calcHash(key);
            auto i = findSlotLookupOrInsert(h, key, collision);
            auto loc = &buckets[i];
            if (!loc.filled)
            {
                if (loc.empty && grow())
                {
                    i = findSlotInsert(h, collision);
                    loc = &buckets[i];
                }

                entryPos = addEntry(h, i, key, value);
                set(loc, entryPos, collision);
            }
            else
            {
                entryPos = loc.position;
                entries[entryPos - 1].value = value;
            }
            return entries[entryPos - 1].value;
        }

        void refill() nothrow @safe
        {
            this.collision = 0;
            foreach (ei, ref e; entries)
            {
                size_t collision;
                const i = findSlotInsert(e.hash, collision);
                e.bucketIndex = i;
                set(&buckets[i], ei + 1, collision);
            }
        }

        void rehash() nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "()");

            const newDim = calcDim(entries.length, 0);
            if (newDim < buckets.length)
            {
                resize(newDim);
            }
            else
            {
                arrayZeroInit(buckets);
                refill();
            }
        }

        bool remove(ref const(K) key)
        {
            const h = calcHash(key);
            auto loc = findSlotLookup(h, key);
            if (loc is null) // Not found
                return false;

            // Remove deleted entry and update tail entries's index
            removeAt(loc.position - 1);

            return true;
        }

        bool removeAt(const(size_t) index)
        in
        {
            assert(index < entries.length);
        }
        do
        {
            auto loc = &buckets[entries[index].bucketIndex];

            // Update tail entries's index
            const entryPos = index + 1;
            if (entryPos < entries.length)
            {
                foreach (i; entryPos..entries.length)
                {
                    auto b = &buckets[entries[i].bucketIndex];
                    if (b.position > entryPos)
                        b.position--;

                    entries[i - 1] = entries[i];
                }
            }

            // Reduce the length
            entries.length = entries.length - 1;

            // Mark bucket slot as removed
            loc.position = INDEX_REMOVED;
            
            if (entries.length * SHRINK_DEN < buckets.length * SHRINK_NUM)
                shrink();
            
            return true;
        }

        ref V require(ref K key, lazy V value) return
        {
            size_t collision;
            const h = calcHash(key);
            auto i = findSlotLookupOrInsert(h, key, collision);
            auto loc = &buckets[i];
            if (!loc.filled)
            {
                if (loc.empty && grow())
                {
                    i = findSlotInsert(h, collision);
                    loc = &buckets[i];
                }

                entries ~= Entry(h, i, key, value);
                set(loc, entries.length, collision);
            }
            return entries[loc.position - 1].value;
        }

        void resize(const(size_t) newDim) nothrow pure @safe
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "(buckets.length=", buckets.length,
            //    ", newDim=", newDim, ", entries.length=", entries.length, ")");

            auto oldBuckets = buckets;

            this.buckets = allocBuckets(newDim);
            version(usePrimeFirstSlot) this.bucketPrime = getMaxPrime(this.buckets.length - 1);
            refill();

            // safe to free b/c impossible to reference
            arrayFree!Bucket(oldBuckets);
        }

        pragma(inline, true)
        void set(scope Bucket* loc, const(size_t) entryPosition, const(size_t) collision) nothrow pure @safe
        {
            loc.position = entryPosition;
            if (this.collision < collision)
            {
                version(usePrimeFirstSlot)
                {
                    debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__,
                        ".", K.stringof, "(buckets.length=", buckets.length, ", entries.length=", entries.length, ", collision=", collision, ", bucketPrime=", bucketPrime, ")");
                }
                else
                    debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__,
                        ".", K.stringof, "(buckets.length=", buckets.length, ", entries.length=", entries.length, ", collision=", collision, ")");

                this.collision = collision;
            }
        }

        void shrink()
        {
            //debug(debug_pham_utl_utl_array_dictionary) static if (isIntegral!K) if (!__ctfe) debug writeln(__FUNCTION__, "()");

            const newDim = calcDim(entries.length, 0);
            if (newDim > INIT_NUM_BUCKETS && newDim < buckets.length)
                resize(newDim);
        }

        size_t toHash() const nothrow scope
        {
            size_t result;
            foreach (ref entry; entries)
            {
                result += hashOf(hashOf(entry.value), hashOf(entry.key));
            }
            return result;
        }

        ref V update(C, U)(ref K key, scope C createVal, scope U updateVal) return
        {
            size_t collision;
            const h = calcHash(key);
            auto i = findSlotLookupOrInsert(h, key, collision);
            auto loc = &buckets[i];
            if (!loc.filled)
            {
                if (loc.empty && grow())
                {
                    i = findSlotInsert(h, collision);
                    loc = &buckets[i];
                }

                entries ~= Entry(h, i, key, createVal());
                set(loc, entries.length, collision);
            }
            else
            {
                updateVal(entries[loc.position - 1].value);
            }
            return entries[loc.position - 1].value;
        }

        pragma(inline, true)
        @property size_t mask() const @nogc nothrow pure @safe
        {
            return buckets.length - 1;
        }

        Bucket[] buckets;
        Entry[] entries;
        version(usePrimeFirstSlot) size_t bucketPrime;
        size_t collision;
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

    // grow threshold
    enum GROW_NUM = 4;
    enum GROW_DEN = 5;

    // grow factor
    enum GROW_FAC = 4;

    // shrink threshold
    enum SHRINK_NUM = 1;
    enum SHRINK_DEN = 8;

    // growing the AA doubles it's size, so the shrink threshold must be
    // smaller than half the grow threshold to have a hysteresis
    static assert(GROW_FAC * SHRINK_NUM * GROW_DEN < GROW_NUM * SHRINK_DEN);

    // initial load factor (for literals), mean of both thresholds
    //enum INIT_NUM = (GROW_DEN * SHRINK_NUM + GROW_NUM * SHRINK_DEN) / 2;
    //enum INIT_DEN = SHRINK_DEN * GROW_DEN;

    enum INIT_NUM_BUCKETS = 16u;

    static size_t calcDim(const(size_t) requiredLength, size_t bucketLength) @nogc nothrow pure @safe
    {
        if (bucketLength == 0 && requiredLength < INIT_NUM_BUCKETS)
            return INIT_NUM_BUCKETS;

        const requiredBucketLength = requiredLength == 0 ? (INIT_NUM_BUCKETS * GROW_DEN) : (requiredLength * GROW_DEN);
        size_t result = bucketLength == 0 ? (INIT_NUM_BUCKETS * GROW_FAC) : bucketLength;
        while (requiredBucketLength > result * GROW_NUM)
            result = result * GROW_FAC;
        assert(result > requiredLength);
        return result;
    }

    static size_t calcHash(ref const(K) key)
    {
        version(usePrimeFirstSlot)
            const hash = hashOf(key);
        else
            const hash = mixMurmurHash2(hashOf(key));
        return hash != 0 ? hash : 1u;
    }

    static size_t mixMurmurHash2(size_t hash) @nogc nothrow pure @safe
    {
        // final mix function of MurmurHash2
        enum m = 0x5bd1e995;
        hash ^= hash >> 13;
        hash *= m;
        hash ^= hash >> 15;
        return hash;
    }

private:
    Impl* aa;
}

auto asAA(K, V)(Dictionary!(K, V) aa) @trusted
{
    if (aa.length)
    {
        // need to build the AA from the hash
        V[K] result;
        foreach (e; aa[])
        {
            result[e.key] = e.value;
        }
        return result;
    }

    return V[K].init;
}


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

version(none)
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
        foreach (i; 0 .. keys.length)
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

    Dictionary!(int, int) aa;
    foreach (int i; 0..100)
        aa[i] = i;
    assert(aa.length == 100);
    foreach (int i; 0..100)
        assert(i in aa);
    foreach (int i; 0..50)
        assert(aa.remove(i));
    foreach (int i; 50..100)
        assert(i in aa);
    foreach (int i; 50..100)
        assert(aa.remove(i));
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
    static struct Json {
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
    map.rehash;
}

unittest // Dictionary issue14104()
{
    alias K = const(ubyte)*;
    Dictionary!(K, size_t) aa;
    immutable key = cast(K)(cast(size_t) uint.max + 1);
    aa[key] = 12;
    assert(key in aa);
}

version(none)
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
    import core.memory;

    Dictionary!(size_t, size_t) glob;

    class Foo
    {
        size_t count;

        this (size_t entries) @safe
        {
            this.count = entries;
            foreach (idx; 0 .. entries)
                glob[idx] = idx;
        }

        ~this () @safe
        {
            foreach (idx; 0 .. this.count)
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

unittest // Dictionary miscTests2()
{
    Dictionary!(int, int) aa;
    foreach (k, v; aa)
        assert(false);
    foreach (v; aa)
        assert(false);
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

unittest // Dictionary testRemove()
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
    foreach (i; 0 .. 6)
        aa[i] = i;
    foreach (i; 0 .. 6)
        assert(aa.remove(i));
    foreach (i; 6 .. 10)
        aa[i] = i;
    assert(aa.length == 4);
    foreach (i; 6 .. 10)
        assert(i in aa);
}

unittest // Dictionary testClear()
{
    Dictionary!(int, int) aa;
    assert(aa.length == 0);
    foreach (i; 0 .. 100)
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
