/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * A clone from https://github.com/dotnet/corefx
 * tree/master/src/System.Runtime.Numerics/src/System/Numerics
 */

module pham.utl.utl_big_integer_calculator;

import std.algorithm : swap;

import pham.utl.utl_array : IndexedArray;

nothrow @safe:

// Threadhold if we can use stack memory for speed
enum allocationThreshold = 250;

alias CharTempArray = IndexedArray!(char, allocationThreshold * uint.sizeof);
alias UByteTempArray = IndexedArray!(ubyte, allocationThreshold * uint.sizeof);
alias UIntTempArray = IndexedArray!(uint, allocationThreshold);

package(pham.utl):

// To spare memory allocations a buffer helps reusing memory!
// We just create the target array twice and switch between every
// operation. In order to not compute unnecessarily with all those
// leading zeros we take care of the current actual length.
struct BitsBuffer
{
nothrow @safe:

public:
    this(size_t size, uint value) pure
    in
    {
        assert(size >= 1);
    }
    do
    {
        _bits.length = size;
        _bits[0] = value;
        _length = value != 0 ? 1 : 0;
    }

    this(size_t size, scope const(uint)[] value) pure
    in
    {
        assert(size >= BigIntegerCalculator.actualLength(value, value.length));
    }
    do
    {
        _bits.length = size;
        _length = BigIntegerCalculator.actualLength(value, value.length);
        if (_length)
            _bits.put(value[0.._length], 0);
    }

    this(size_t size, UIntTempArray value) pure
    {
        this(size, value[]);
    }

    uint[] opIndex() pure return
    {
        return _bits[];
    }

    uint[] dup() pure
    {
        return this[].dup;
    }

    void multiplySelf(ref BitsBuffer value, ref BitsBuffer temp) pure
    in
    {
        assert(temp.length == 0);
        assert(length + value.length <= temp.size);
    }
    do
    {
        // Executes a multiplication for this and value, writes the
        // result to temp. Switches this and temp arrays afterwards.

        const dLength = length + value.length;
        if (length < value.length)
            BigIntegerCalculator.multiply(value.ptr(0), value.length, ptr(0), length, temp.ptr(0), dLength);
        else
            BigIntegerCalculator.multiply(ptr(0), length, value.ptr(0), value.length, temp.ptr(0), dLength);

        apply(temp, dLength);
    }

    void squareSelf(ref BitsBuffer temp) pure
    in
    {
        assert(temp.length == 0);
        assert(length + length <= temp.size);
    }
    do
    {
        // Executes a square for this, writes the result to temp.
        // Switches this and temp arrays afterwards.

        const dLength = length + length;
        BigIntegerCalculator.square(ptr(0), length, temp.ptr(0), dLength);
        apply(temp, dLength);
    }

    void reduce(ref FastReducer reducer) pure
    {
        // Executes a modulo operation using an optimized reducer.
        // Thus, no need of any switching here, happens in-line.

        _length = reducer.reduce(_bits, _length);
    }

    void reduce(scope const(uint)[] modulus) pure
    {
        // Executes a modulo operation using the divide operation.
        // Thus, no need of any switching here, happens in-line.

        if (_length >= modulus.length)
        {
            BigIntegerCalculator.divide(ptr(0), _length, &modulus[0], modulus.length, null, 0);
            _length = BigIntegerCalculator.actualLength(_bits, modulus.length);
        }
    }

    void reduce(ref BitsBuffer modulus) pure
    {
        // Executes a modulo operation using the divide operation.
        // Thus, no need of any switching here, happens in-line.

        if (length >= modulus.length)
        {
            BigIntegerCalculator.divide(ptr(0), length, modulus.ptr(0), modulus.length, null, 0);
            _length = BigIntegerCalculator.actualLength(_bits, modulus.length);
        }
    }

    void overwrite(ulong value) pure
    in
    {
        assert(_bits.length >= 2);
    }
    do
    {
        // Ensure leading zeros
        if (_length > 2)
            _bits.fill(0);

        const uint lo = cast(uint)value;
        const uint hi = cast(uint)(value >> 32);

        _bits[0] = lo;
        _bits[1] = hi;
        _length = hi != 0 ? 2 : (lo != 0 ? 1 : 0);
    }

    void overwrite(uint value) pure
    in
    {
        assert(_bits.length >= 1);
    }
    do
    {
        // Ensure leading zeros
        if (_length > 1)
            _bits.fill(0);

        _bits[0] = value;
        _length = value != 0 ? 1 : 0;
    }

    pragma(inline, true)
    uint* ptr(size_t index) pure return
    {
        return _bits.ptr(index);
    }

    void refresh(size_t maxLength) pure
    in
    {
        assert(_bits.length >= maxLength);
    }
    do
    {
        // Ensure leading zeros
        if (_length > maxLength)
            _bits.fill(0, maxLength);

        _length = BigIntegerCalculator.actualLength(_bits, maxLength);
    }

    private void apply(ref BitsBuffer temp, size_t maxLength) pure
    in
    {
        assert(temp.length == 0);
        assert(maxLength <= temp.size);
    }
    do
    {
        // Resets this and switches this and temp afterwards.
        // The caller assumed an empty temp, the next will too.

        _bits.fill(0);
        swap(temp._bits, _bits);
        _length = BigIntegerCalculator.actualLength(_bits, maxLength);
    }

    pragma(inline, true)
    @property size_t length() const @nogc pure
    {
        return _length;
    }

    pragma(inline, true)
    @property size_t size() const @nogc pure
    {
        return _bits.length;
    }

private:
    size_t _length;
    UIntTempArray _bits;
}

// If we need to reduce by a certain modulus again and again, it's much
// more efficient to do this with multiplication operations. This is
// possible, if we do some pre-computations first...
// see https://en.wikipedia.org/wiki/Barrett_reduction
struct FastReducer
{
nothrow @safe:

public:
    this(scope const(uint)[] modulus) pure
    {
        const dModulusLen = modulus.length * 2;

        // Let r = 4^k, with 2^k > m
        auto r = UIntTempArray(0);
        r.length = dModulusLen + 1;
        r[r.length - 1] = 1;

        // Let mu = 4^k / m
        _mu = BigIntegerCalculator.divide(r[], modulus);
        _modulus = UIntTempArray(modulus);

        // Allocate memory for quotients once
        _q1.length = dModulusLen + 2;
        _q2.length = dModulusLen + 1;

        _muLength = BigIntegerCalculator.actualLength(_mu, _mu.length);
    }

    size_t reduce(ref UIntTempArray value, size_t length) pure
    in
    {
        assert(length <= value.length);
        assert(value.length <= _modulus.length * 2);
    }
    do
    {
        // Trivial: value is shorter
        if (length < _modulus.length)
            return length;

        // Let q1 = v/2^(k-1) * mu
        size_t l1 = divMul(value, length, _mu, _muLength, _q1, _modulus.length - 1);

        // Let q2 = q1/2^(k+1) * m
        size_t l2 = divMul(_q1, l1, _modulus, _modulus.length, _q2, _modulus.length + 1);

        // Let v = (v - q2) % 2^(k+1) - i*m
        return subMod(value, length, _q2, l2, _modulus, _modulus.length + 1);
    }

private:
    static size_t divMul(ref UIntTempArray left, size_t leftLength,
        ref UIntTempArray right, size_t rightLength,
        ref UIntTempArray bits, size_t k) pure @trusted
    in
    {
        assert(left.length >= leftLength);
        assert(right.length >= rightLength);
        assert(bits.length + k >= leftLength + rightLength);
    }
    do
    {
        // Executes the multiplication algorithm for left and right,
        // but skips the first k limbs of left, which is equivalent to
        // preceding division by 2^(32*k). To spare memory allocations
        // we write the result to an already allocated memory.
        bits.fill(0);

        if (left.length > k)
        {
            leftLength -= k;

            if (leftLength < rightLength)
            {
                BigIntegerCalculator.multiply(right.ptr(0), rightLength,
                    left.ptr(k), leftLength,
                    bits.ptr(0), leftLength + rightLength);
            }
            else
            {
                BigIntegerCalculator.multiply(left.ptr(k), leftLength,
                    right.ptr(0), rightLength,
                    bits.ptr(0), leftLength + rightLength);
            }

            return BigIntegerCalculator.actualLength(bits, leftLength + rightLength);
        }

        return 0;
    }

    static size_t subMod(ref UIntTempArray left, size_t leftLength,
        ref UIntTempArray right, size_t rightLength,
        ref UIntTempArray modulus, size_t k) pure
    in
    {
        assert(left.length >= leftLength);
        assert(right.length >= rightLength);
    }
    do
    {
        // Executes the subtraction algorithm for left and right,
        // but considers only the first k limbs, which is equivalent to
        // preceding reduction by 2^(32*k). Furthermore, if left is
        // still greater than modulus, further subtractions are used.

        if (leftLength > k)
            leftLength = k;
        if (rightLength > k)
            rightLength = k;

        BigIntegerCalculator.subtractSelf(left.ptr(0), leftLength, right.ptr(0), rightLength);
        leftLength = BigIntegerCalculator.actualLength(left, leftLength);

        while (BigIntegerCalculator.compare(left.ptr(0), leftLength, modulus.ptr(0), modulus.length) >= 0)
        {
            BigIntegerCalculator.subtractSelf(left.ptr(0), leftLength, modulus.ptr(0), modulus.length);
            leftLength = BigIntegerCalculator.actualLength(left, leftLength);
        }

        if (leftLength < left.length)
            left.fill(0, leftLength);

        return leftLength;
    }

private:
    UIntTempArray _modulus;
    UIntTempArray _mu;
    UIntTempArray _q1;
    UIntTempArray _q2;
    size_t _muLength;
}

struct BigIntegerCalculator
{
nothrow @safe:

    // Do an in-place two's complement. "Dangerous" because it causes
    // a mutation and needs to be used with care for immutable types.
    version (none)
    static void makeTwosComplement(ref uint[] d) pure
    {
        if (d.length != 0)
        {
            d[0] = ~d[0] + 1;

            size_t i = 1;
            // first do complement and +1 as long as carry is needed
            for (; d[i - 1] == 0 && i < d.length; i++)
                d[i] = ~d[i] + 1;
            // now ones complement is sufficient
            for (; i < d.length; i++)
                d[i] = ~d[i];
        }
    }

    static ref UIntTempArray makeTwosComplement(return ref UIntTempArray d) pure
    {
        if (!d.empty)
        {
            d[0] = ~d[0] + 1;

            size_t i = 1;
            // first do complement and +1 as long as carry is needed
            for (; i < d.length && d[i - 1] == 0; i++)
                d[i] = ~d[i] + 1;
            // now ones complement is sufficient
            for (; i < d.length; i++)
                d[i] = ~d[i];
        }
        return d;
    }

    static double logBase(double number, double logBase) pure
    {
        import std.math : log;

        return log(number) / log(logBase);
    }

    static UIntTempArray add(scope const(uint)[] left, uint right) pure
    in
    {
        assert(left.length >= 1);
    }
    do
    {
        // Executes the addition for one big and one 32-bit integer.
        // Thus, we've similar code than below, but there is no loop for
        // processing the 32-bit integer, since it's a single element.

        auto result = UIntTempArray(0);
        result.length = left.length + 1;

        long digit = cast(long)left[0] + right;
        result[0] = cast(uint)digit;
        long carry = digit >> 32;

        for (size_t i = 1; i < left.length; i++)
        {
            digit = left[i] + carry;
            result[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        result[left.length] = cast(uint)carry;

        return result;
    }

    static UIntTempArray add(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= right.length);
    }
    do
    {
        // Switching to unsafe pointers helps sparing
        // some nasty index calculations...

        auto result = UIntTempArray(0);
        result.length = left.length + 1;
        add(&left[0], left.length, &right[0], right.length, result.ptr(0), result.length);
        return result;
    }

    private static void add(scope const(uint)* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength,
        uint* bits, size_t bitsLength) pure @trusted
    in
    {
        assert(leftLength >= rightLength);
        assert(bitsLength == leftLength + 1);
    }
    do
    {
        // Executes the "grammar-school" algorithm for computing z = a + b.
        // While calculating z_i = a_i + b_i we take care of overflow:
        // Since a_i + b_i + c <= 2(2^32 - 1) + 1 = 2^33 - 1, our carry c
        // has always the value 1 or 0; hence, we're safe here.

        size_t i = 0;
        long carry = 0L;

        for (; i < rightLength; i++)
        {
            long digit = (left[i] + carry) + right[i];
            bits[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; i < leftLength; i++)
        {
            long digit = left[i] + carry;
            bits[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        bits[i] = cast(uint)carry;
    }

    private static void addSelf(scope uint* left, size_t leftLength,
        scope uint* right, size_t rightLength) pure @trusted
    in
    {
        assert(leftLength >= 0);
        assert(rightLength >= 0);
        assert(leftLength >= rightLength);
    }
    do
    {
        // Executes the "grammar-school" algorithm for computing z = a + b.
        // Same as above, but we're writing the result directly to a and
        // stop execution, if we're out of b and c is already 0.

        size_t i = 0;
        long carry = 0L;

        for (; i < rightLength; i++)
        {
            const long digit = (left[i] + carry) + right[i];
            left[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; carry != 0 && i < leftLength; i++)
        {
            const long digit = left[i] + carry;
            left[i] = cast(uint)digit;
            carry = digit >> 32;
        }

        assert(carry == 0);
    }

    static UIntTempArray subtract(scope const(uint)[] left, uint right) pure
    in
    {
        assert(left.length >= 1);
        assert(left[0] >= right || left.length >= 2);
    }
    do
    {
        // Executes the subtraction for one big and one 32-bit integer.
        // Thus, we've similar code than below, but there is no loop for
        // processing the 32-bit integer, since it's a single element.

        auto result = UIntTempArray(0);
        result.length = left.length;

        long digit = cast(long)left[0] - right;
        result[0] = cast(uint)digit;
        long carry = digit >> 32;

        for (size_t i = 1; i < left.length; i++)
        {
            digit = left[i] + carry;
            result[i] = cast(uint)digit;
            carry = digit >> 32;
        }

        return result;
    }

    static UIntTempArray subtract(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= right.length);
        assert(compare(left, right) >= 0);
    }
    do
    {
        // Switching to unsafe pointers helps sparing
        // some nasty index calculations...

        auto result = UIntTempArray(0);
        result.length = left.length;
        subtract(&left[0], left.length, &right[0], right.length, result.ptr(0), result.length);
        return result;
    }

    private static void subtract(scope const(uint)* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength,
        uint* bits, size_t bitsLength) pure @trusted
    in
    {
        assert(leftLength >= rightLength);
        assert(compare(left, leftLength, right, rightLength) >= 0);
        assert(bitsLength == leftLength);
    }
    do
    {
        // Executes the "grammar-school" algorithm for computing z = a - b.
        // While calculating z_i = a_i - b_i we take care of overflow:
        // Since a_i - b_i doesn't need any additional bit, our carry c
        // has always the value -1 or 0; hence, we're safe here.

        size_t i = 0;
        long carry = 0L;

        for (; i < rightLength; i++)
        {
            const long digit = (left[i] + carry) - right[i];
            bits[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; i < leftLength; i++)
        {
            const long digit = left[i] + carry;
            bits[i] = cast(uint)digit;
            carry = digit >> 32;
        }

        assert(carry == 0);
    }

    private static void subtractSelf(scope uint* left, size_t leftLength,
        scope uint* right, size_t rightLength) pure @trusted
    in
    {
        assert(leftLength >= rightLength);
        assert(compare(left, leftLength, right, rightLength) >= 0);
    }
    do
    {
        // Executes the "grammar-school" algorithm for computing z = a - b.
        // Same as above, but we're writing the result directly to a and
        // stop execution, if we're out of b and c is already 0.

        size_t i = 0;
        long carry = 0L;

        for (; i < rightLength; i++)
        {
            const long digit = (left[i] + carry) - right[i];
            left[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; carry != 0 && i < leftLength; i++)
        {
            const long digit = left[i] + carry;
            left[i] = cast(uint)digit;
            carry = digit >> 32;
        }

        assert(carry == 0);
    }

    static int compare(scope const(uint)[] left, scope const(uint)[] right) pure
    {
        if (left.length < right.length)
            return -1;

        if (left.length > right.length)
            return 1;

        for (ptrdiff_t i = cast(ptrdiff_t)(left.length) - 1; i >= 0; i--)
        {
            if (left[i] < right[i])
                return -1;
            if (left[i] > right[i])
                return 1;
        }

        return 0;
    }

    private static int compare(scope const(uint)* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength) pure @trusted
    {
        if (leftLength < rightLength)
            return -1;

        if (leftLength > rightLength)
            return 1;

        for (ptrdiff_t i = cast(ptrdiff_t)(leftLength) - 1; i >= 0; i--)
        {
            if (left[i] < right[i])
                return -1;
            if (left[i] > right[i])
                return 1;
        }

        return 0;
    }

    static UIntTempArray divide(scope const(uint)[] left, uint right, out uint remainder) pure
    in
    {
        assert(left.length >= 1);
    }
    do
    {
        // Executes the division for one big and one 32-bit integer.
        // Thus, we've similar code than below, but there is no loop for
        // processing the 32-bit integer, since it's a single element.

        auto quotient = UIntTempArray(0);
        quotient.length = left.length;

        ulong carry = 0UL;
        for (ptrdiff_t i = cast(ptrdiff_t)(left.length) - 1; i >= 0; i--)
        {
            const ulong value = (carry << 32) | left[i];
            const ulong digit = value / right;
            quotient[i] = cast(uint)digit;
            carry = value - digit * right;
        }
        remainder = cast(uint)carry;

        return quotient;
    }

    static UIntTempArray divide(scope const(uint)[] left, uint right) pure
    in
    {
        assert(left.length >= 1);
    }
    do
    {
        // Same as above, but only computing the quotient.

        uint remainder = void;
        return divide(left, right, remainder);
    }

    static UIntTempArray divide(scope const(uint)[] left, scope const(uint)[] right,
        out UIntTempArray remainder) pure
    in
    {
        assert(left.length >= 1);
        assert(right.length >= 1);
        assert(left.length >= right.length);
    }
    do
    {
        // Switching to unsafe pointers helps sparing
        // some nasty index calculations...

        // NOTE: left will get overwritten, we need a local copy

        remainder = UIntTempArray(left);
        auto quotient = UIntTempArray(0);
        quotient.length = left.length - right.length + 1;
        divide(remainder.ptr(0), remainder.length, &right[0], right.length, quotient.ptr(0), quotient.length);
        return quotient;
    }

    static UIntTempArray divide(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= 1);
        assert(right.length >= 1);
        assert(left.length >= right.length);
    }
    do
    {
        // Same as above, but only returning the quotient.

        UIntTempArray remainder;
        return divide(left, right, remainder);
    }

    private static void divide(scope uint* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength,
        uint* bits, size_t bitsLength) pure @trusted
    in
    {
        assert(leftLength >= 1);
        assert(rightLength >= 1);
        assert(leftLength >= rightLength);
        assert(bitsLength == leftLength - rightLength + 1 || bitsLength == 0);
    }
    do
    {
        // Executes the "grammar-school" algorithm for computing q = a / b.
        // Before calculating q_i, we get more bits into the highest bit
        // block of the divisor. Thus, guessing digits of the quotient
        // will be more precise. Additionally we'll get r = a % b.

        uint divHi = right[rightLength - 1];
        uint divLo = rightLength > 1 ? right[rightLength - 2] : 0;

        // We measure the leading zeros of the divisor
        int shift = leadingZeros(divHi);
        int backShift = 32 - shift;

        // And, we make sure the most significant bit is set
        if (shift > 0)
        {
            uint divNx = rightLength > 2 ? right[rightLength - 3] : 0;

            divHi = (divHi << shift) | (divLo >> backShift);
            divLo = (divLo << shift) | (divNx >> backShift);
        }

        // Then, we divide all of the bits as we would do it using
        // pen and paper: guessing the next digit, subtracting, ...
        for (ptrdiff_t i = leftLength; i >= rightLength; i--)
        {
            const ptrdiff_t n = i - rightLength;
            const uint t = i < leftLength ? left[i] : 0;

            ulong valHi = (cast(ulong)t << 32) | left[i - 1];
            uint valLo = i > 1 ? left[i - 2] : 0;

            // We shifted the divisor, we shift the dividend too
            if (shift > 0)
            {
                const uint valNx = i > 2 ? left[i - 3] : 0;

                valHi = (valHi << shift) | (valLo >> backShift);
                valLo = (valLo << shift) | (valNx >> backShift);
            }

            // First guess for the current digit of the quotient,
            // which naturally must have only 32 bits...
            ulong digit = valHi / divHi;
            if (digit > 0xFFFFFFFF)
                digit = 0xFFFFFFFF;

            // Our first guess may be a little bit to big
            while (divideGuessTooBig(digit, valHi, valLo, divHi, divLo))
                --digit;

            if (digit > 0)
            {
                // Now it's time to subtract our current quotient
                uint carry = subtractDivisor(left + n, leftLength - n,
                                             right, rightLength, digit);
                if (carry != t)
                {
                    assert(carry == t + 1);

                    // Our guess was still exactly one too high
                    carry = addDivisor(left + n, leftLength - n, right, rightLength);
                    --digit;

                    assert(carry == 1);
                }
            }

            // We have the digit!
            if (bitsLength != 0)
                bits[n] = cast(uint)digit;
            if (i < leftLength)
                left[i] = 0;
        }
    }

    static uint remainder(scope const(uint)[] left, uint right) pure
    in
    {
        assert(left.length >= 1);
    }
    do
    {
        // Same as above, but only computing the remainder.

        ulong carry = 0UL;
        for (ptrdiff_t i = cast(ptrdiff_t)(left.length) - 1; i >= 0; i--)
        {
            const ulong value = (carry << 32) | left[i];
            carry = value % right;
        }

        return cast(uint)carry;
    }

    static UIntTempArray remainder(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= 1);
        assert(right.length >= 1);
        assert(left.length >= right.length);
    }
    do
    {
        // Same as above, but only returning the remainder.

        // NOTE: left will get overwritten, we need a local copy

        auto result = UIntTempArray(left);
        divide(result.ptr(0), result.length, &right[0], right.length, null, 0);
        return result;
    }

    private static uint addDivisor(scope uint* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength) pure @trusted
    in
    {
        assert(leftLength >= 0);
        assert(rightLength >= 0);
        assert(leftLength >= rightLength);
    }
    do
    {
        // Repairs the dividend, if the last subtract was too much

        ulong carry = 0UL;

        for (size_t i = 0; i < rightLength; i++)
        {
            const ulong digit = (left[i] + carry) + right[i];
            left[i] = cast(uint)digit;
            carry = digit >> 32;
        }

        return cast(uint)carry;
    }

    private static uint subtractDivisor(scope uint* left, size_t leftLength,
        scope const(uint)* right, size_t rightLength,
        ulong q) pure @trusted
    in
    {
        assert(leftLength >= rightLength);
        assert(q <= 0xFFFFFFFF);
    }
    do
    {
        // Combines a subtract and a multiply operation, which is naturally
        // more efficient than multiplying and then subtracting...

        ulong carry = 0UL;

        for (size_t i = 0; i < rightLength; i++)
        {
            carry += right[i] * q;
            const uint digit = cast(uint)carry;
            carry = carry >> 32;
            if (left[i] < digit)
                ++carry;
            left[i] = left[i] - digit;
        }

        return cast(uint)carry;
    }

    private static bool divideGuessTooBig(ulong q, ulong valHi, uint valLo,
        uint divHi, uint divLo) pure
    in
    {
        assert(q <= 0xFFFFFFFF);
    }
    do
    {
        // We multiply the two most significant limbs of the divisor
        // with the current guess for the quotient. If those are bigger
        // than the three most significant limbs of the current dividend
        // we return true, which means the current guess is still too big.

        ulong chkHi = divHi * q;
        ulong chkLo = divLo * q;

        chkHi = chkHi + (chkLo >> 32);
        chkLo = chkLo & 0xFFFFFFFF;

        if (chkHi < valHi)
            return false;
        if (chkHi > valHi)
            return true;

        if (chkLo < valLo)
            return false;
        if (chkLo > valLo)
            return true;

        return false;
    }

    private static uint leadingZeros(uint value) pure
    {
        if (value == 0)
            return 32;

        uint count = 0;
        if ((value & 0xFFFF0000) == 0)
        {
            count += 16;
            value = value << 16;
        }
        if ((value & 0xFF000000) == 0)
        {
            count += 8;
            value = value << 8;
        }
        if ((value & 0xF0000000) == 0)
        {
            count += 4;
            value = value << 4;
        }
        if ((value & 0xC0000000) == 0)
        {
            count += 2;
            value = value << 2;
        }
        if ((value & 0x80000000) == 0)
        {
            count += 1;
        }

        return count;
    }

    static UIntTempArray square(scope const(uint)[] value) pure
    {
        // Switching to unsafe pointers helps sparing
        // some nasty index calculations...

        auto result = UIntTempArray(0);
        result.length = value.length + value.length;
        square(&value[0], value.length, result.ptr(0), result.length);
        return result;
    }

    private static void square(scope const(uint)* value, size_t valueLength,
        uint* bits, const(size_t) bitsLength) pure @trusted
    in
    {
        assert(valueLength >= 0);
        assert(bitsLength == valueLength + valueLength);
    }
    do
    {
        // Executes different algorithms for computing z = a * a
        // based on the actual length of a. If a is "small" enough
        // we stick to the classic "grammar-school" method; for the
        // rest we switch to implementations with less complexity
        // albeit more overhead (which needs to pay off!).

        // NOTE: useful thresholds needs some "empirical" testing,
        // which are smaller in DEBUG mode for testing purpose.
        // Mutable for unit testing?
        enum int squareThreshold = 32;

        if (valueLength < squareThreshold)
        {
            // Squares the bits using the "grammar-school" method.
            // Envisioning the "rhombus" of a pen-and-paper calculation
            // we see that computing z_i+j += a_j * a_i can be optimized
            // since a_j * a_i = a_i * a_j (we're squaring after all!).
            // Thus, we directly get z_i+j += 2 * a_j * a_i + c.

            // ATTENTION: an ordinary multiplication is safe, because
            // z_i+j + a_j * a_i + c <= 2(2^32 - 1) + (2^32 - 1)^2 =
            // = 2^64 - 1 (which perfectly matches with ulong!). But
            // here we would need an UInt65... Hence, we split these
            // operation and do some extra shifts.

            for (size_t i = 0; i < valueLength; i++)
            {
                ulong carry = 0UL;
                for (size_t j = 0; j < i; j++)
                {
                    const ulong digit1 = bits[i + j] + carry;
                    const ulong digit2 = cast(ulong)value[j] * value[i];
                    bits[i + j] = cast(uint)(digit1 + (digit2 << 1));
                    carry = (digit2 + (digit1 >> 1)) >> 31;
                }
                const ulong digits = cast(ulong)value[i] * value[i] + carry;
                bits[i + i] = cast(uint)digits;
                bits[i + i + 1] = cast(uint)(digits >> 32);
            }
        }
        else
        {
            // Based on the Toom-Cook multiplication we split value
            // into two smaller values, doing recursive squaring.
            // The special form of this multiplication, where we
            // split both operands into two operands, is also known
            // as the Karatsuba algorithm...

            // https://en.wikipedia.org/wiki/Toom-Cook_multiplication
            // https://en.wikipedia.org/wiki/Karatsuba_algorithm

            // Say we want to compute z = a * a ...

            // ... we need to determine our new length (just the half)
            const n = valueLength >> 1;
            const n2 = n << 1;

            // ... split value like a = (a_1 << n) + a_0
            const(uint)* valueLow = value;
            const valueLowLength = n;
            const(uint)* valueHigh = value + n;
            const valueHighLength = valueLength - n;

            // ... prepare our result array (to reuse its memory)
            uint* bitsLow = bits;
            const bitsLowLength = n2;
            uint* bitsHigh = bits + n2;
            const bitsHighLength = bitsLength - n2;

            // ... compute z_0 = a_0 * a_0 (squaring again!)
            square(valueLow, valueLowLength, bitsLow, bitsLowLength);

            // ... compute z_2 = a_1 * a_1 (squaring again!)
            square(valueHigh, valueHighLength, bitsHigh, bitsHighLength);

            const foldLength = valueHighLength + 1;
            auto foldMem = UIntTempArray(0);
            foldMem.length = foldLength;
            auto fold = foldMem.ptr(0);

            const coreLength = foldLength + foldLength;
            auto coreMem = UIntTempArray(0);
            coreMem.length = coreLength;
            auto core = coreMem.ptr(0);

            // ... compute z_a = a_1 + a_0 (call it fold...)
            add(valueHigh, valueHighLength, valueLow, valueLowLength, fold, foldLength);

            // ... compute z_1 = z_a * z_a - z_0 - z_2
            square(fold, foldLength, core, coreLength);
            subtractCore(bitsHigh, bitsHighLength, bitsLow, bitsLowLength, core, coreLength);

            // ... and finally merge the result! :-)
            addSelf(&bits[n], bitsLength - n, core, coreLength);
        }
    }

    static UIntTempArray multiply(scope const(uint)[] left, uint right) pure
    {
        // Executes the multiplication for one big and one 32-bit integer.
        // Since every step holds the already slightly familiar equation
        // a_i * b + c <= 2^32 - 1 + (2^32 - 1)^2 < 2^64 - 1,
        // we are safe regarding to overflows.

        auto result = UIntTempArray(0);
        result.length = left.length + 1;

        ulong carry = 0UL;
        size_t i = 0;
        for (; i < left.length; i++)
        {
            const ulong digits = cast(ulong)left[i] * right + carry;
            result[i] = cast(uint)digits;
            carry = digits >> 32;
        }
        result[i] = cast(uint)carry;

        return result;
    }

    static UIntTempArray multiply(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= right.length);
    }
    do
    {
        // Switching to unsafe pointers helps sparing
        // some nasty index calculations...

        auto result = UIntTempArray(0);
        result.length = left.length + right.length;
        multiply(&left[0], left.length, &right[0], right.length, result.ptr(0), result.length);
        return result;
    }

    private static void multiply(scope const(uint)* left, const(size_t) leftLength,
        scope const(uint)* right, const(size_t) rightLength,
        uint* bits, const(size_t) bitsLength) pure @trusted
    in
    {
        assert(leftLength >= 0);
        assert(rightLength >= 0);
        assert(leftLength >= rightLength);
        assert(bitsLength == leftLength + rightLength);
    }
    do
    {
        // Executes different algorithms for computing z = a * b
        // based on the actual length of b. If b is "small" enough
        // we stick to the classic "grammar-school" method; for the
        // rest we switch to implementations with less complexity
        // albeit more overhead (which needs to pay off!).

        // NOTE: useful thresholds needs some "empirical" testing,
        // which are smaller in DEBUG mode for testing purpose.
        // Mutable for unit testing?
        enum int multiplyThreshold = 32;

        if (rightLength < multiplyThreshold)
        {
            // Multiplies the bits using the "grammar-school" method.
            // Envisioning the "rhombus" of a pen-and-paper calculation
            // should help getting the idea of these two loops...
            // The inner multiplication operations are safe, because
            // z_i+j + a_j * b_i + c <= 2(2^32 - 1) + (2^32 - 1)^2 =
            // = 2^64 - 1 (which perfectly matches with ulong!).

            for (size_t i = 0; i < rightLength; i++)
            {
                ulong carry = 0UL;
                for (size_t j = 0; j < leftLength; j++)
                {
                    const ulong digits = bits[i + j] + carry + cast(ulong)left[j] * right[i];
                    bits[i + j] = cast(uint)digits;
                    carry = digits >> 32;
                }
                bits[i + leftLength] = cast(uint)carry;
            }
        }
        else
        {
            // Based on the Toom-Cook multiplication we split left/right
            // into two smaller values, doing recursive multiplication.
            // The special form of this multiplication, where we
            // split both operands into two operands, is also known
            // as the Karatsuba algorithm...

            // https://en.wikipedia.org/wiki/Toom-Cook_multiplication
            // https://en.wikipedia.org/wiki/Karatsuba_algorithm

            // Say we want to compute z = a * b ...

            // ... we need to determine our new length (just the half)
            const n = rightLength >> 1;
            const n2 = n << 1;

            // ... split left like a = (a_1 << n) + a_0
            const(uint)* leftLow = left;
            const leftLowLength = n;
            const(uint)* leftHigh = left + n;
            const leftHighLength = leftLength - n;

            // ... split right like b = (b_1 << n) + b_0
            const(uint)* rightLow = right;
            const rightLowLength = n;
            const(uint)* rightHigh = right + n;
            const rightHighLength = rightLength - n;

            // ... prepare our result array (to reuse its memory)
            uint* bitsLow = bits;
            const bitsLowLength = n2;
            uint* bitsHigh = bits + n2;
            const bitsHighLength = bitsLength - n2;

            // ... compute z_0 = a_0 * b_0 (multiply again)
            multiply(leftLow, leftLowLength, rightLow, rightLowLength, bitsLow, bitsLowLength);

            // ... compute z_2 = a_1 * b_1 (multiply again)
            multiply(leftHigh, leftHighLength, rightHigh, rightHighLength, bitsHigh, bitsHighLength);

            const leftFoldLength = leftHighLength + 1;
            auto leftFoldMem = UIntTempArray(0);
            leftFoldMem.length = leftFoldLength;
            auto leftFold = leftFoldMem.ptr(0);

            const rightFoldLength = rightHighLength + 1;
            auto rightFoldMem = UIntTempArray(0);
            rightFoldMem.length = rightFoldLength;
            auto rightFold = rightFoldMem.ptr(0);

            const coreLength = leftFoldLength + rightFoldLength;
            auto coreMem = UIntTempArray(0);
            coreMem.length = coreLength;
            auto core = coreMem.ptr(0);

            // ... compute z_a = a_1 + a_0 (call it fold...)
            add(leftHigh, leftHighLength, leftLow, leftLowLength, leftFold, leftFoldLength);

            // ... compute z_b = b_1 + b_0 (call it fold...)
            add(rightHigh, rightHighLength, rightLow, rightLowLength, rightFold, rightFoldLength);

            // ... compute z_1 = z_a * z_b - z_0 - z_2
            multiply(leftFold, leftFoldLength, rightFold, rightFoldLength, core, coreLength);
            subtractCore(bitsHigh, bitsHighLength, bitsLow, bitsLowLength, core, coreLength);

            // ... and finally merge the result! :-)
            addSelf(&bits[n], bitsLength - n, core, coreLength);
        }
    }

    private static void subtractCore(scope const(uint)* left, const(size_t) leftLength,
        scope const(uint)* right, const(size_t) rightLength,
        uint* core, const(size_t) coreLength) pure @trusted
    in
    {
        assert(leftLength >= rightLength);
        assert(coreLength >= leftLength);
    }
    do
    {
        // Executes a special subtraction algorithm for the multiplication,
        // which needs to subtract two different values from a core value,
        // while core is always bigger than the sum of these values.

        // NOTE: we could do an ordinary subtraction of course, but we spare
        // one "run", if we do this computation within a single one...

        long carry = 0L;

        size_t i = 0;
        for (; i < rightLength; i++)
        {
            const long digit = (core[i] + carry) - left[i] - right[i];
            core[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; i < leftLength; i++)
        {
            const long digit = (core[i] + carry) - left[i];
            core[i] = cast(uint)digit;
            carry = digit >> 32;
        }
        for (; carry != 0 && i < coreLength; i++)
        {
            const long digit = core[i] + carry;
            core[i] = cast(uint)digit;
            carry = digit >> 32;
        }
    }

    static uint gcd(uint left, uint right) pure
    {
        // Executes the classic Euclidean algorithm.
        // https://en.wikipedia.org/wiki/Euclidean_algorithm

        while (right != 0)
        {
            const uint temp = left % right;
            left = right;
            right = temp;
        }

        return left;
    }

    static ulong gcd(ulong left, ulong right) pure
    {
        // Same as above, but for 64-bit values.

        while (right > 0xFFFFFFFF)
        {
            const ulong temp = left % right;
            left = right;
            right = temp;
        }

        if (right != 0)
            return gcd(cast(uint)right, cast(uint)(left % right));

        return left;
    }

    static uint gcd(scope const(uint)[] left, uint right) pure
    in
    {
        assert(left.length >= 1);
        assert(right != 0);
    }
    do
    {
        // A common divisor cannot be greater than right;
        // we compute the remainder and continue above...

        const uint temp = remainder(left, right);
        return gcd(right, temp);
    }

    static UIntTempArray gcd(scope const(uint)[] left, scope const(uint)[] right) pure
    in
    {
        assert(left.length >= 2);
        assert(right.length >= 2);
        assert(compare(left, right) >= 0);
    }
    do
    {
        auto leftBuffer = BitsBuffer(left.length, left);
        auto rightBuffer = BitsBuffer(right.length, right);
        gcd(leftBuffer, rightBuffer);
        return UIntTempArray(leftBuffer[]);
    }

    private static void gcd(ref BitsBuffer left, ref BitsBuffer right) pure
    in
    {
        assert(left.length >= 2);
        assert(right.length >= 2);
        assert(left.length >= right.length);
    }
    do
    {
        // Executes Lehmer's gcd algorithm, but uses the most
        // significant bits to work with 64-bit (not 32-bit) values.
        // Furthermore we're using an optimized version due to Jebelean.

        // http://cacr.uwaterloo.ca/hac/about/chap14.pdf (see 14.4.2)
        // ftp://ftp.risc.uni-linz.ac.at/pub/techreports/1992/92-69.ps.gz

        while (right.length > 2)
        {
            ulong x, y;
            extractDigits(left, right, x, y);

            uint a = 1U, b = 0U;
            uint c = 0U, d = 1U;
            int iteration = 0;

            // Lehmer's guessing
            while (y != 0)
            {
                ulong q, r, s, t;

                // Odd iteration
                q = x / y;

                if (q > 0xFFFFFFFF)
                    break;

                r = a + q * c;
                s = b + q * d;
                t = x - q * y;

                if (r > 0x7FFFFFFF || s > 0x7FFFFFFF)
                    break;
                if (t < s || t + r > y - c)
                    break;

                a = cast(uint)r;
                b = cast(uint)s;
                x = t;

                ++iteration;
                if (x == b)
                    break;

                // Even iteration
                q = y / x;

                if (q > 0xFFFFFFFF)
                    break;

                r = d + q * b;
                s = c + q * a;
                t = y - q * x;

                if (r > 0x7FFFFFFF || s > 0x7FFFFFFF)
                    break;
                if (t < s || t + r > x - b)
                    break;

                d = cast(uint)r;
                c = cast(uint)s;
                y = t;

                ++iteration;
                if (y == c)
                    break;
            }

            if (b == 0)
            {
                // Euclid's step
                left.reduce(right);

                swap(left, right);
            }
            else
            {
                // Lehmer's step
                lehmerCore(left, right, a, b, c, d);

                if (iteration % 2 == 1)
                {
                    // Ensure left is larger than right
                    swap(left, right);
                }
            }
        }

        if (right.length != 0)
        {
            // Euclid's step
            left.reduce(right);

            auto xBits = right[];
            auto yBits = left[];

            const ulong x = (cast(ulong)xBits[1] << 32) | xBits[0];
            const ulong y = (cast(ulong)yBits[1] << 32) | yBits[0];

            left.overwrite(gcd(x, y));
            right.overwrite(0);
        }
    }

    private static void extractDigits(ref BitsBuffer xBuffer, ref BitsBuffer yBuffer,
        out ulong x, out ulong y) pure
    in
    {
        assert(xBuffer.length >= 3);
        assert(yBuffer.length >= 3);
        assert(xBuffer.length >= yBuffer.length);
    }
    do
    {
        // Extracts the most significant bits of x and y,
        // but ensures the quotient x / y does not change!

        const xBits = xBuffer[];
        const xLength = xBuffer.length;
        const yBits = yBuffer[];
        const yLength = yBuffer.length;
        const ulong xh = xBits[xLength - 1];
        const ulong xm = xBits[xLength - 2];
        const ulong xl = xBits[xLength - 3];
        ulong yh, ym, yl;

        // arrange the bits
        switch (xLength - yLength)
        {
            case 0:
                yh = yBits[yLength - 1];
                ym = yBits[yLength - 2];
                yl = yBits[yLength - 3];
                break;

            case 1:
                yh = 0UL;
                ym = yBits[yLength - 1];
                yl = yBits[yLength - 2];
                break;

            case 2:
                yh = 0UL;
                ym = 0UL;
                yl = yBits[yLength - 1];
                break;

            default:
                yh = 0UL;
                ym = 0UL;
                yl = 0UL;
                break;
        }

        // Use all the bits but one, see [hac] 14.58 (ii)
        const z = leadingZeros(cast(uint)xh);

        x = ((xh << 32 + z) | (xm << z) | (xl >> 32 - z)) >> 1;
        y = ((yh << 32 + z) | (ym << z) | (yl >> 32 - z)) >> 1;

        assert(x >= y);
    }

    private static void lehmerCore(ref BitsBuffer xBuffer, ref BitsBuffer yBuffer,
        long a, long b, long c, long d) pure
    in
    {
        assert(xBuffer.length >= 1);
        assert(yBuffer.length >= 1);
        assert(xBuffer.length >= yBuffer.length);
        assert(a <= 0x7FFFFFFF && b <= 0x7FFFFFFF);
        assert(c <= 0x7FFFFFFF && d <= 0x7FFFFFFF);
    }
    do
    {
        // Executes the combined calculation of Lehmer's step.

        auto x = xBuffer[];
        auto y = yBuffer[];
        const length = yBuffer.length;
        long xCarry = 0L, yCarry = 0L;
        for (size_t i = 0; i < length; i++)
        {
            const long xDigit = a * x[i] - b * y[i] + xCarry;
            const long yDigit = d * y[i] - c * x[i] + yCarry;
            xCarry = xDigit >> 32;
            yCarry = yDigit >> 32;
            x[i] = cast(uint)xDigit;
            y[i] = cast(uint)yDigit;
        }

        xBuffer.refresh(length);
        yBuffer.refresh(length);
    }

    // Executes different exponentiation algorithms, which are
    // based on the classic square-and-multiply method.

    // https://en.wikipedia.org/wiki/Exponentiation_by_squaring

    static UIntTempArray pow(uint value, uint power) pure
    {
        // The basic pow method for a 32-bit integer.
        // To spare memory allocations we first roughly
        // estimate an upper bound for our buffers.

        const size = powBound(power, 1, 1);
        auto v = BitsBuffer(size, value);
        return powCore(power, v);
    }

    static UIntTempArray pow(scope const(uint)[] value, uint power) pure
    {
        // The basic pow method for a big integer.
        // To spare memory allocations we first roughly
        // estimate an upper bound for our buffers.

        const size = powBound(power, value.length, 1);
        auto v = BitsBuffer(size, value);
        return powCore(power, v);
    }

    private static UIntTempArray powCore(uint power, ref BitsBuffer value) pure
    {
        // Executes the basic pow algorithm.

        const size = value.size;
        auto temp = BitsBuffer(size, 0);
        auto result = BitsBuffer(size, 1);
        powCore(power, value, result, temp);
        return UIntTempArray(result[]);
    }

    private static size_t powBound(uint power, size_t valueLength, size_t resultLength) pure
    {
        // The basic pow algorithm, but instead of squaring
        // and multiplying we just sum up the lengths.

        while (power != 0)
        {
            // todo overflow checked resultLength & valueLength

            if ((power & 1) == 1)
                resultLength += valueLength;

            if (power != 1)
                valueLength += valueLength;

            power = power >> 1;
        }

        return resultLength;
    }

    private static void powCore(uint power, ref BitsBuffer value,
        ref BitsBuffer result, ref BitsBuffer temp) pure
    {
        // The basic pow algorithm using square-and-multiply.

        while (power != 0)
        {
            if ((power & 1) == 1)
                result.multiplySelf(value, temp);
            if (power != 1)
                value.squareSelf(temp);
            power = power >> 1;
        }
    }

    static uint pow(uint value, uint power, uint modulus) pure
    {
        // The 32-bit modulus pow method for a 32-bit integer
        // raised by a 32-bit integer...

        return powCore(power, modulus, value, 1);
    }

    static uint pow(scope const(uint)[] value, uint power, uint modulus) pure
    {
        // The 32-bit modulus pow method for a big integer
        // raised by a 32-bit integer...

        const uint v = remainder(value, modulus);
        return powCore(power, modulus, v, 1);
    }

    static uint pow(uint value, scope const(uint)[] power, uint modulus) pure
    {
        // The 32-bit modulus pow method for a 32-bit integer
        // raised by a big integer...

        return powCore(power, modulus, value, 1);
    }

    static uint pow(scope const(uint)[] value, scope const(uint)[] power, uint modulus) pure
    {
        // The 32-bit modulus pow method for a big integer
        // raised by a big integer...

        const uint v = remainder(value, modulus);
        return powCore(power, modulus, v, 1);
    }

    private static uint powCore(scope const(uint)[] power, uint modulus, ulong value, ulong result) pure
    {
        // The 32-bit modulus pow algorithm for all but
        // the last power limb using square-and-multiply.

        for (size_t i = 0; i < cast(ptrdiff_t)(power.length) - 1; i++)
        {
            uint p = power[i];
            for (size_t j = 0; j < 32; j++)
            {
                if ((p & 1) == 1)
                    result = (result * value) % modulus;
                value = (value * value) % modulus;
                p = p >> 1;
            }
        }

        return powCore(power[power.length - 1], modulus, value, result);
    }

    private static uint powCore(uint power, uint modulus, ulong value, ulong result) pure
    {
        // The 32-bit modulus pow algorithm for the last or
        // the only power limb using square-and-multiply.

        while (power != 0)
        {
            if ((power & 1) == 1)
                result = (result * value) % modulus;
            if (power != 1)
                value = (value * value) % modulus;
            power = power >> 1;
        }

        return cast(uint)(result % modulus);
    }

    static UIntTempArray pow(uint value, uint power, scope const(uint)[] modulus) pure
    {
        // The big modulus pow method for a 32-bit integer
        // raised by a 32-bit integer...

        const size = modulus.length + modulus.length;
        auto v = BitsBuffer(size, value);
        return powCore(power, modulus, v);
    }

    static UIntTempArray pow(scope const(uint)[] value, uint power, scope const(uint)[] modulus) pure
    {
        // The big modulus pow method for a big integer
        // raised by a 32-bit integer...

        const size = modulus.length + modulus.length;
        auto v = value.length > modulus.length
            ? BitsBuffer(size, remainder(value, modulus))
            : BitsBuffer(size, value);
        return powCore(power, modulus, v);
    }

    static UIntTempArray pow(uint value, scope const(uint)[] power, scope const(uint)[] modulus) pure
    {
        // The big modulus pow method for a 32-bit integer
        // raised by a big integer...

        const size = modulus.length + modulus.length;
        auto v = BitsBuffer(size, value);
        return powCore(power, modulus, v);
    }

    static UIntTempArray pow(scope const(uint)[] value, scope const(uint)[] power, scope const(uint)[] modulus) pure
    {
        // The big modulus pow method for a big integer
        // raised by a big integer...

        const size = modulus.length + modulus.length;
        auto v = value.length > modulus.length
            ? BitsBuffer(size, remainder(value, modulus))
            : BitsBuffer(size, value);
        return powCore(power, modulus, v);
    }

    // Mutable for unit testing...
    private static enum reducerThreshold = 32;

    private static UIntTempArray powCore(scope const(uint)[] power, scope const(uint)[] modulus, ref BitsBuffer value) pure
    {
        // Executes the big pow algorithm.

        const size = value.size;
        auto temp = BitsBuffer(size, 0);
        auto result = BitsBuffer(size, 1);

        if (modulus.length < reducerThreshold)
        {
            powCore(power, modulus, value, result, temp);
        }
        else
        {
            auto reducer = FastReducer(modulus);
            powCore(power, reducer, value, result, temp);
        }

        return UIntTempArray(result[]);
    }

    private static UIntTempArray powCore(uint power, scope const(uint)[] modulus, ref BitsBuffer value) pure
    {
        // Executes the big pow algorithm.

        const size = value.size;
        auto temp = BitsBuffer(size, 0);
        auto result = BitsBuffer(size, 1);

        if (modulus.length < reducerThreshold)
        {
            powCore(power, modulus, value, result, temp);
        }
        else
        {
            auto reducer = FastReducer(modulus);
            powCore(power, reducer, value, result, temp);
        }

        return UIntTempArray(result[]);
    }

    private static void powCore(scope const(uint)[] power, scope const(uint)[] modulus,
        ref BitsBuffer value, ref BitsBuffer result, ref BitsBuffer temp) pure
    {
        // The big modulus pow algorithm for all but
        // the last power limb using square-and-multiply.

        // NOTE: we're using an ordinary remainder here,
        // since the reducer overhead doesn't pay off.

        for (size_t i = 0; i < cast(ptrdiff_t)(power.length) - 1; i++)
        {
            uint p = power[i];
            for (size_t j = 0; j < 32; j++)
            {
                if ((p & 1) == 1)
                {
                    result.multiplySelf(value, temp);
                    result.reduce(modulus);
                }
                value.squareSelf(temp);
                value.reduce(modulus);
                p = p >> 1;
            }
        }

        powCore(power[power.length - 1], modulus, value, result, temp);
    }

    private static void powCore(uint power, scope const(uint)[] modulus,
        ref BitsBuffer value, ref BitsBuffer result, ref BitsBuffer temp) pure
    {
        // The big modulus pow algorithm for the last or
        // the only power limb using square-and-multiply.

        // NOTE: we're using an ordinary remainder here,
        // since the reducer overhead doesn't pay off.

        while (power != 0)
        {
            if ((power & 1) == 1)
            {
                result.multiplySelf(value, temp);
                result.reduce(modulus);
            }
            if (power != 1)
            {
                value.squareSelf(temp);
                value.reduce(modulus);
            }
            power = power >> 1;
        }
    }

    private static void powCore(scope const(uint)[] power, ref FastReducer reducer,
        ref BitsBuffer value, ref BitsBuffer result, ref BitsBuffer temp) pure
    {
        // The big modulus pow algorithm for all but
        // the last power limb using square-and-multiply.

        // NOTE: we're using a special reducer here,
        // since it's additional overhead does pay off.

        for (size_t i = 0; i < cast(ptrdiff_t)(power.length) - 1; i++)
        {
            uint p = power[i];
            for (size_t j = 0; j < 32; j++)
            {
                if ((p & 1) == 1)
                {
                    result.multiplySelf(value, temp);
                    result.reduce(reducer);
                }
                value.squareSelf(temp);
                value.reduce(reducer);
                p = p >> 1;
            }
        }

        powCore(power[power.length - 1], reducer, value, result, temp);
    }

    private static void powCore(uint power, ref FastReducer reducer,
        ref BitsBuffer value, ref BitsBuffer result, ref BitsBuffer temp) pure
    {
        // The big modulus pow algorithm for the last or
        // the only power limb using square-and-multiply.

        // NOTE: we're using a special reducer here,
        // since it's additional overhead does pay off.

        while (power != 0)
        {
            if ((power & 1) == 1)
            {
                result.multiplySelf(value, temp);
                result.reduce(reducer);
            }
            if (power != 1)
            {
                value.squareSelf(temp);
                value.reduce(reducer);
            }
            power = power >> 1;
        }
    }

    // Since we're reusing memory here, the actual length
    // of a given value may be less then the array's length
    package(pham.utl) static size_t actualLength(ref UIntTempArray value, size_t length) pure
    in
    {
        assert(length <= value.length);
    }
    do
    {
        while (length > 0 && value[length - 1] == 0)
            --length;
        return length;
    }

    package(pham.utl) static size_t actualLength(scope const(uint)[] value, size_t length) pure
    in
    {
        assert(length <= value.length);
    }
    do
    {
        while (length > 0 && value[length - 1] == 0)
            --length;
        return length;
    }
}
