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

module pham.cp.pad;

import std.algorithm.searching : all;

import pham.cp.cipher : CipherBuffer;
import pham.cp.random;

nothrow @safe:

enum CipherPaddingMode : ubyte
{
    none,
    ansiX923,        // 00 00 00 08 (zero + size)
    iso10126,        // 0A EB 02 08 (random + size) - W3C Padding
    pkcs1_5,
    pkcs5,           // 08 08 08 08 (size size)
    pkcs7,           // 08 08 08 08 (size size)
    zero,            // 00 00 00 00 (zero zero)
    orgSize,         // 00 00 00 00 + (00 00 00 99) (zero + Original-size)
}

enum CipherPaddingModeKind : ubyte
{
    none,
    zero,
    random,
    size,
    orgSize,
}

enum minPaddingBlockSize = 8;

struct CipherPaddingModeImpl(CipherPaddingModeKind fill, CipherPaddingModeKind suffix)
if (fill == CipherPaddingModeKind.zero || suffix != CipherPaddingModeKind.orgSize)
{
nothrow @safe:

public:
    enum noPadding = fill == CipherPaddingModeKind.none || suffix == CipherPaddingModeKind.none;

    static bool isValidBlockSize(const(size_t) blockSize) @nogc pure
    {
        return blockSize > 0 && blockSize <= 0xFF && (blockSize % minPaddingBlockSize == 0);
    }

    static bool isValidPaddedDataSize(size_t dataLength, const(size_t) blockSize) @nogc pure
    {
        return (dataLength >= blockSize) && (dataLength % blockSize == 0);
    }

    /*
     * Params:
     *  blockSize = Must be greater zero and less-equal to 255
     */
    ubyte[] pad(ubyte[] data, const(size_t) blockSize = minPaddingBlockSize)
    in
    {
        assert(isValidBlockSize(blockSize), "Invalid block size, which must be a multiple of 8 and less-equal to 255.");
        assert(data.length < uint.max - blockSize);
    }
    do
    {
        static if (noPadding)
        {
            return data;
        }
        else
        {
            auto result = CipherBuffer!ubyte(data);
            return pad(result, blockSize)[].dup;
        }
    }

    /*
     * Params:
     *  blockSize = Must be greater zero and less-equal to 255
     */
    ref CipherBuffer!ubyte pad(return ref CipherBuffer!ubyte data, const(size_t) blockSize = minPaddingBlockSize)
    in
    {
        assert(isValidBlockSize(blockSize), "Invalid block size, which must be a multiple of 8 and less-equal to 255.");
        assert(data.length < uint.max - blockSize);
    }
    do
    {
        static if (noPadding)
        {
            return data;
        }
        else static if (suffix != CipherPaddingModeKind.orgSize)
        {
            const paddingSize = blockSize - (data.length % blockSize);

            void fillBuffer(CipherPaddingModeKind type)
            {
                switch (type)
                {
                    case CipherPaddingModeKind.zero:
                        data.put(0);
                        break;

                    case CipherPaddingModeKind.size:
                        data.put(cast(ubyte)paddingSize);
                        break;

                    static if (fill == CipherPaddingModeKind.random)
                    {
                    case CipherPaddingModeKind.random:
                        data.put(rnd.next!ubyte(1, 255)); // Exclude 0
                        break;
                    }

                    default:
                        assert(0);
                }
            }

            auto fillCount = cast(ptrdiff_t)paddingSize - 1;
            while (fillCount--)
                fillBuffer(fill);
            fillBuffer(suffix);

            return data;
        }
        else
        {
            import pham.utl.bit_array : nativeToBytes;

            const orgDataLength = cast(uint)data.length;
            ptrdiff_t paddingSize = blockSize - (orgDataLength % blockSize);
            if (paddingSize < 4)
                paddingSize += blockSize;

            auto fillCount = paddingSize - 4;
            while (fillCount--)
                data.put(0);
            data.put(nativeToBytes!uint(orgDataLength));

            return data;
        }
    }

    static ubyte[] unpad(ubyte[] data, const(size_t) blockSize = minPaddingBlockSize) pure
    in
    {
        assert(isValidBlockSize(blockSize), "Invalid block size, which must be a multiple of 8 and less-equal to 255.");
    }
    do
    {
        static if (noPadding)
        {
            return data;
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return [];

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return [];

            // Invalid padding mode?
            if (!data[dataLength - paddingSize..$ - 1].all!((a) => (a == 0)))
                return [];

            return data[0..dataLength - paddingSize];
        }
        else static if (fill == CipherPaddingModeKind.random && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return [];

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return [];

            return data[0..dataLength - paddingSize];
        }
        else static if (fill == CipherPaddingModeKind.size && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return [];

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return [];

            // Invalid padding mode?
            if (!data[dataLength - paddingSize..dataLength - 1].all!((a) => (a == paddingSize)))
                return [];

            return data[0..dataLength - paddingSize];
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.zero)
        {
            size_t dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return [];

            // Invalid padding mode?
            if (data[dataLength - 1] != 0)
                return [];

            while (dataLength && data[dataLength - 1] == 0)
                dataLength--;

            return data[0..dataLength];
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.orgSize)
        {
            import pham.utl.bit_array : bytesToNative;

            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return [];

            const orgLen = bytesToNative!uint(data[dataLength - 4..dataLength]);

            // Invalid padding size?
            if (!(orgLen >= 0 && orgLen <= (dataLength - 4)))
                return [];

            // Invalid padding mode?
            for (size_t i = orgLen; i < dataLength - 4; i++)
            {
                if (data[i] != 0)
                    return [];
            }

            return data[0..orgLen];
        }
        else
        {
            static assert(0);
        }
    }

    static ref CipherBuffer!ubyte unpad(return ref CipherBuffer!ubyte data, const(size_t) blockSize = minPaddingBlockSize)
    in
    {
        assert(isValidBlockSize(blockSize), "Invalid block size, which must be a multiple of 8 and less-equal to 255.");
    }
    do
    {
        static if (noPadding)
        {
            return data;
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return data.clear();

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return data.clear();

            // Invalid padding mode?
            if (!data[dataLength - paddingSize..$ - 1].all!((a) => (a == 0)))
                return data.clear();

            return data.chopTail(paddingSize);
        }
        else static if (fill == CipherPaddingModeKind.random && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return data.clear();

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return data.clear();

            return data.chopTail(paddingSize);
        }
        else static if (fill == CipherPaddingModeKind.size && suffix == CipherPaddingModeKind.size)
        {
            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return data.clear();

            const paddingSize = data[dataLength - 1];

            // Invalid padding size?
            if (paddingSize == 0 || paddingSize > blockSize)
                return data.clear();

            // Invalid padding mode?
            if (!data[dataLength - paddingSize..dataLength - 1].all!((a) => (a == paddingSize)))
                return data.clear();

            return data.chopTail(paddingSize);
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.zero)
        {
            size_t dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return data.clear();

            // Invalid padding mode?
            if (data[dataLength - 1] != 0)
                return data.clear();

            while (dataLength && data[dataLength - 1] == 0)
                dataLength--;

            return data.chopTail(data.length - dataLength);
        }
        else static if (fill == CipherPaddingModeKind.zero && suffix == CipherPaddingModeKind.orgSize)
        {
            import pham.utl.bit_array : bytesToNative;

            const dataLength = data.length;
            if (!isValidPaddedDataSize(dataLength, blockSize))
                return data.clear();

            const orgLen = bytesToNative!uint(data[dataLength - 4..dataLength]);

            // Invalid padding size?
            if (!(orgLen >= 0 && orgLen <= (dataLength - 4)))
                return data.clear();

            // Invalid padding mode?
            for (size_t i = orgLen; i < dataLength - 4; i++)
            {
                if (data[i] != 0)
                    return data.clear();
            }

            return data.chopTail(dataLength - orgLen);
        }
        else
        {
            static assert(0);
        }
    }

private:
    static if (fill == CipherPaddingModeKind.random)
    CipherRandomGenerator rnd;
}

alias CipherPaddingNone = CipherPaddingModeImpl!(CipherPaddingModeKind.none, CipherPaddingModeKind.none);
alias CipherPaddingANSIX923 = CipherPaddingModeImpl!(CipherPaddingModeKind.zero, CipherPaddingModeKind.size);
alias CipherPaddingISO10126 = CipherPaddingModeImpl!(CipherPaddingModeKind.random, CipherPaddingModeKind.size);
alias CipherPaddingPKCS5 = CipherPaddingModeImpl!(CipherPaddingModeKind.size, CipherPaddingModeKind.size);
alias CipherPaddingPKCS7 = CipherPaddingModeImpl!(CipherPaddingModeKind.size, CipherPaddingModeKind.size);
alias CipherPaddingZero = CipherPaddingModeImpl!(CipherPaddingModeKind.zero, CipherPaddingModeKind.zero);
alias CipherPaddingOrgSize = CipherPaddingModeImpl!(CipherPaddingModeKind.zero, CipherPaddingModeKind.orgSize);

//https://crypto.stackexchange.com/questions/32557/rsa-pkcs1-v1-5-padding-output
struct CipherPaddingPKCS1_5
{
nothrow @safe:

public:
    enum padPKCS1_5Tag = 2;
    enum padPKCS1_5Length = 11;

    ubyte[] pad(ubyte[] data, const(size_t) blockSize)
    in
    {
        assert(data.length + padPKCS1_5Length < blockSize);
    }
    do
    {
        auto result = CipherBuffer!ubyte(data);
        return pad(result, blockSize)[].dup;
    }

    ref CipherBuffer!ubyte pad(return ref CipherBuffer!ubyte data, const(size_t) blockSize)
    in
    {
        assert(data.length + padPKCS1_5Length < blockSize);
    }
    do
    {
        // 0x00 + 0x02 + random-bytes + 0x00 + data
        // random-bytes count = keySize - (3 + data.length)
        tempBlock.clear();
        tempBlock.put(0);
        tempBlock.put(padPKCS1_5Tag);
        auto rndCount = blockSize - 3 - data.length;
        while (rndCount--)
            tempBlock.put(rnd.next!ubyte(1, ubyte.max)); // None zero value
        tempBlock.put(0);
        tempBlock.put(data[]);

        data.clear().put(tempBlock[]);
        return data;
    }

    static ubyte[] unpad(ubyte[] data, const(size_t) blockSize) pure
    {
        const dataLength = data.length;
        if (dataLength == 0)
            return [];

        // Check for min length && leading markers
        if (dataLength <= padPKCS1_5Length || data[0] != 0 || data[1] != padPKCS1_5Tag)
            return [];

        // Search for zero end marker
        size_t i = 2;
        while (i < dataLength && data[i] != 0)
            i++;

        return i >= dataLength || data[i++] != 0 ? [] : data[i..dataLength];
    }

    static ref CipherBuffer!ubyte unpad(return ref CipherBuffer!ubyte data, const(size_t) blockSize) pure
    {
        const dataLength = data.length;
        if (dataLength == 0)
            return data;

        // Check for min length && leading markers
        if (dataLength <= padPKCS1_5Length || data[0] != 0 || data[1] != padPKCS1_5Tag)
            return data.clear();

        // Search for zero end marker
        size_t i = 2;
        while (i < dataLength && data[i] != 0)
            i++;

        return i >= dataLength || data[i++] != 0 ? data.clear() : data.chopFront(i);
    }

private:
    CipherRandomGenerator rnd;
    CipherBuffer!ubyte tempBlock;
}

struct CipherPadding
{
nothrow @safe:

    static ubyte[] pad(ubyte[] data, const(CipherPaddingMode) paddingMode, const(size_t) blockSize = minPaddingBlockSize)
    {
        final switch (paddingMode)
        {
            case CipherPaddingMode.none:
                CipherPaddingNone nonePad;
                return nonePad.pad(data, blockSize);

            case CipherPaddingMode.ansiX923:
                CipherPaddingANSIX923 ansiX923Pad;
                return ansiX923Pad.pad(data, blockSize);

            case CipherPaddingMode.iso10126:
                CipherPaddingISO10126 iso10126Pad;
                return iso10126Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs1_5:
                CipherPaddingPKCS1_5 pkcs1_5Pad;
                return pkcs1_5Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs5:
                CipherPaddingPKCS5 pkcs5Pad;
                return pkcs5Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs7:
                CipherPaddingPKCS7 pkcs7Pad;
                return pkcs7Pad.pad(data, blockSize);

            case CipherPaddingMode.zero:
                CipherPaddingZero zeroPad;
                return zeroPad.pad(data, blockSize);

            case CipherPaddingMode.orgSize:
                CipherPaddingOrgSize orgSizePad;
                return orgSizePad.pad(data, blockSize);
        }
    }

    static ref CipherBuffer!ubyte pad(return ref CipherBuffer!ubyte data, const(CipherPaddingMode) paddingMode, const(size_t) blockSize = minPaddingBlockSize)
    {
        final switch (paddingMode)
        {
            case CipherPaddingMode.none:
                CipherPaddingNone nonePad;
                return nonePad.pad(data, blockSize);

            case CipherPaddingMode.ansiX923:
                CipherPaddingANSIX923 ansiX923Pad;
                return ansiX923Pad.pad(data, blockSize);

            case CipherPaddingMode.iso10126:
                CipherPaddingISO10126 iso10126Pad;
                return iso10126Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs1_5:
                CipherPaddingPKCS1_5 pkcs1_5Pad;
                return pkcs1_5Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs5:
                CipherPaddingPKCS5 pkcs5Pad;
                return pkcs5Pad.pad(data, blockSize);

            case CipherPaddingMode.pkcs7:
                CipherPaddingPKCS7 pkcs7Pad;
                return pkcs7Pad.pad(data, blockSize);

            case CipherPaddingMode.zero:
                CipherPaddingZero zeroPad;
                return zeroPad.pad(data, blockSize);

            case CipherPaddingMode.orgSize:
                CipherPaddingOrgSize orgSizePad;
                return orgSizePad.pad(data, blockSize);
        }
    }

    static ubyte[] unpad(ubyte[] data, const(CipherPaddingMode) paddingMode, const(size_t) blockSize = minPaddingBlockSize) pure
    {
        final switch (paddingMode)
        {
            case CipherPaddingMode.none:
                return CipherPaddingNone.unpad(data, blockSize);

            case CipherPaddingMode.ansiX923:
                return CipherPaddingANSIX923.unpad(data, blockSize);

            case CipherPaddingMode.iso10126:
                return CipherPaddingISO10126.unpad(data, blockSize);

            case CipherPaddingMode.pkcs1_5:
                return CipherPaddingPKCS1_5.unpad(data, blockSize);

            case CipherPaddingMode.pkcs5:
                return CipherPaddingPKCS5.unpad(data, blockSize);

            case CipherPaddingMode.pkcs7:
                return CipherPaddingPKCS7.unpad(data, blockSize);

            case CipherPaddingMode.zero:
                return CipherPaddingZero.unpad(data, blockSize);

            case CipherPaddingMode.orgSize:
                return CipherPaddingOrgSize.unpad(data, blockSize);
        }
    }

    static ref CipherBuffer!ubyte unpad(return ref CipherBuffer!ubyte data, const(CipherPaddingMode) paddingMode, const(size_t) blockSize = minPaddingBlockSize) pure
    {
        final switch (paddingMode)
        {
            case CipherPaddingMode.none:
                return CipherPaddingNone.unpad(data, blockSize);

            case CipherPaddingMode.ansiX923:
                return CipherPaddingANSIX923.unpad(data, blockSize);

            case CipherPaddingMode.iso10126:
                return CipherPaddingISO10126.unpad(data, blockSize);

            case CipherPaddingMode.pkcs1_5:
                return CipherPaddingPKCS1_5.unpad(data, blockSize);

            case CipherPaddingMode.pkcs5:
                return CipherPaddingPKCS5.unpad(data, blockSize);

            case CipherPaddingMode.pkcs7:
                return CipherPaddingPKCS7.unpad(data, blockSize);

            case CipherPaddingMode.zero:
                return CipherPaddingZero.unpad(data, blockSize);

            case CipherPaddingMode.orgSize:
                return CipherPaddingOrgSize.unpad(data, blockSize);
        }
    }
}


private:

unittest // CipherPadding
{
    import std.traits : EnumMembers;
    import pham.utl.test;
    traceUnitTest("unittest pham.cp.pad.CipherPadding");

    ubyte[] data1 = [1, 2, 3, 4, 5, 6, 7];
    ubyte[] data2 = [1, 2, 3, 4, 5, 6, 7, 8];
    ubyte[] data3 = [];

    ubyte[] padded, unpadded;
    foreach (p; EnumMembers!CipherPaddingMode)
    {
        const b = p == CipherPaddingMode.pkcs1_5 ? 128 : 8;

        padded = CipherPadding.pad(data1, p, b);
        unpadded = CipherPadding.unpad(padded, p, b);
        assert(unpadded == data1);

        padded = CipherPadding.pad(data2, p, b);
        unpadded = CipherPadding.unpad(padded, p, b);
        assert(unpadded == data2);

        padded = CipherPadding.pad(data3, p, b);
        unpadded = CipherPadding.unpad(padded, p, b);
        assert(unpadded == data3);
    }
}
