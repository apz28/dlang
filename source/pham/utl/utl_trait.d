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

module pham.utl.utl_trait;

import core.internal.traits : Unqual;

@safe:

template isTypeOf(T, checkingT)
{
    enum bool isTypeOf = is(T == checkingT) || is(Unqual!T == checkingT);
}


private:

unittest
{
    static struct S {}
    static class C {}
    
    static assert(isTypeOf!(int, int));
    static assert(isTypeOf!(const(int), int));
    static assert(isTypeOf!(immutable(int), int));
    static assert(isTypeOf!(shared int, int));
    
    static assert(isTypeOf!(S, S));
    static assert(isTypeOf!(const(S), S));
    static assert(isTypeOf!(immutable(S), S));
    static assert(isTypeOf!(shared S, S));
    
    static assert(isTypeOf!(C, C));
    static assert(isTypeOf!(const(C), C));
    static assert(isTypeOf!(immutable(C), C));
    static assert(isTypeOf!(shared C, C));
    
    static assert(isTypeOf!(string, string));
    static assert(isTypeOf!(const(string), string));
    static assert(isTypeOf!(immutable(string), string));
    static assert(isTypeOf!(shared string, string));    
}
