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

module pham.db.db_builder;

import std.range.primitives : isOutputRange;
import std.traits : isIntegral, isFloatingPoint;

public import pham.utl.utl_array : Appender;
public import pham.var.var_variant : Variant, VariantType;
import pham.db.db_database : DbColumn, DbColumnList, DbDatabase, DbParameter, DbParameterList;
import pham.db.db_type : DbType, dbArrayElementOf, dbTypeOf, isDbTypeQuoted, uint32;

@safe:

enum LogicalOp : ubyte
{
    and,
    or,
}

static immutable string[LogicalOp.max + 1] logicalOps = [
    "and",
    "or"
    ];

enum ConditionOp : ubyte
{
    equal,
    greater,
    greaterEqual,
    lesser,
    lesserEqual,
    in_,
    like,
    isNull,
    isNotNull,
    not,
    notEqual,
    custom,
}

static immutable string[ConditionOp.max + 1] conditionOps = [
    "=",
    ">",
    ">=",
    "<",
    "<=",
    "in",
    "like",
    "is null",
    "is not null",
    "not",
    "<>",
    "?",
    ];

struct ConditionGroupBeginTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer) const nothrow
    if (isOutputRange!(Writer, char))
    {
        writer.put('(');
        return writer;
    }
}

struct ConditionGroupEndTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer) const nothrow
    if (isOutputRange!(Writer, char))
    {
        writer.put(')');
        return writer;
    }
}

struct ConditionLhsTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        name = null;
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer) const nothrow
    if (isOutputRange!(Writer, char))
    {
        writer.put(name);
        return writer;
    }

public:
    string name;
}

struct ConditionLogicalTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        logicalOp = LogicalOp.and;
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer) const nothrow
    if (isOutputRange!(Writer, char))
    {
        writer.put(logicalOps[logicalOp]);
        return writer;
    }

public:
    LogicalOp logicalOp;
}

struct ConditionOperatorTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        customOp = null;
        conditionOp = ConditionOp.equal;
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer, ref ConditionOp lastOperator) const nothrow
    if (isOutputRange!(Writer, char))
    {
        writer.put(conditionOp == ConditionOp.custom ? customOp : conditionOps[conditionOp]);
        lastOperator = conditionOp;
        return writer;
    }

public:
    string customOp;
    ConditionOp conditionOp;
}

struct ConditionRhsTerm
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        name = null;
        value.nullify();
        type = DbType.unknown;
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer, DbParameterList parameters, DbDatabase db,
        const(ConditionOp) lastOperator)
    if (isOutputRange!(Writer, char))
    {
        void writeNameOrValue(const(bool) canAsParam)
        {
            if (canAsParam && sqlAsParam())
            {
                if (name.length == 0)
                    name = DbParameter.generateName(cast(uint32)(parameters.length + 1));
                writer.put('@');
                writer.put(name);
                auto parameter = parameters.add(name, type);
                parameter.variant = value;
            }
            else
                writer.put(sqlValueString(db, lastOperator));
        }

        switch (lastOperator)
        {
            case ConditionOp.isNull:
            case ConditionOp.isNotNull:
                break;
            case ConditionOp.in_:
                writer.put('(');
                writeNameOrValue(false);
                writer.put(')');
                break;
            default:
                writeNameOrValue(true);
                break;
        }
        return writer;
    }

    pragma(inline, true)
    bool sqlAsParam() const nothrow
    {
        return name.length != 0;
    }

    string sqlValueString(DbDatabase db, const(ConditionOp) lastOperator) @trusted
    {
        const needQuoted = (lastOperator != ConditionOp.custom)
            && (isDbTypeQuoted(dbArrayElementOf(type)) || lastOperator == ConditionOp.like);

        const vt = value.variantType;
        if (vt == VariantType.staticArray || vt == VariantType.dynamicArray)
        {
            auto buffer = Appender!string(100);

            int appendElement(size_t i, Variant e, void* context) @trusted
            {
                if (i)
                    buffer.put(',');

                auto s = e.toString();
                //import std.stdio : writeln; debug writeln("e.toString()=", s);
                if (needQuoted)
                    db.quoteString(buffer, s);
                else
                    buffer.put(s);

                return 0;
            }

            value.each(&appendElement, null);
            return buffer.data;
        }
        else
        {
            auto s = value.toString();
            //import std.stdio : writeln; debug writeln("value.toString()=", s);
            return needQuoted ? db.quoteString(s) : s;
        }
    }

public:
    string name;
    Variant value;
    DbType type;
}

enum ConditionTermKind : ubyte
{
    logical,
    lhs,
    operator,
    rhs,
    groupBegin,
    groupEnd,
}

struct ConditionTerm
{
@safe:

public:
    this(LogicalOp logicalOp) nothrow @trusted
    {
        this.kind = ConditionTermKind.logical;
        this.logical = ConditionLogicalTerm(logicalOp);
    }

    this(string name) nothrow @trusted
    {
        this.kind = ConditionTermKind.lhs;
        this.lhs = ConditionLhsTerm(name);
    }

    this(ConditionOp conditionOp, string customOp) nothrow @trusted
    {
        this.kind = ConditionTermKind.operator;
        this.operator = ConditionOperatorTerm(customOp, conditionOp);
    }

    this(string name, Variant value, DbType type) nothrow @trusted
    {
        this.kind = ConditionTermKind.rhs;
        this.rhs = ConditionRhsTerm(name, value, type);
    }

    this(ConditionGroupBeginTerm begin) nothrow @trusted
    {
        this.kind = ConditionTermKind.groupBegin;
        this.groupBegin = begin;
    }

    this(ConditionGroupEndTerm end) nothrow @trusted
    {
        this.kind = ConditionTermKind.groupEnd;
        this.groupEnd = end;
    }

    ref typeof(this) clear() nothrow return @trusted
    {
        final switch (kind)
        {
            case ConditionTermKind.logical:
                logical.clear();
                break;
            case ConditionTermKind.lhs:
                lhs.clear();
                break;
            case ConditionTermKind.operator:
                operator.clear();
                break;
            case ConditionTermKind.rhs:
                rhs.clear();
                break;
            case ConditionTermKind.groupBegin:
                groupBegin.clear();
                break;
            case ConditionTermKind.groupEnd:
                groupEnd.clear();
                break;
        }
        return this;
    }

    ref Writer sql(Writer)(return ref Writer writer, DbParameterList parameters, DbDatabase db,
        ref ConditionOp lastOperator) @trusted
    {
        final switch (kind)
        {
            case ConditionTermKind.logical:
                return logical.sql(writer);
            case ConditionTermKind.lhs:
                return lhs.sql(writer);
            case ConditionTermKind.operator:
                return operator.sql(writer, lastOperator);
            case ConditionTermKind.rhs:
                return rhs.sql(writer, parameters, db, lastOperator);
            case ConditionTermKind.groupBegin:
                return groupBegin.sql(writer);
            case ConditionTermKind.groupEnd:
                return groupEnd.sql(writer);
        }
    }

public:
    union
    {
        ConditionLogicalTerm logical;
        ConditionLhsTerm lhs;
        ConditionOperatorTerm operator;
        ConditionRhsTerm rhs;
        ConditionGroupBeginTerm groupBegin;
        ConditionGroupEndTerm groupEnd;
    }
    ConditionTermKind kind;
}

struct ConditionBuilder
{
@safe:

public:
    ref typeof(this) clear() nothrow return
    {
        terms = [];
        rhsCount = 0;
        return this;
    }

    ref typeof(this) put(ConditionTerm term) nothrow return
    {
        terms ~= term;
        rhsCount += term.kind == ConditionTermKind.rhs;
        return this;
    }

    ref typeof(this) putLogical(LogicalOp logicalOp) nothrow return
    {
        return put(ConditionTerm(logicalOp));
    }

    // LHS
    ref typeof(this) putColumn(string name) nothrow return
    {
        return put(ConditionTerm(name));
    }

    ref typeof(this) putCondition(ConditionOp conditionOp,
        string customOp = null) nothrow return
    {
        return put(ConditionTerm(conditionOp, customOp));
    }

    // RHS
    ref typeof(this) putValue(string name, Variant value,
        DbType type = DbType.unknown) nothrow return
    {
        return put(ConditionTerm(name, value, type));
    }

    ref typeof(this) putValue(T)(string name, T value) nothrow return
    {
        //import std.stdio : writeln; debug writeln("T=", T.stringof);
        return put(ConditionTerm(name, Variant(value), dbTypeOf!T()));
    }

    ref typeof(this) putGroupBegin() nothrow return
    {
        return put(ConditionTerm(ConditionGroupBeginTerm.init));
    }

    ref typeof(this) putGroupEnd() nothrow return
    {
        return put(ConditionTerm(ConditionGroupEndTerm.init));
    }

    ref Writer sql(Writer)(return ref Writer writer, DbParameterList parameters, DbDatabase db)
    {
        bool needSpace;
        ConditionOp lastOperator;
        foreach (term; terms)
        {
            if (needSpace && term.kind != ConditionTermKind.groupEnd)
                writer.put(' ');
            term.sql(writer, parameters, db, lastOperator);
            needSpace = term.kind != ConditionTermKind.groupBegin;
        }
        return writer;
    }

public:
    ConditionTerm[] terms;
    size_t rhsCount;
}

ref Writer columnNameString(Writer, List)(return ref Writer writer, List names,
    const(char)[] separator = ",") nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    foreach(i, e; names)
    {
        if (i)
            writer.put(separator);
        writer.put(e.name.value);
    }
    return writer;
}

ref Writer parameterNameString(Writer, List)(return ref Writer writer, List names,
    const(char)[] separator = ",") nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    foreach(i, e; names)
    {
        if (i)
            writer.put(separator);
        writer.put('@');
        writer.put(e.name.value);
    }
    return writer;
}

ref Writer parameterConditionString(Writer, List)(return ref Writer writer, List names,
    const(bool) all = false,
    const(char)[] logicalOp = "and") nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    uint count;
    foreach(e; names)
    {
        if (all || e.isKey)
        {
            if (count)
            {
                writer.put(" ");
                writer.put(logicalOp);
                writer.put(" ");
            }
            writer.put(e.name.value);
            writer.put("=@");
            writer.put(e.name.value);
            count++;
        }
    }
    return writer;
}

ref Writer parameterUpdateString(Writer, List)(return ref Writer writer, List names,
    const(char)[] separator = ",") nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    static if (is(List : DbParameterList))
        alias DbItem = DbParameter;
    else
        alias DbItem = DbColumn;

    size_t[] keyIndexes;
    uint count;
    foreach(i, e; names)
    {
        if (e.isKey)
        {
            keyIndexes ~= i;
            continue;
        }

        if (count)
            writer.put(separator);
        writer.put(e.name.value);
        writer.put("=@");
        writer.put(e.name.value);
        count++;
    }

    if (keyIndexes.length)
    {
        DbItem[] keyItems;
        keyItems.reserve(keyIndexes.length);
        for (auto i = keyIndexes.length; i != 0; i--)
            keyItems ~= names.remove(keyIndexes[i - 1]);
        for (auto i = keyItems.length; i != 0; i--)
            names.put(keyItems[i - 1]);
    }

    return writer;
}


// Any below codes are private
private:

unittest // columnNameString
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32);
    parameters.add("colum2", DbType.int32);

    auto buffer = Appender!string(20);
    auto text = buffer.columnNameString(parameters)[];
    assert(text == "colum1,colum2", text);
}

unittest // parameterNameString
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32);
    parameters.add("colum2", DbType.int32);

    auto buffer = Appender!string(20);
    auto text = buffer.parameterNameString(parameters)[];
    assert(text == "@colum1,@colum2", text);
}

unittest // parameterConditionString
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32).isKey = true;
    parameters.add("colum2", DbType.int32);
    parameters.add("colum3", DbType.int32).isKey = true;

    auto buffer = Appender!string(50);
    auto text = buffer.parameterConditionString(parameters)[];
    assert(text == "colum1=@colum1 and colum3=@colum3", text);
}

unittest // parameterUpdateString
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32);
    parameters.add("colum2", DbType.int32);
    parameters.add("colum3", DbType.int32).isKey = true;

    auto buffer = Appender!string(20);
    auto text = buffer.parameterUpdateString(parameters)[];
    assert(text == "colum1=@colum1,colum2=@colum2", text);
}

unittest // ConditionBuilder
{
    import pham.db.db_fbdatabase : FbDatabase;

    auto db = new FbDatabase();
    auto params = new DbParameterList(db);
    auto sql = Appender!string(200);

    ConditionBuilder builder;
    builder.putColumn("F1")
            .putCondition(ConditionOp.equal)
            .putValue(null, "string1")
        .putLogical(LogicalOp.and)
            .putCondition(ConditionOp.not)
            .putColumn("F2")
            .putCondition(ConditionOp.greater)
            .putValue("P1", 2)
        .putLogical(LogicalOp.and)
        .putGroupBegin()
            .putColumn("F3")
            .putCondition(ConditionOp.greaterEqual)
            .putValue(null, 5.1)
        .putLogical(LogicalOp.or)
            .putColumn("F4")
            .putCondition(ConditionOp.lesser)
            .putValue("P2", 5)
        .putGroupEnd()
        .putLogical(LogicalOp.and)
        .putCondition(ConditionOp.not)
        .putGroupBegin()
            .putColumn("F5")
            .putCondition(ConditionOp.lesserEqual)
            .putValue(null, 100)
        .putLogical(LogicalOp.or)
            .putColumn("F5")
            .putCondition(ConditionOp.like)
            .putValue(null, "%foo")
        .putLogical(LogicalOp.or)
            .putColumn("F6")
            .putCondition(ConditionOp.in_)
            .putValue(null, [1, 3, 5])
        .putLogical(LogicalOp.or)
            .putColumn("F7")
            .putCondition(ConditionOp.isNull)
        .putLogical(LogicalOp.or)
            .putColumn("F8")
            .putCondition(ConditionOp.isNotNull)
        .putLogical(LogicalOp.or)
            .putColumn("F9")
            .putCondition(ConditionOp.notEqual)
            .putValue("P6", 6)
        .putGroupEnd()
        .sql(sql, params, db);

    //import std.stdio : writeln; debug writeln("sql=", sql.data);
    assert(sql.data == "F1 = 'string1' and not F2 > @P1 and (F3 >= 5.1 or F4 < @P2) and"
        ~ " not (F5 <= 100 or F5 like '%foo' or F6 in (1,3,5) or F7 is null or F8 is not null or F9 <> @P6)", sql.data);
}
