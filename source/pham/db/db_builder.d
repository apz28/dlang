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
import std.traits : isIntegral, isFloatingPoint, Unqual;

public import pham.utl.utl_array : Appender;
public import pham.var.var_variant : Variant, VariantType;
import pham.db.db_database : DbColumn, DbColumnList, DbDatabase, DbParameter, DbParameterList;
import pham.db.db_type : DbType, dbArrayElementOf, dbTypeOf, isDbTypeQuoted,
    int32, uint32;

@safe:

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
    "IN",
    "LIKE",
    "IS NULL",
    "IS NOT NULL",
    "NOT",
    "<>",
    "?",
    ];

enum LogicalOp : ubyte
{
    and,
    or,
}

static immutable string[LogicalOp.max + 1] logicalOps = [
    "AND",
    "OR"
    ];

enum OrderBySortedKind : ubyte
{
    def,
    asc,
    dsc,
}

static immutable string[OrderBySortedKind.max + 1] orderBySortedKinds = [
    null,  // No need to specify (default as asc)
    "ASC",
    "DESC"
    ];

enum StatementOp : ubyte
{
    select,
    insert,
    update,
    delete_,
}

static immutable string[StatementOp.max + 1] statementOps = [
    "SELECT",
    "INSERT",
    "UPDATE",
    "DELETE",
    ];

enum TableJoin : ubyte
{
    none,
    join,
    joinInner,
    joinLeft,
    joinRight,
    joinFull,
}

static immutable string[TableJoin.max + 1] tableJoins = [
    null,
    "JOIN",
    "INNER JOIN",
    "LEFT JOIN",
    "RIGHT JOIN",
    "FULL JOIN",
    ];

enum TermKind : ubyte
{
    groupBegin,
    groupEnd,
    logicalOp,
    column,
    conditionOp,
    value,
    parameterPlaceholder,
    table,
    orderByLiteral,
    orderBySortedKind,
    whereLiteral,
    limit,
    returningLiteral,
    statementOp,
    top,
    tableHint,
}

struct ColumnTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        //import std.stdio : writeln; debug writeln(__FUNCTION__, "(context.lastStatementOp=", context.lastStatementOp, ", context.lastSectionTerm=", context.lastSectionTerm, ")");

        scope (exit)
            context.sectionColumnCount++;

        switch (context.lastStatementOp)
        {
            default:
                return sqlCondition(writer, context);
            case StatementOp.insert:
                return sqlInsert(writer, context);
            case StatementOp.update:
                return context.lastSectionTerm == TermKind.table
                    ? sqlUpdate(writer, context)
                    : sqlCondition(writer, context);
        }
    }

private:
    ref Writer sqlCondition(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    {
        sqlSeparator(writer, context);

        if (aliasOrTable.length)
            writer.put(aliasOrTable).put('.');
        writer.put(name);
        if (alias_.length)
            writer.put(" as ").put(alias_);

        return writer;
    }

    ref Writer sqlInsert(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    {
        if (context.sectionColumnCount == 0)
            writer.put('(');
        else
            sqlSeparator(writer, context);

        if (aliasOrTable.length)
            writer.put(aliasOrTable).put('.');
        return writer.put(name);
    }

    ref Writer sqlUpdate(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    {
        //import std.stdio : writeln; debug writeln(__FUNCTION__, "(name=", name, ")");

        writer.put(context.sectionColumnCount == 0 ? " " : ", ");

        if (aliasOrTable.length)
            writer.put(aliasOrTable).put('.');
        return writer.put(name).put(" =");
    }

    void sqlSeparator(Writer)(ref Writer writer, ref SqlBuilderContext context) const nothrow
    {
        switch (context.lastTerm)
        {
            case TermKind.column:
            case TermKind.orderBySortedKind:
                writer.put(", ");
                break;
            case TermKind.groupBegin:
                break;
            default:
                if (context.lastTerm != ubyte.max)
                    writer.put(' ');
                break;
        }
    }

public:
    string aliasOrTable;
    string name;
    string alias_;
}

struct GroupBeginTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        return writer.put('(');
    }
}

struct GroupEndTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        return writer.put(')');
    }
}

struct LimitTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        // Can't have both TOP & LIMIT; TOP has higher priority + it's took place first
        auto limitClause = context.referredTopClause.length == 0
            ? context.db.limitClause(rows, offset)
            : null;
        return limitClause.length ? writer.put(' ').put(limitClause) : writer;
    }

public:
    int32 rows;
    uint32 offset;
}

struct LogicalOpTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        scope (exit)
            context.lastConditionOp = ubyte.max;
        
        return writer.put(' ').put(logicalOps[logicalOp]);
    }

public:
    LogicalOp logicalOp;
}

struct ConditionOpTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        scope (exit)
            context.lastConditionOp = conditionOp;

        return writer.put(' ').put(conditionOp == ConditionOp.custom ? customOp : conditionOps[conditionOp]);
    }

public:
    string customOp;
    ConditionOp conditionOp;
}

struct OrderByLiteralTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.sectionColumnCount = 0;
        context.lastSectionTerm = TermKind.orderByLiteral;

        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        return writer.put("ORDER BY");
    }
}

struct OrderBySortedKindTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        if (orderBySortedKinds[orderBySortedKind].length)
            writer.put(' ').put(orderBySortedKinds[orderBySortedKind]);
        return writer;
    }

public:
    OrderBySortedKind orderBySortedKind;
}

struct ParameterPlaceholderTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) nothrow
    if (isOutputRange!(Writer, char))
    {
        scope (exit)
            context.parameterCount++;

        if (name.length == 0)
            name = DbParameter.generateName(context.parameterCount + 1);

        return writer.put(" @").put(name);
    }

public:
    string name;
}

struct ReturningLiteralTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.sectionColumnCount = 0;
        context.lastSectionTerm = TermKind.returningLiteral;

        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        return writer.put("RETURNING");
    }
}

// select column_name ... from table_name [join table_name on ...] [where ...] [order by ...]
// insert into table_name(column_name, ...) values(...)
// update table_name set column_name=... [where ...]
// delete from table_name [where ...]
struct StatementOpTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.sectionColumnCount = 0;
        context.lastSectionTerm = TermKind.statementOp;
        context.referredTopClause = null;

        scope (exit)
            context.lastStatementOp = statementOp;

        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        writer.put(statementOps[statementOp]);

        return writer;
    }

public:
    StatementOp statementOp;
}

struct TableTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.sectionColumnCount = 0;
        context.lastSectionTerm = TermKind.table;

        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        if (join != TableJoin.none)
            writer.put(tableJoins[join]).put(' ');
        else
        {
            switch (context.lastStatementOp)
            {
                case StatementOp.select:
                case StatementOp.delete_:
                    writer.put("FROM ");
                    break;
                case StatementOp.insert:
                    writer.put("INTO ");
                    break;
                default:
                    break;
            }
        }

        writer.put(nameOrCommand);

        if (alias_.length)
            writer.put(' ').put(alias_);

        if (join != join.none)
            writer.put(" ON");
        else if (context.lastStatementOp == StatementOp.update)
            writer.put(" SET");

        return writer;
    }

public:
    string nameOrCommand;
    string alias_;
    TableJoin join;
}

struct TableHintTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        return context.db.tableHint.length
            ? writer.put(' ').put(hint)
            : writer;
    }

public:
    string hint;
}

struct TopTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.referredTopClause = context.db.topClause(rows);
        return context.referredTopClause.length
            ? writer.put(' ').put(context.referredTopClause)
            : writer;
    }

public:
    int32 rows;
}

struct ValueTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context)
    if (isOutputRange!(Writer, char))
    {
        //import std.stdio : writeln; debug writeln(__FUNCTION__, "(context.lastStatementOp=", context.lastStatementOp, ", context.lastSectionTerm=", context.lastSectionTerm, ")");

        scope (exit)
            context.valueCount++;

        switch (context.lastStatementOp)
        {
            default:
                return sqlCondition(writer, context);
            case StatementOp.insert:
                return sqlInsert(writer, context);
            case StatementOp.update:
                return context.lastSectionTerm == TermKind.table
                    ? sqlUpdate(writer, context)
                    : sqlCondition(writer, context);
        }
    }

private:
    ref Writer sqlCondition(Writer)(return ref Writer writer, ref SqlBuilderContext context)
    {
        switch (context.lastConditionOp)
        {
            case ConditionOp.isNull:
            case ConditionOp.isNotNull:
                return writer;
            case ConditionOp.in_:
                writer.put(" (");
                sqlNameOrValue(writer, context, false);
                return writer.put(')');
            default:
                return sqlNameOrValue(writer, context, true);
        }
    }

    ref Writer sqlInsert(Writer)(return ref Writer writer, ref SqlBuilderContext context)
    {
        if (context.sectionColumnCount == 0)
            writer.put(") VALUES(");
        else
            writer.put(",");
        return sqlNameOrValue(writer, context, true);
    }

    ref Writer sqlUpdate(Writer)(return ref Writer writer, ref SqlBuilderContext context)
    {
        //import std.stdio : writeln; debug writeln(__FUNCTION__, "(parameterName=", parameterName, ")");

        return sqlNameOrValue(writer, context, true);
    }

    ref Writer sqlNameOrValue(Writer)(return ref Writer writer, ref SqlBuilderContext context, const(bool) referAsParam)
    {
        if (parameterName.length != 0 || (!sqlLiteral && referAsParam))
        {
            scope (exit)
                context.parameterCount++;

            auto pn = parameterName.length != 0
                ? parameterName
                : DbParameter.generateName(context.parameterCount + 1);

            writer.put(" @").put(pn);
            auto parameter = context.parameters.add(pn, type);
            parameter.variant = value;
            return writer;
        }
        else
            return sqlValueString(writer, context);
    }

    ref Writer sqlValueString(Writer)(return ref Writer writer, ref SqlBuilderContext context) @trusted
    {
        const needQuoted = !sqlLiteral
            && (context.lastConditionOp != ConditionOp.custom)
            && (context.lastConditionOp == ConditionOp.like || isDbTypeQuoted(dbArrayElementOf(type)));

        const vt = value.variantType;
        if (vt == VariantType.staticArray || vt == VariantType.dynamicArray)
        {
            auto buffer = Appender!string(100);

            int appendElement(size_t i, Variant e, void*) @trusted
            {
                if (i)
                    buffer.put(", ");

                auto s = e.toString();
                //import std.stdio : writeln; debug writeln("e.toString()=", s);
                if (needQuoted)
                    context.db.quoteString(buffer, s);
                else
                    buffer.put(s);

                return 0;
            }

            value.each(&appendElement, null);
            return writer.put(buffer.data);
        }
        else
        {
            writer.put(' ');
            auto s = value.toString();
            //import std.stdio : writeln; debug writeln("value.toString()=", s);
            return needQuoted ? context.db.quoteString(writer, s) : writer.put(s);
        }
    }

public:
    string parameterName;
    Variant value;
    DbType type;
    bool sqlLiteral;
}

struct WhereLiteralTerm
{
@safe:

public:
    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) const nothrow
    if (isOutputRange!(Writer, char))
    {
        context.sectionColumnCount = 0;
        context.lastSectionTerm = TermKind.whereLiteral;

        if (context.lastTerm != ubyte.max)
            writer.put(' ');

        return writer.put("WHERE");
    }
}

struct SqlTerm
{
@safe:

public:
    this(LogicalOp logicalOp) nothrow @trusted
    {
        this.kind = TermKind.logicalOp;
        this.logicalOp = LogicalOpTerm(logicalOp);
    }

    this(string aliasOrTable, string columnName, string columnAlias) nothrow @trusted
    {
        this.kind = TermKind.column;
        this.column = ColumnTerm(aliasOrTable, columnName, columnAlias);
    }

    this(ConditionOp conditionOp, string customOp) nothrow @trusted
    {
        this.kind = TermKind.conditionOp;
        this.conditionOp = ConditionOpTerm(customOp, conditionOp);
    }

    this(string parameterName, Variant value, DbType type, bool sqlLiteral) nothrow @trusted
    {
        this.kind = TermKind.value;
        this.value = ValueTerm(parameterName, value, type, sqlLiteral);
    }

    this(GroupBeginTerm begin) nothrow @trusted
    {
        this.kind = TermKind.groupBegin;
        this.groupBegin = begin;
    }

    this(GroupEndTerm end) nothrow @trusted
    {
        this.kind = TermKind.groupEnd;
        this.groupEnd = end;
    }

    this(string tableNameOrCommand, string tableAlias, TableJoin tableJoin) nothrow @trusted
    {
        this.kind = TermKind.table;
        this.table = TableTerm(tableNameOrCommand, tableAlias, tableJoin);
    }

    this(OrderByLiteralTerm orderByLiteral) nothrow @trusted
    {
        this.kind = TermKind.orderByLiteral;
        this.orderByLiteral = orderByLiteral;
    }

    this(OrderBySortedKind orderBySortedKind) nothrow @trusted
    {
        this.kind = TermKind.orderBySortedKind;
        this.orderBySortedKind = OrderBySortedKindTerm(orderBySortedKind);
    }

    this(ParameterPlaceholderTerm parameterPlaceholder) nothrow @trusted
    {
        this.kind = TermKind.parameterPlaceholder;
        this.parameterPlaceholder = parameterPlaceholder;
    }

    this(WhereLiteralTerm whereLiteral) nothrow @trusted
    {
        this.kind = TermKind.whereLiteral;
        this.whereLiteral = whereLiteral;
    }

    this(int32 limitRows, uint32 limitOffset) nothrow @trusted
    {
        this.kind = TermKind.limit;
        this.limit = LimitTerm(limitRows, limitOffset);
    }

    this(ReturningLiteralTerm returningLiteral) nothrow @trusted
    {
        this.kind = TermKind.returningLiteral;
        this.returningLiteral = returningLiteral;
    }

    this(TopTerm top) nothrow @trusted
    {
        this.kind = TermKind.top;
        this.top = top;
    }

    this(StatementOp statementOp) nothrow @trusted
    {
        this.kind = TermKind.statementOp;
        this.statementOp = StatementOpTerm(statementOp);
    }

    this(TableHintTerm tableHint) nothrow @trusted
    {
        this.kind = TermKind.tableHint;
        this.tableHint = tableHint;
    }

    ref Writer sql(Writer)(return ref Writer writer, ref SqlBuilderContext context) @trusted
    {
        //import std.stdio : writeln; debug writeln(__FUNCTION__, "(kind=", kind, ")");

        scope (exit)
            context.lastTerm = kind;

        final switch (kind)
        {
            case TermKind.logicalOp:
                return logicalOp.sql(writer, context);
            case TermKind.column:
                return column.sql(writer, context);
            case TermKind.conditionOp:
                return conditionOp.sql(writer, context);
            case TermKind.value:
                return value.sql(writer, context);
            case TermKind.parameterPlaceholder:
                return parameterPlaceholder.sql(writer, context);
            case TermKind.groupBegin:
                return groupBegin.sql(writer, context);
            case TermKind.groupEnd:
                return groupEnd.sql(writer, context);
            case TermKind.table:
                return table.sql(writer, context);
            case TermKind.orderByLiteral:
                return orderByLiteral.sql(writer, context);
            case TermKind.orderBySortedKind:
                return orderBySortedKind.sql(writer, context);
            case TermKind.whereLiteral:
                return whereLiteral.sql(writer, context);
            case TermKind.limit:
                return limit.sql(writer, context);
            case TermKind.returningLiteral:
                return returningLiteral.sql(writer, context);
            case TermKind.statementOp:
                return statementOp.sql(writer, context);
            case TermKind.top:
                return top.sql(writer, context);
            case TermKind.tableHint:
                return tableHint.sql(writer, context);
        }
    }

public:
    private static size_t maxTermSize() nothrow @nogc pure
    {
        size_t result;
        static foreach (n; [
            ColumnTerm.sizeof, GroupBeginTerm.sizeof, GroupEndTerm.sizeof, LimitTerm.sizeof, LogicalOpTerm.sizeof, ConditionOpTerm.sizeof, 
            OrderByLiteralTerm.sizeof, OrderBySortedKindTerm.sizeof, ParameterPlaceholderTerm.sizeof, ReturningLiteralTerm.sizeof,
            StatementOpTerm.sizeof, TableTerm.sizeof, TableHintTerm.sizeof, TopTerm.sizeof, ValueTerm.sizeof, WhereLiteralTerm.sizeof])
        {
            if (result < n)
                result = n;
        }
        return result;
    }
    
    union
    {
        ubyte[maxTermSize] _zeroInitializer;
        ColumnTerm column;
        GroupBeginTerm groupBegin;
        GroupEndTerm groupEnd;
        LimitTerm limit;
        LogicalOpTerm logicalOp;
        ConditionOpTerm conditionOp;
        OrderByLiteralTerm orderByLiteral;
        OrderBySortedKindTerm orderBySortedKind;
        ParameterPlaceholderTerm parameterPlaceholder;
        ReturningLiteralTerm returningLiteral;
        StatementOpTerm statementOp;
        TableTerm table;
        TableHintTerm tableHint;
        TopTerm top;
        ValueTerm value;
        WhereLiteralTerm whereLiteral;
    }
    TermKind kind;
}

struct SqlBuilderContext
{
@safe:

public:
    this(DbDatabase db, DbParameterList parameters) nothrow
    {
        this.db = db;
        this.parameters = parameters;
        //this.sectionColumnCount = this.parameterCount = 0;
        //this.referredTopClause = null;
        this.lastConditionOp = this.lastStatementOp = this.lastTerm = this.lastSectionTerm = ubyte.max;
    }

public:
    DbDatabase db;
    DbParameterList parameters;
    string referredTopClause;
    uint sectionColumnCount;
    uint parameterCount;
    uint valueCount;
    ubyte lastConditionOp;
    ubyte lastSectionTerm;
    ubyte lastStatementOp;
    ubyte lastTerm;
}

struct SqlBuilder
{
@safe:

public:
    ref typeof(this) put(SqlTerm term) nothrow return
    {
        if (terms.length == 0 && terms.capacity == 0)
            terms.reserve(100);
            
        terms ~= term;
        return this;
    }

    ref typeof(this) putLogical(LogicalOp logicalOp) nothrow return
    {
        return put(SqlTerm(logicalOp));
    }

    ref typeof(this) putColumn(string columnName) nothrow return
    {
        return putColumn(null, columnName);
    }

    ref typeof(this) putColumn(string[] columnNames) nothrow return
    {
        foreach (columnName; columnNames)
            putColumn(null, columnName);
        return this;
    }

    ref typeof(this) putColumn(string aliasOrTable, string columnName) nothrow return
    {
        return put(SqlTerm(aliasOrTable, columnName, null));
    }

    ref typeof(this) putColumn(string aliasOrTable, string[] columnNames) nothrow return
    {
        foreach (columnName; columnNames)
            putColumn(aliasOrTable, columnName);
        return this;
    }

    ref typeof(this) putColumnAs(string columnName, string columnAlias) nothrow return
    {
        return putColumnAs(null, columnName, columnAlias);
    }

    ref typeof(this) putColumnAs(string aliasOrTable, string columnName, string columnAlias) nothrow return
    {
        return put(SqlTerm(aliasOrTable, columnName, columnAlias));
    }

    ref typeof(this) putCondition(ConditionOp conditionOp,
        string customOp = null) nothrow return
    {
        return put(SqlTerm(conditionOp, customOp));
    }

    ref typeof(this) putGroupBegin() nothrow return
    {
        return put(SqlTerm(GroupBeginTerm.init));
    }

    ref typeof(this) putGroupEnd() nothrow return
    {
        return put(SqlTerm(GroupEndTerm.init));
    }

    ref typeof(this) putLimit(int32 limitRows, uint32 limitOffset = 0) nothrow return
    {
        return put(SqlTerm(limitRows, limitOffset));
    }

    ref typeof(this) putLimitIf(bool ifTrue, int32 limitRows, uint32 limitOffset = 0) nothrow return
    {
        return ifTrue ? put(SqlTerm(limitRows, limitOffset)) : this;
    }

    ref typeof(this) putOrderByLiteral() nothrow return
    {
        return put(SqlTerm(OrderByLiteralTerm.init));
    }

    ref typeof(this) putOrderBySortedKind(OrderBySortedKind orderBySortedKind) nothrow return
    {
        return put(SqlTerm(orderBySortedKind));
    }

    ref typeof(this) putParameterPlaceholder(string parameterName) nothrow return
    {
        return put(SqlTerm(ParameterPlaceholderTerm(parameterName)));
    }

    ref typeof(this) putReturningLiteral() nothrow return
    {
        return put(SqlTerm(ReturningLiteralTerm.init));
    }

    ref typeof(this) putStatementOp(StatementOp statementOp) nothrow return
    {
        return put(SqlTerm(statementOp));
    }

    ref typeof(this) putTable(string tableNameOrCommand,
        string tableAlias = null,
        TableJoin tableJoin = TableJoin.none) nothrow return
    {
        return put(SqlTerm(tableNameOrCommand, tableAlias, tableJoin));
    }

    ref typeof(this) putTableHint(string hint) nothrow return
    {
        return put(SqlTerm(TableHintTerm(hint)));
    }

    ref typeof(this) putTop(int32 limitRows) nothrow return
    {
        return put(SqlTerm(TopTerm(limitRows)));
    }

    ref typeof(this) putTopIf(bool ifTrue, int32 limitRows) nothrow return
    {
        return ifTrue ? put(SqlTerm(TopTerm(limitRows))) : this;
    }

    ref typeof(this) putValue(string parameterName, Variant value,
        DbType type = DbType.unknown) nothrow return
    {
        return put(SqlTerm(parameterName, value, type, false));
    }

    ref typeof(this) putValue(T)(string parameterName, T value) nothrow return
    if (!is(Unqual!T == Variant))
    {
        return put(SqlTerm(parameterName, Variant(value), dbTypeOf!T(), false));
    }

    ref typeof(this) putValueLiteral(string value) nothrow return
    {
        return put(SqlTerm(null, Variant(value), DbType.unknown, true));
    }

    ref typeof(this) putWhereCondition(SqlBuilder conditions) nothrow return
    {
        if (conditions.terms.length == 0)
            return this;

        const isWhereLiteral = conditions.terms[0].kind == TermKind.whereLiteral;

        if (isWhereLiteral && conditions.terms.length == 1)
            return this;

        if (!isWhereLiteral)
            putWhereLiteral();
            
        terms ~= conditions.terms;
        return this;
    }

    ref typeof(this) putWhereLiteral() nothrow return
    {
        return put(SqlTerm(WhereLiteralTerm.init));
    }

    ref typeof(this) reserve(const(size_t) capacity) nothrow return
    {
        if (terms.length < capacity)
            terms.reserve(capacity);
        return this;
    }
    
    ref Writer sql(Writer)(return ref Writer writer, DbDatabase db, DbParameterList parameters)
    {
        auto context = SqlBuilderContext(db, parameters);

        foreach (ref term; terms)
            term.sql(writer, context);

        return context.lastStatementOp == StatementOp.insert
            ? sqlInsert(writer, context)
            : writer;
    }

private:
    ref Writer sqlInsert(Writer)(return ref Writer writer, ref SqlBuilderContext context) nothrow @trusted
    {
        if (context.valueCount == 0)
            sqlInsertValues(writer, context);

        return writer.put(')');
    }

    ref Writer sqlInsertValues(Writer)(return ref Writer writer, ref SqlBuilderContext context) nothrow @trusted
    {
        const populateParameters = context.parameters.length == 0;
        auto i = 0;
        writer.put(") VALUES(");
        foreach (ref term; terms)
        {
            if (term.kind != TermKind.column)
                continue;

            if (i)
                writer.put(", ");

            auto pn = term.column.name;
            writer.put('@').put(pn);

            if (populateParameters)
                context.parameters.add(pn, DbType.unknown);

            i++;
        }
        
        return writer;
    }
    
public:
    SqlTerm[] terms;
}

ref Writer columnNameString(Writer, List)(return ref Writer writer, List names,
    const(char)[] separator = ", ") nothrow
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

ref SqlBuilder columnNameString(List)(return ref SqlBuilder writer, List names) nothrow
if (is(List : DbParameterList) || is(List : DbColumnList))
{
    foreach(e; names)
        writer.putColumn(e.name.value);
    return writer;
}

ref Writer parameterNameString(Writer, List)(return ref Writer writer, List names) nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    foreach(i, e; names)
    {
        if (i)
            writer.put(", ");
        writer.put('@');
        writer.put(e.name.value);
    }
    return writer;
}

ref Writer parameterConditionString(Writer, List)(return ref Writer writer, List names,
    const(bool) all = false,
    const(LogicalOp) logicalOp = LogicalOp.and) nothrow
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
                writer.put(logicalOps[logicalOp]);
                writer.put(" ");
            }
            writer.put(e.name.value);
            writer.put(" = @");
            writer.put(e.name.value);
            count++;
        }
    }
    return writer;
}

ref SqlBuilder parameterConditionString(List)(return ref SqlBuilder writer, List names,
    const(bool) all = false,
    const(LogicalOp) logicalOp = LogicalOp.and) nothrow
if (is(List : DbParameterList) || is(List : DbColumnList))
{
    uint count;
    foreach(e; names)
    {
        if (all || e.isKey)
        {
            if (count)
                writer.putLogical(logicalOp);

            writer.putColumn(e.name.value)
                .putCondition(ConditionOp.equal)
                .putParameterPlaceholder(e.name.value);

            count++;
        }
    }
    return writer;
}

ref SqlBuilder parameterConditionStringIf(List)(return ref SqlBuilder writer, List names,
    const(bool) all = false,
    const(LogicalOp) logicalOp = LogicalOp.and) nothrow
if (is(List : DbParameterList) || is(List : DbColumnList))
{
    if (names is null || names.length == 0)
        return writer;

    uint count;
    foreach(e; names)
    {
        if (all || e.isKey)
        {
            if (count == 0)
                writer.putWhereLiteral();
            else
                writer.putLogical(logicalOp);

            writer.putColumn(e.name.value)
                .putCondition(ConditionOp.equal)
                .putParameterPlaceholder(e.name.value);

            count++;
        }
    }
    return writer;
}

ref Writer parameterUpdateColumn(Writer, List)(return ref Writer writer, List names) nothrow
if (isOutputRange!(Writer, char) && (is(List : DbParameterList) || is(List : DbColumnList)))
{
    uint count;
    foreach(i, e; names)
    {
        if (e.isKey)
            continue;

        if (count)
            writer.put(", ");
        writer.put(e.name.value);
        writer.put(" = @");
        writer.put(e.name.value);
        count++;
    }
    return writer;
}

ref SqlBuilder parameterUpdateColumn(List)(return ref SqlBuilder writer, List names) nothrow
if (is(List : DbParameterList) || is(List : DbColumnList))
{
    foreach(e; names)
    {
        if (e.isKey)
            continue;

        writer.putColumn(e.name.value)
            .putParameterPlaceholder(e.name.value);
    }
    return writer;
}

List moveBackKeys(List)(List names) nothrow
if (is(List : DbParameterList) || is(List : DbColumnList))
{
    static if (is(List : DbParameterList))
        alias DbItem = DbParameter;
    else
        alias DbItem = DbColumn;

    size_t[] keyIndexes;
    bool needMove; // Track if all keys are already at the end
    foreach(i, e; names)
    {
        if (e.isKey)
            keyIndexes ~= i;
        else if (keyIndexes.length)
            needMove = true;
    }

    if (needMove && keyIndexes.length)
    {
        DbItem[] keyItems;
        keyItems.reserve(keyIndexes.length);
        for (auto i = keyIndexes.length; i != 0; i--)
            keyItems ~= names.remove(keyIndexes[i - 1]);
        for (auto i = keyItems.length; i != 0; i--)
            names.put(keyItems[i - 1]);
    }

    return names;
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
    assert(text == "colum1, colum2", text);
}

unittest // parameterNameString
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32);
    parameters.add("colum2", DbType.int32);

    auto buffer = Appender!string(20);
    auto text = buffer.parameterNameString(parameters)[];
    assert(text == "@colum1, @colum2", text);
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
    assert(text == "colum1 = @colum1 AND colum3 = @colum3", text);
}

unittest // parameterUpdateColumn
{
    import pham.utl.utl_array : Appender;

    auto parameters = new DbParameterList(null);
    parameters.add("colum1", DbType.int32);
    parameters.add("colum2", DbType.int32);
    parameters.add("colum3", DbType.int32).isKey = true;

    auto buffer = Appender!string(20);
    auto text = buffer.parameterUpdateColumn(parameters)[];
    assert(text == "colum1 = @colum1, colum2 = @colum2", text);
}

unittest // SqlBuilder
{
    import pham.db.db_fbdatabase : FbDatabase;

    auto db = new FbDatabase();

    { // Condition
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
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
            .sql(sql, db, params);

        //import std.stdio : writeln; debug writeln("sql=", sql.data);
        assert(sql.data == "F1 = @_param1 AND NOT F2 > @P1 AND (F3 >= @_param3 OR F4 < @P2)"
            ~ " AND NOT (F5 <= @_param5 OR F5 LIKE @_param6 OR F6 IN (1, 3, 5) OR F7 IS NULL"
            ~ " OR F8 IS NOT NULL OR F9 <> @P6)"
            , sql.data);
        assert(params.length == 7);
        assert(params[0].variant == "string1");
        assert(params.get("_param1").variant == "string1");
        assert(params[1].variant == 2);
        assert(params.get("P1").variant == 2);
        assert(params[2].variant == 5.1);
        assert(params.get("_param3").variant == 5.1);
        assert(params[3].variant == 5);
        assert(params.get("P2").variant == 5);
        assert(params[4].variant == 100);
        assert(params.get("_param5").variant == 100);
        assert(params[5].variant == "%foo");
        assert(params.get("_param6").variant == "%foo");
        assert(params[6].variant == 6);
        assert(params.get("P6").variant == 6);
    }

    { // Select
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
        builder.putStatementOp(StatementOp.select)
                .putColumn("c1")
                .putColumn("t", "c2")
                .putColumnAs("c3", "x")
                .putColumnAs("t", "c4", "y")
                .putColumn(["c4", "c5"])
                .putColumn("t", ["c6", "c7"])
            .putTable("tbl", "t")
            .putTable("jtbl", "j", TableJoin.join)
                .putColumn("j", "cjfrom")
                .putCondition(ConditionOp.equal)
                .putColumn("t", "cjto")
            .putWhereLiteral()
                .putColumn("cw1")
                .putCondition(ConditionOp.equal)
                .putValue(null, "string1")
            .putOrderByLiteral()
                .putColumn("co1")
                .putOrderBySortedKind(OrderBySortedKind.dsc)
                .putColumn("t", "co2")
            .putLimit(1, 2)
            .sql(sql, db, params);
        //import std.stdio : writeln; debug writeln("sql=", sql.data);
        assert(sql.data == "SELECT c1, t.c2, c3 as x, t.c4 as y, c4, c5, t.c6, t.c7"
            ~ " FROM tbl t"
            ~ " JOIN jtbl j ON j.cjfrom = t.cjto"
            ~ " WHERE cw1 = @_param1"
            ~ " ORDER BY co1 DESC, t.co2"
            ~ " ROWS 3 TO 3" // Database specific
            , sql.data);
        assert(params.length == 1);
        assert(params[0].variant == "string1");
        assert(params.get("_param1").variant == "string1");
    }

    { // Insert
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
        builder.putStatementOp(StatementOp.insert)
            .putTable("tbl")
                .putColumn("c1")
                .putColumn("c2")
            .sql(sql, db, params);
        assert(sql.data == "INSERT INTO tbl(c1, c2) VALUES(@c1, @c2)", sql.data);
        assert(params.length == 2);
        assert(params.exist("c1"));
        assert(params.exist("c2"));
    }

    { // Update
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
        builder.putStatementOp(StatementOp.update)
            .putTable("tbl")
                .putColumn("c1")
                .putValue("c1", 100)
                .putColumn("c2")
                .putValue("c2", 101)
            .putWhereLiteral()
                .putColumn("cw1")
                .putCondition(ConditionOp.equal)
                .putValue("cw1", "string1")
                .putLogical(LogicalOp.and)
                .putColumn("cw2")
                .putCondition(ConditionOp.greater)
                .putValue("cw2", 2)
            .sql(sql, db, params);
        assert(sql.data == "UPDATE tbl SET c1 = @c1, c2 = @c2 WHERE cw1 = @cw1 AND cw2 > @cw2", sql.data);
        assert(params.length == 4);
        assert(params.get("c1").variant == 100);
        assert(params.get("c2").variant == 101);
        assert(params.get("cw1").variant == "string1");
        assert(params.get("cw2").variant == 2);
    }

    { // Delete
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
        builder.putStatementOp(StatementOp.delete_)
            .putTable("tbl")
            .putWhereLiteral()
                .putColumn("cw1")
                .putCondition(ConditionOp.equal)
                .putValue("cw1", "string1")
                .putLogical(LogicalOp.and)
                .putColumn("cw2")
                .putCondition(ConditionOp.greater)
                .putValue("cw2", 2)
            .sql(sql, db, params);
        assert(sql.data == "DELETE FROM tbl WHERE cw1 = @cw1 AND cw2 > @cw2", sql.data);
        assert(params.length == 2);
        assert(params.get("cw1").variant == "string1");
        assert(params.get("cw2").variant == 2);
    }

    { // Delete+putValueLiteral
        auto params = new DbParameterList(db);
        auto sql = Appender!string(200);
        SqlBuilder builder;
        builder.putStatementOp(StatementOp.delete_)
            .putTable("tbl")
            .putWhereLiteral()
                .putColumn("cw1")
                .putCondition(ConditionOp.equal)
                .putValueLiteral("CURRENT_TIMESTAMP(2)")
                .putLogical(LogicalOp.and)
                .putColumn("cw2")
                .putCondition(ConditionOp.greater)
                .putValueLiteral("NOW")
            .sql(sql, db, params);
        assert(sql.data == "DELETE FROM tbl WHERE cw1 = CURRENT_TIMESTAMP(2) AND cw2 > NOW", sql.data);
        assert(params.length == 0);
    }
}
