/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json;

public import pham.utl.utl_array_dictionary : Dictionary;
public import pham.json.json_codec;
public import pham.json.json_exception : JSONException;
public import pham.json.json_reader;
public import pham.json.json_type : defaultOptions, defaultPrettyOptions, defaultTab, optionsOf,
    JSONFloatLiteralType, JSONLiteral, JSONOptions, JSONType;
public import pham.json.json_writer;
public import pham.json.json_value;


private:

unittest
{
    import std.conv : text;

    static immutable string testJSON =
`[
    {
        "id": 1,
        "guid": "d25a9f69-a260-458f-bcac-0e1e59e05215",
        "isActive": true,
        "balance": "$3,733.60",
        "picture": "http://placehold.it/32x32",
        "age": 29,
        "eyeColor": "blue",
        "name": "Nell Ray",
        "gender": "female",
        "company": "FUTURITY",
        "email": "nellray@futurity.com",
        "phone": "+1 (823) 450-2959",
        "address": "761 Tompkins Avenue, Kansas, Marshall Islands, 8019",
        "about": "Incididunt anim in minim sint laborum consectetur sint adipisicing. Aliqua ullamco eiusmod aute quis voluptate reprehenderit pariatur ea eu sunt. Consectetur commodo Lorem laborum dolore eiusmod nisi dolor laborum. Magna mollit Lorem occaecat aliqua est consectetur officia quis cillum ea ea laborum. Aliqua et enim cillum dolor ad labore cillum quis non officia est pariatur incididunt mollit. Dolor elit aliquip ullamco esse magna commodo in.",
        "registered": "2014-01-30T21:32:18 +08:00",
        "latitude": 51.0,
        "longitude": -98.0,
        "tags": [
            "eu",
            "qui",
            "ad",
            "consequat",
            "occaecat",
            "ullamco",
            "est"
        ],
        "friends": [
            {
                "id": 0,
                "name": "Letha Ramsey"
            },
            {
                "id": 1,
                "name": "Lewis Cotton"
            },
            {
                "id": 2,
                "name": "Vega Hunt"
            }
        ],
        "greeting": "Hello, Nell Ray! You have 4 unread messages.",
        "favoriteFruit": "banana"
    },
    {
        "id": 2,
        "guid": "95deefa7-5468-4838-bbbc-c17e5d8afca7",
        "isActive": false,
        "balance": "$2,920.86",
        "picture": "http://placehold.it/32x32",
        "age": 36,
        "eyeColor": "green",
        "name": "Parks Wyatt",
        "gender": "male",
        "company": "NETPLODE",
        "email": "parkswyatt@netplode.com",
        "phone": "+1 (857) 514-3706",
        "address": "220 Canda Avenue, Wilsonia, Texas, 8807",
        "about": "Magna mollit incididunt ex occaecat mollit. Et dolore amet duis enim aute est dolor tempor sunt velit. Nisi anim reprehenderit eiusmod nostrud ut ut ea labore sint enim ut ut. Nisi laborum incididunt velit est irure nisi. Velit ut commodo ullamco magna ullamco fugiat cupidatat consequat enim. Aliqua reprehenderit ipsum quis sit duis consectetur nulla proident eu velit ex.",
        "registered": "2014-02-12T23:53:10 +08:00",
        "latitude": -57.0,
        "longitude": 157.0,
        "tags": [
            "pariatur",
            "laborum",
            "cillum",
            "aute",
            "excepteur",
            "deserunt",
            "cupidatat"
        ],
        "friends": [
            {
                "id": 0,
                "name": "Hart Gillespie"
            },
            {
                "id": 1,
                "name": "Donaldson Wise"
            },
            {
                "id": 2,
                "name": "Heidi Horton"
            }
        ],
        "greeting": "Hello, Parks Wyatt! You have 2 unread messages.",
        "favoriteFruit": "strawberry"
    }
]`;

    auto json = JSONValue.parse(testJSON);
    const jsonPretty = json.toString(optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.doNotEscapeSlash, JSONOptions.prettyString]));
    assert(jsonPretty == testJSON, text('\n', jsonPretty, '\n', testJSON, '\n', diffLoc(jsonPretty, testJSON)));
}
