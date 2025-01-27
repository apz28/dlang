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

module pham.utl.utl_prime;

import std.math : sqrt;

@safe:

enum size_t hashPrime = 101;

// This is the maximum prime smaller than int.max/uint.max
//enum uint maxPrimeLength2B = 2_147_483_587;
enum uint maxPrimeLength4B = 4_294_967_291;

static immutable uint[] primeLengths = [
    11, 17, 23, 29, 37, 47, 59, 71, 89, 107, 131, 163, 197, 239, 293, 353, 431, 521, 631, 761, 919,
    1_103, 1_327, 1_597, 1_931, 2_333, 2_801, 3_371, 4_049, 4_861, 5_839, 7_013, 8_419,
    10_103, 12_143, 14_591, 17_519, 21_023, 25_229, 30_293, 36_353, 43_627, 52_361, 62_851, 75_431, 90_523,
    108_631, 130_363, 156_437, 187_751, 225_307, 270_371, 324_449, 389_357, 467_237, 560_689, 672_827, 807_403, 968_897,
    1_162_687, 1_395_263, 1_674_319, 2_009_191, 2_411_033, 2_893_249, 3_471_899, 4_166_287, 4_999_559, 5_999_471, 7_199_369
];

/**
 * Returns grow to length in prime number
 * Allow the hashtables to grow to maximum possible length (~4B elements)
 * before encountering capacity overflow.
 * Params:
 *  oldLength = current length
 */
size_t expandPrimeLength(const(size_t) oldLength) @nogc nothrow pure
{
    const increment = oldLength > 1_000
        ? (oldLength / 2)
        : (oldLength != 0 ? oldLength : 8);
    const newLength = oldLength + increment;

    if (newLength > maxPrimeLength4B)
    {
        assert(maxPrimeLength4B > oldLength, "Overflow prime length");

        return maxPrimeLength4B;
    }

    return getPrime(newLength);
}

/**
 * Returns a prime number which is less than or equal to max.
 * If no prime number found, returns 3
 * Params:
 *  max = maximum posititive number that the result must be satisfied
 */
size_t getMaxPrime(const(size_t) max) @nogc nothrow pure
{
    for (size_t i = (max-1 | 1); i > 3; i -= 2)
    {
        if (isPrime(i) && ((i - 1) % hashPrime != 0))
            return i;
    }

    return 3;
}

/**
 * Returns a next prime number which is greater than min.
 * If no next prime number found, returns parameter min
 * Params:
 *  min = minimum posititive number that the result must be satisfied
 */
size_t getPrime(const(size_t) min) @nogc nothrow pure
{
    for (size_t i = (min | 1); i < size_t.max; i += 2)
    {
        if (isPrime(i) && ((i - 1) % hashPrime != 0))
            return i;
    }

    return min;
}

/**
 * Same as getPrime but suitable for array length
 */
size_t getPrimeLength(const(size_t) min) @nogc nothrow pure
{
    foreach (prime; primeLengths)
    {
        if (prime >= min)
            return prime;
    }

    // Outside of our predefined table. Compute the hard way.
    return getPrime(min);
}

/**
 * Returns true if candidate is a prime number
 * Params:
 *  candidate = a position number to be checked
 * Returns:
 */
bool isPrime(const(size_t) candidate) @nogc nothrow pure
{
    if ((candidate & 1) != 0)
    {
        const limit = cast(size_t)sqrt(cast(double)candidate);
        for (size_t divisor = 3; divisor <= limit; divisor += 2)
        {
            if ((candidate % divisor) == 0)
                return false;
        }
        return true;
    }
    return candidate == 2;
}

version(none)
unittest
{
    import std.stdio : writeln;

    debug writeln("Largest prime number less than ", uint.max.stringof, " is ", getMaxPrime(uint.max - 1));
}

unittest // getPrimeLength
{
    assert(getPrimeLength(1) == 11);
    assert(getPrimeLength(1_450) == 1_597);
}
