/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.auth_crypt3;

nothrow @safe:

/**************************************************************************
* Function:    crypt3
*
* Description: Clone of Unix crypt(3) function.
*
* Inputs:      char[] pw
*              array of 8 characters encryption key (user password)
*              char[2] salt
*              array of 2 characters salt used to modify the DES results.
*
* Returns:     string containing the salt concatenated
*              on to the encrypted results. Same as stored in passwd file.
**************************************************************************/
ubyte[] crypt3(const(char)[] pw, const(char)[2] salt)
in
{
    assert(pw.length > 0);
    assert(salt[0] != '\0');
    assert(salt[1] != '\0');
}
do
{
	byte[66] block;
    ubyte[16] iobuf;
    Crypt3Key crypt3Key;

    block[] = 0;

    /* break pw into 64 bits */
    {
        int i, pwi;
        for (i = 0, pwi = 0; i < 64 && pwi < pw.length; pwi++, i++)
        {
            byte c = cast(byte)pw[pwi];
            for (int j = 0; j < 7; j++, i++)
                block[i] = (c >> (6 - j)) & 01;
        }
    }

    /* set key based on pw */
    crypt3Key.setKey(block);

    block[] = 0;

    for (int i = 0; i < 2; i++)
    {
        /* store salt at beginning of results */
        byte c = cast(byte)salt[i];
        iobuf[i] = c;

        if (c > 'Z')
            c -= 6;

        if (c > '9')
            c -= 7;

        c -= '.';

        /* use salt to effect the E-bit selection */
        for (int j = 0; j < 6; j++)
        {
            if ((c >> j) & 01)
            {
                auto temp = crypt3Key.E[6 * i + j];
                crypt3Key.E[6 * i +j] = crypt3Key.E[6 * i + j + 24];
                crypt3Key.E[6 * i + j + 24] = temp;
            }
        }
    }

    /* call DES encryption 25 times using pw as key and initial data = 0 */
    for (int i = 0; i < 25; i++)
        crypt3Key.encrypt(block);

    /* format encrypted block for standard crypt(3) output */
    {
        int i = 0;
        for (; i < 11; i++)
        {
            byte c = 0;
            for (int j = 0; j < 6; j++)
            {
                c <<= 1;
                c |= block[6 * i + j];
            }

            c += '.';
            if (c > '9')
                c += 7;

            if (c > 'Z')
                c += 6;

            iobuf[i + 2] = c;
        }

        return iobuf[0..i + 2].dup;
    }
}


// Any below codes are private
private:


/* Initial permutation */
immutable byte[] IP = [
    58, 50, 42, 34, 26, 18, 10, 2,
    60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17,  9, 1,
    59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5,
    63, 55, 47, 39, 31, 23, 15, 7,
    ];

/* Final permutation, FP = IP^(-1) */
immutable byte[] FP = [
    40, 8, 48, 16, 56, 24, 64, 32,
    39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41,  9, 49, 17, 57, 25,
    ];

/**************************************************************************
* Permuted-choice 1 from the key bits to yield C and D.
* Note that bits 8,16... are left out:
* They are intended for a parity check.
**************************************************************************/
immutable byte[] PC1_C = [
    57, 49, 41, 33, 25, 17,  9,
     1, 58, 50, 42, 34, 26, 18,
    10,  2, 59, 51, 43, 35, 27,
    19, 11,  3, 60, 52, 44, 36,
    ];

immutable byte[] PC1_D = [
    63, 55, 47, 39, 31, 23, 15,
     7, 62, 54, 46, 38, 30, 22,
    14,  6, 61, 53, 45, 37, 29,
    21, 13,  5, 28, 20, 12,  4,
    ];

/* Sequence of shifts used for the key schedule. */
immutable byte[] shifts = [
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1
    ];

/**************************************************************************
* Permuted-choice 2, to pick out the bits from the CD array that generate
* the key schedule.
**************************************************************************/
immutable byte[] PC2_C = [
    14, 17, 11, 24,  1,  5,
     3, 28, 15,  6, 21, 10,
    23, 19, 12,  4, 26,  8,
    16,  7, 27, 20, 13,  2,
    ];

immutable byte[] PC2_D = [
    41, 52, 31, 37, 47, 55,
    30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53,
    46, 42, 50, 36, 29, 32,
    ];

/* The E bit-selection table. */
immutable byte[] e2 = [
    32,  1,  2,  3,  4,  5,
     4,  5,  6,  7,  8,  9,
     8,  9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21,
    20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29,
    28, 29, 30, 31, 32,  1,
    ];

/**************************************************************************
* The 8 selection functions. For some reason, they give a 0-origin
* index, unlike everything else.
**************************************************************************/
immutable byte[64][8] S = [
    [
        14,  4, 13,  1,  2, 15, 11,  8,  3, 10,  6, 12,  5,  9,  0,  7,
         0, 15,  7,  4, 14,  2, 13,  1, 10,  6, 12, 11,  9,  5,  3,  8,
         4,  1, 14,  8, 13,  6,  2, 11, 15, 12,  9,  7,  3, 10,  5,  0,
        15, 12,  8,  2,  4,  9,  1,  7,  5, 11,  3, 14, 10,  0,  6, 13
        ],
    [
        15,  1,  8, 14,  6, 11,  3,  4,  9,  7,  2, 13, 12,  0,  5, 10,
         3, 13,  4,  7, 15,  2,  8, 14, 12,  0,  1, 10,  6,  9, 11,  5,
         0, 14,  7, 11, 10,  4, 13,  1,  5,  8, 12,  6,  9,  3,  2, 15,
        13,  8, 10,  1,  3, 15,  4,  2, 11,  6,  7, 12,  0,  5, 14,  9
        ],
    [
        10,  0,  9, 14,  6,  3, 15,  5,  1, 13, 12,  7, 11,  4,  2,  8,
        13,  7,  0,  9,  3,  4,  6, 10,  2,  8,  5, 14, 12, 11, 15,  1,
        13,  6,  4,  9,  8, 15,  3,  0, 11,  1,  2, 12,  5, 10, 14,  7,
         1, 10, 13,  0,  6,  9,  8,  7,  4, 15, 14,  3, 11,  5,  2, 12
        ],
    [
         7, 13, 14,  3,  0,  6,  9, 10,  1,  2,  8,  5, 11, 12,  4, 15,
        13,  8, 11,  5,  6, 15,  0,  3,  4,  7,  2, 12,  1, 10, 14,  9,
        10,  6,  9,  0, 12, 11,  7, 13, 15,  1,  3, 14,  5,  2,  8,  4,
         3, 15,  0,  6, 10,  1, 13,  8,  9,  4,  5, 11, 12,  7,  2, 14
         ],
    [
         2, 12,  4,  1,  7, 10, 11,  6,  8,  5,  3, 15, 13,  0, 14,  9,
        14, 11,  2, 12,  4,  7, 13,  1,  5,  0, 15, 10,  3,  9,  8,  6,
         4,  2,  1, 11, 10, 13,  7,  8, 15,  9, 12,  5,  6,  3,  0, 14,
        11,  8, 12,  7,  1, 14,  2, 13,  6, 15,  0,  9, 10,  4,  5,  3
         ],
    [
        12,  1, 10, 15,  9,  2,  6,  8,  0, 13,  3,  4, 14,  7,  5, 11,
        10, 15,  4,  2,  7, 12,  9,  5,  6,  1, 13, 14,  0, 11,  3,  8,
         9, 14, 15,  5,  2,  8, 12,  3,  7,  0,  4, 10,  1, 13, 11,  6,
         4,  3,  2, 12,  9,  5, 15, 10, 11, 14,  1,  7,  6,  0,  8, 13
        ],
    [
         4, 11,  2, 14, 15,  0,  8, 13,  3, 12,  9,  7,  5, 10,  6,  1,
        13,  0, 11,  7,  4,  9,  1, 10, 14,  3,  5, 12,  2, 15,  8,  6,
         1,  4, 11, 13, 12,  3,  7, 14, 10, 15,  6,  8,  0,  5,  9,  2,
         6, 11, 13,  8,  1,  4, 10,  7,  9,  5,  0, 15, 14,  2,  3, 12
         ],
    [
        13,  2,  8,  4,  6, 15, 11,  1, 10,  9,  3, 14,  5,  0, 12,  7,
         1, 15, 13,  8, 10,  3,  7,  4, 12,  5,  6, 11,  0, 14,  9,  2,
         7, 11,  4,  1,  9, 12, 14,  2,  0,  6, 10, 13, 15,  3,  5,  8,
         2,  1, 14,  7,  4, 10,  8, 13, 15, 12,  9,  0,  3,  5,  6, 11
        ]
    ];

/**************************************************************************
* P is a permutation on the selected combination of the current L and key.
**************************************************************************/
immutable byte[] P = [
    16,  7, 20, 21,
    29, 12, 28, 17,
     1, 15, 23, 26,
     5, 18, 31, 10,
     2,  8, 24, 14,
    32, 27,  3,  9,
    19, 13, 30,  6,
    22, 11,  4, 25,
    ];

struct Crypt3Key
{
    /* The E bit-selection table. */
    byte[48] E;

    /* The key schedule. Generated from the key. */
    byte[48][16] KS;

    /* The C and D arrays used to calculate the key schedule. */
    byte[28] C, D;

    /* The combination of the key and the input, before selection. */
    byte[48] preS;

    /**************************************************************************
    * Function:    setKey
    *
    * Description: Set up the key schedule from the encryption key.
    *
    * Inputs:      char[66] key
    *              64 characters array. Each character represents a
    *              bit in the key.
    *
    * Returns:     none
    **************************************************************************/
    void setKey(const ref byte[66] key) nothrow
    {
        /**********************************************************************
        * First, generate C and D by permuting the key. The low order bit of
        * each 8-bit char is not used, so C and D are only 28 bits apiece.
        **********************************************************************/
        for (int i = 0; i < 28; i++)
        {
            C[i] = key[PC1_C[i] - 1];
            D[i] = key[PC1_D[i] - 1];
        }

        /**********************************************************************
        * To generate Ki, rotate C and D according to schedule and pick up a
        * permutation using PC2.
        **********************************************************************/
        for (int i = 0; i < 16; i++)
        {
            /* rotate */
            for (int k = 0; k < shifts[i]; k++)
            {
                auto temp = C[0];
                for (int j = 0; j < 28 - 1; j++)
                    C[j] = C[j+1];
                C[27] = temp;

                temp = D[0];
                for (int j = 0; j < 28 - 1; j++)
                    D[j] = D[j+1];
                D[27] = temp;
            }

            /* get Ki. Note C and D are concatenated */
            for (int j = 0; j < 24; j++)
            {
                KS[i][j] = C[PC2_C[j] - 1];
                KS[i][j + 24] = D[PC2_D[j] - 28 -1];
            }
        }

        /* load E with the initial E bit selections */
        E = e2;
    }

    /**************************************************************************
    * Function:    encrypt
    *
    * Description: Uses DES to encrypt a 64 bit block of data. Requires
    *              setKey to be invoked with the encryption key before it may
    *              be used. The results of the encryption are stored in block.
    *
    * Inputs:      byte[66] block
    *              64 bytes array. Each character represents a
    *              bit in the data block.
    *
    * Returns:     none
    **************************************************************************/
    void encrypt(ref byte[66] block) nothrow
    {
        byte[32] left, right, old, f; /* block in two halves */

        /* First, permute the bits in the input */
        {
            int j = 0;
            for (; j < 32; j++)
                left[j] = block[IP[j] - 1];

            for(; j < 64; j++)
                right[j - 32] = block[IP[j] - 1];
        }

        /* Perform an encryption operation 16 times. */
        for (int ii = 0; ii < 16; ii++)
        {
            auto i = ii;

            /* Save the right array, which will be the new left. */
            old = right;

            /******************************************************************
            * Expand right to 48 bits using the E selector and
            * exclusive-or with the current key bits.
            ******************************************************************/
            for (int j = 0; j < 48; j++)
                preS[j] = right[E[j] - 1] ^ KS[i][j];

            /******************************************************************
            * The pre-select bits are now considered in 8 groups of 6 bits ea.
            * The 8 selection functions map these 6-bit quantities into 4-bit
            * quantities and the results are permuted to make an f(R, K).
            * The indexing into the selection functions is peculiar;
            * it could be simplified by rewriting the tables.
            ******************************************************************/
            for (int j = 0; j < 8; j++)
            {
                int temp = 6 * j;
                int k = S[j][(preS[temp + 0] << 5) +
                    (preS[temp + 1] << 3) +
                    (preS[temp + 2] << 2) +
                    (preS[temp + 3] << 1) +
                    (preS[temp + 4] << 0) +
                    (preS[temp + 5] << 4)];

                temp = 4 * j;

                f[temp + 0] = (k >> 3) & 01;
                f[temp + 1] = (k >> 2) & 01;
                f[temp + 2] = (k >> 1) & 01;
                f[temp + 3] = (k >> 0) & 01;
            }

            /******************************************************************
            * The new right is left ^ f(R, K).
            * The f here has to be permuted first, though.
            ******************************************************************/
            for (int j = 0; j < 32; j++)
                right[j] = left[j] ^ f[P[j] - 1];

            /* Finally, the new left (the original right) is copied back. */
            left = old;
        }

        /* The output left and right are reversed. */
        for (int j = 0; j < 32; j++)
        {
            auto temp = left[j];
            left[j] = right[j];
            right[j] = temp;
        }

        /* The final output gets the inverse permutation of the very original. */
        for (int j = 0; j < 64; j++)
        {
            auto i = FP[j];
            if (i < 33)
                block[j] = left[FP[j] - 1];
            else
                block[j] = right[FP[j] - 33];
        }
    }
}

@safe unittest // crypt3
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.auth_crypt3.crypt3");

    const(char)[] e;

    e = cast(const(char)[])crypt3("test", "PQ");
    assert(e == "PQl1.p7BcJRuM", "PQl1.p7BcJRuM ? '" ~ e ~ "'");

    e = cast(const(char)[])crypt3("much longer password here", "xx");
    assert(e == "xxtHrOGVa3182", "xxtHrOGVa3182 ? '" ~ e ~ "'");

    e = cast(const(char)[])crypt3("testtest", "es");
    assert(e == "esDRYJnY4VaGM", "esDRYJnY4VaGM ? '" ~ e ~ "'");
}
