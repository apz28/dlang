/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.cp_random;

import std.algorithm.searching : all;
import std.random : isUniformRNG, Random;
import std.range.primitives : isOutputRange, put;
import std.traits : isUnsigned, Unqual;
import std.typecons : No, Yes;

version (profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_big_integer : BigInteger, defaultParseBigIntegerOptions, isProbablyPrime, probablyPrimeTestIterations;
import pham.cp.cp_cipher : CipherBuffer;
import pham.cp.cp_cipher_prime_number;

nothrow @safe:

T cipherUniformRandom(RandomGen, T, string boundaries = "[]")(ref RandomGen rng, const(T) a, const(T) b) @nogc
if (isUniformRNG!RandomGen && isUnsigned!T && boundaries.length == 2)
in
{
    assert(a < T.max);
    assert(a+1 < b);
}
do
{
    import std.conv : unsigned;
    import std.random : uniform;

    static if (boundaries[0] == '(')
    {
        const lower = cast(T)(a + 1u);
    }
    else static if (boundaries[0] == '[')
    {
        const lower = a;
    }
    else
        static assert(0, "Invalid boundaries[0]: '" ~ boundaries[0] ~ "'");

    static if (boundaries[1] == ')')
    {
        const upperDist = unsigned(b - lower);
    }
    else static if (boundaries[1] == ']')
    {
        // Special case - all bits are occupied?
        if (lower == T.min && b == T.max)
            return uniform!T(rng);

        const upperDist = unsigned(b - lower) + 1u;
    }
    else
        static assert(0, "Invalid boundaries[1]: '" ~ boundaries[1] ~ "'");

    assert(upperDist != 0);
    alias UpperType = Unqual!(typeof(upperDist));
    static assert(UpperType.min == 0);

    UpperType rngNum, offset, bucketFront;
    do
    {
        rngNum = uniform!UpperType(rng);
        offset = rngNum % upperDist;
        bucketFront = rngNum - offset;
    } // while we're in an unfair bucket...
    while (bucketFront > (UpperType.max - (upperDist - 1)));

    return cast(T)(lower + offset);
}

struct CipherRandomGenerator
{
nothrow @safe:

public:
    size_t front() @nogc
    {
        if (p >= buffer.length)
            fillBuffer();
        return buffer[p];
    }

    /**
     * Returns next random value
     * Params:
     *  nextMin = minimum value inclusive
     *  nextMax = maximum value inclusive
     * Returns:
     *  value x such that nextMin <= x <= nextMax
     */
    T next(T)(T nextMin = T.min, T nextMax = T.max) @nogc
    if (isUnsigned!T)
    in
    {
        assert(nextMin < T.max);
        assert(nextMin+1 < nextMax);
    }
    do
    {
        return cipherUniformRandom(this, nextMin, nextMax);
    }

    ref Writer nextAlphaNumCharacters(Writer)(return ref Writer sink, size_t count)
    if (isOutputRange!(Writer, char))
    in
    {
        assert(count != 0);
    }
    do
    {
        import std.ascii : digits, letters;
        static immutable alphaNumChars = digits ~ letters;

        while (count--)
        {
            put(sink, alphaNumChars[next!ubyte(0, alphaNumChars.length - 1)]);
        }

        return sink;
    }

    BigInteger nextBigInteger(size_t bitLength)
    in
    {
        assert(bitLength >= 8);
    }
    do
    {
        CipherBuffer!ubyte buffer;
        nextBytes(buffer, (bitLength + 7) / 8);
        return BigInteger(buffer[], Yes.unsigned);
    }

    /// Creates a random BigInteger in [0..limit)
    BigInteger nextBigInteger1(const(BigInteger) limit)
    in
    {
        assert(limit >= uint.max);
    }
    do
    {
        const bitLength = limit.bitLength;
	    while (true)
        {
            auto r = nextBigInteger(bitLength);
	    	if (r < limit)
		    	return r;
	    }
    }

    /// Creates a random BigInteger in (min..max)
    BigInteger nextBigInteger2(const(BigInteger) min, const(BigInteger) max)
    in
    {
        assert(min+1 < max);
    }
    do
    {
        const r = nextBigInteger(max.bitLength);
        return r % (max - min + 1) + min;
    }

    BigInteger nextBigIntegerPrime(const(uint) bitLength, const(ushort) testIterations = probablyPrimeTestIterations)
    in
    {
        assert(bitLength >= 8);
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

    	const b = bitLength % 8 == 0 ? 8 : bitLength % 8;
        const bs = (bitLength + 7) / 8;
        CipherBuffer!ubyte buffer;

        while (true)
        {
            nextBytes(buffer.clear(), bs);

		    // Don't let the value be too small, i.e, set the most significant two bits.
		    // Setting the top two bits, rather than just the top bit,
		    // means that when two of these values are multiplied together,
		    // the result isn't ever one bit short.
			buffer[bs - 1] |= 0xC0;

		    // Clear bits in the first byte to make sure the candidate has a size <= bits.
		    buffer[bs - 1] &= cast(ubyte)((1 << b) - 1);

		    // Make the value odd since an even number this large certainly isn't prime.
		    buffer[0] |= 1;

            // smallPrimes is a list of small, prime numbers that allows us to rapidly
            // exclude some fraction of composite candidates when searching for a random
            // prime. This list is truncated at the point where smallPrimesProduct exceeds
            // a uint64. It does not include two because we ensure that the candidates are
            // odd by construction.
            static immutable ubyte[] smallPrimes = [
	            3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53,
                ];

            static immutable smallPrimesProduct = BigInteger(16_294_579_238_595_022_365UL);

            auto tryResult = BigInteger(buffer[], Yes.unsigned);
		    const mod = (tryResult % smallPrimesProduct).toULong;
		    for (ulong delta = 0UL; delta < 1UL<<20; delta += 2)
            {
		        // Calculate the value mod the product of smallPrimes. If it's
		        // a multiple of any of these primes we add two until it isn't.
		        // The probability of overflowing is minimal and can be ignored
		        // because we still perform Miller-Rabin tests on the result.
                auto nextDelta = false;
			    const m = mod + delta;
			    foreach (prime; smallPrimes)
                {
				    if (m % cast(uint)prime == 0 && (bitLength > 6 || m != cast(uint)prime))
                    {
                        nextDelta = true;
                        break;
                    }
			    }

                if (!nextDelta)
                {
                    auto result = tryResult.dup;
                    if (delta != 0)
                        result += delta;

                    // There is a tiny possibility that, by adding delta, we caused
	    	        // the number to be one bit too long. Thus we check bitLength here.
                    // Overflow -> no need to try delta
                    if (result.bitLength > bitLength)
                        break;
                    if (isProbablyPrime(result, &nextBigInteger1, testIterations))
			            return result;
                }
		    }
        }

        assert(0);
    }

    ref Writer nextBytes(Writer)(return ref Writer sink, size_t count)
    if (isOutputRange!(Writer, ubyte))
    in
    {
        assert(count != 0);
    }
    do
    {
        version (profile) debug auto p = PerfFunction.create();

        // Exclude 0 or FF for first byte
        put(sink, next!ubyte(1, ubyte.max-1));
        count--;

        while (count > 1)
        {
            put(sink, next!ubyte(0, ubyte.max));
            count--;
        }

        // Exclude 0 or FF for last byte
        if (count)
            put(sink, next!ubyte(1, ubyte.max-1));

        return sink;
    }

    ref Writer nextCharacters(Writer)(return ref Writer sink, size_t count)
    if (isOutputRange!(Writer, char))
    in
    {
        assert(count != 0);
    }
    do
    {
        while (count--)
        {
            // Excluse 0 (null) char
            put(sink, cast(char)next!ubyte(1, 127));
        }
        return sink;
    }

    ref Writer nextDigits(Writer)(return ref Writer sink, size_t count)
    if (isOutputRange!(Writer, char))
    in
    {
        assert(count != 0);
    }
    do
    {
        import std.ascii : digits;

         // Excluse 0 for first digit
        put(sink, digits[next!ubyte(1, digits.length - 1)]);
        count--;
        
        while (count > 1)
        {
            put(sink, digits[next!ubyte(0, digits.length - 1)]);
            count--;
        }
        
         // Excluse 0 for last digit
        if (count)
            put(sink, digits[next!ubyte(1, digits.length - 1)]);

        return sink;
    }

    ref Writer nextHexDigits(Writer)(return ref Writer sink, size_t count,
        bool leadingIndicator = true)
    if (isOutputRange!(Writer, char))
    in
    {
        assert(count != 0);
    }
    do
    {
        import std.ascii : hexDigits;

        if (leadingIndicator)
        {
            put(sink, '0');
            put(sink, 'x');
        }

        // Excluse 0 or F for first hexdigit
        put(sink, hexDigits[next!ubyte(1, hexDigits.length - 2)]);
        count--;

        while (count > 1)
        {
            put(sink, hexDigits[next!ubyte(0, hexDigits.length - 1)]);
            count--;
        }

        // Excluse 0 or F for last hexdigit
        if (count)
            put(sink, hexDigits[next!ubyte(1, hexDigits.length - 2)]);

        return sink;
    }

    ushort nextSmallPrime(ushort nextMin = ushort.min, ushort nextMax = ushort.max) @nogc
    in
    {
        assert(nextMin < ushort.max);
        assert(nextMin+1 < nextMax);
    }
    do
    {
        initRnd();

        while (true)
        {
            const result = ushortPrimes[cipherUniformRandom(this.rnd, 0, ushortPrimes.length - 1)];
            if (result >= nextMin && result <= nextMax)
                return result;
        }
    }

    pragma(inline, true)
    void popFront() @nogc
    {
        p++;
    }

    // For satisfying UniformRandomNumberGenerator
    enum bool empty = false;
    enum bool isUniformRandom = true;
    enum size_t max = size_t.max;
    enum size_t min = size_t.min;

private:
    void fillBuffer() @nogc
    {
        initRnd();

        foreach (i; 0..buffer.length)
        {
            buffer[i] = cipherUniformRandom(this.rnd, 0, size_t.max);
        }

        p = 0;
    }

    pragma(inline, true)
    void initRnd() @nogc
    {
        import std.random : unpredictableSeed;

        if (!inited)
        {
            rnd.seed(unpredictableSeed);
            inited = true;
        }
    }

private:
    enum bufferLength = 64;
    size_t[bufferLength] buffer;
    size_t p = bufferLength;
    Random rnd;
    bool inited;
}


private:

unittest // CipherRandomGenerator.nextBigIntegerPrime
{
    import pham.utl.utl_test : PerfTestResult;
    
    auto perf = PerfTestResult.create();
    BigInteger p;
    CipherRandomGenerator rnd;

    //dgWrite(128); perf.reset();
    p = rnd.nextBigIntegerPrime(128);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());

    //dgWrite(256); perf.reset();
    p = rnd.nextBigIntegerPrime(256);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());

    //dgWrite(512); perf.reset();
    p = rnd.nextBigIntegerPrime(512);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());

    //TODO - speed up logic before enable these tests

    //dgWrite(1_024); perf.reset();
    //p = rnd.nextBigIntegerPrime(1_024);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());

    //dgWrite(2_048); perf.reset();
    //p = rnd.nextBigIntegerPrime(2_048);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());

    //dgWrite(4_096); perf.reset();
    //p = rnd.nextBigIntegerPrime(4_096);
    //dgWriteln(":", perf.end().elapsedTimeMsecs); dgWriteln(p.toString());
}
