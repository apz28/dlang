/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.ini_file;

import std.file : exists;
import std.format : format;
import std.range.primitives : ElementType, isInputRange, isOutputRange;
import std.stdio : File;
import std.traits : hasUDA, isArray, isBasicType, isSomeString;
import std.typecons : Flag, No, Yes;
import std.uni : sicmp;

import pham.utl.array : removeAt;
import pham.utl.delegate_list;

enum IniFileOpenMode : byte
{
    read,
    write,
    readWrite
}

enum IniFileLineKind : byte
{
    empty,
    comment,
    section,
    nameValue,
    notSection,
    noValue,
    invalidSection,
    invalidName
}

struct IniFileMessage
{
nothrow @safe:

    static immutable eUndefinedSection = "Section is not defined.";
    static immutable eInvalidKeyName = "Malform key name";
    static immutable eInvalidSectionName = "Invalid section name: %s.";
}

class IniFileException : Exception
{
    this(string message, Exception next = null)
    {
        super(message, next);
    }
}

struct Ini
{
nothrow @safe:

public:
	static Ini opCall(string msg)
    {
        Ini v;
        v.msg = msg;

		return v;
	}

public:
	string msg;
}

string getIni(T)() @trusted
{
	foreach(it; __traits(getAttributes, T))
    {
		if (hasUDA!(T, Ini))
			return it.msg;
	}

	assert(0);
}

string getIni(T, string member)() @trusted
{
	foreach (it; __traits(getAttributes, __traits(getMember, T, member)))
    {
		if (hasUDA!(__traits(getMember, T, member), Ini))
			return it.msg;
	}

	assert(0, member);
}

class IniFile
{
public:
    alias Line = const(char)[];

    static struct Value
    {
    nothrow @safe:

        Line name;
        Line value;
        Line[] comments;
    }

    static struct Section
    {
    nothrow @safe:

        Line name;
        Value[] values;
        Line[] comments;

        void clear()
        {
            values.length = 0;
            comments.length = 0;
        }

        Line getValue(Line valueName, Line defaultValue = null)
        {
            const i = indexOfName(valueName);
            if (i >= 0)
                return values[i].value;
            else
                return defaultValue;
        }

        ptrdiff_t indexOfName(in Line valueName)
        {
            foreach (i, ref e; values)
            {
                if (sicmp(e.name, valueName) == 0)
                    return i;
            }

            return -1;
        }

        bool removeValue(Line removedName)
        {
             const i = indexOfName(removedName);
             if (i >= 0)
             {
                 removeAt(values, i);
                 return true;
             }
             else
                return false;
        }

        void setValue(Line valueName, Line value)
        in
        {
            assert(valueName.length != 0);
        }
        do
        {
            const i = indexOfName(valueName);
            if (i >= 0)
                values[i].value = value;
            else
                values ~= Value(valueName, value, null);
        }

        bool setValueComment(L...)(Line valueName, L valueComments)
        {
            const i = indexOfName(valueName);
            if (i >= 0)
            {
                values[i].comments = null;
                foreach (c; valueComments)
                    values[i].comments ~= c;

                return true;
            }

            return false;
        }
    }

public:
    /** These two delegates allow extra processing such as encryption to the value
    */

    /** Initiates when caller try to get a value. Occurs before the value being returned
        Params:
            IniFile = this class
            Line = a section name
            Line = a value name
            bool = a default value is being returned
            Line* = a value pointer
    */
    DelegateList!(IniFile, Line, Line, bool, Line*) onGetValue;

    /** Initiates when caller try to set a value. Occurs before the value being set
        Params:
            IniFile = this class
            Line = a section name
            Line = a value name
            Line* = a value pointer
    */
    DelegateList!(IniFile, Line, Line, Line*) onSetValue;

    this(const(char)[] inifileName,
        IniFileOpenMode openMode = IniFileOpenMode.readWrite)
    {
        this._inifileName = inifileName;
        this._openMode = openMode;

        if (openMode == IniFileOpenMode.read)
            load();
        else if (openMode == IniFileOpenMode.readWrite && exists(inifileName))
            load();
    }

    final void clear() nothrow @safe
    {
        _loadedError = false;
        _sections.length = 0;
        foundSection = FoundSection(null, -1);
        _changed = true;
    }

    /** Returns array of all section names in inifile
    */
    final Line[] getSections() nothrow @safe
    {
        if (_sections.length == 0)
            return null;

        Line[] res;

        res.reserve(_sections.length);
        foreach (ref s; _sections)
            res ~= s.name;

        return res;
    }

    /** Returns a string value if existing sectionName & name; otherwise returns defaultValue
    */
    final Line getValue(Line sectionName, Line valueName, Line defaultValue = null)
    {
        Line res;
        const s = indexOfSection(sectionName);
        if (s >= 0)
        {
            res = _sections[s].getValue(valueName, defaultValue);
            if (onGetValue)
                onGetValue(this, sectionName, valueName, false, &res);
        }
        else
        {
            res = defaultValue;
            if (onGetValue)
                onGetValue(this, sectionName, valueName, true, &res);
        }
        return res;
    }

    /** Returns array of all names of the sectionName
    */
    final Line[] getNames(Line sectionName) nothrow @safe
    {
        const s = indexOfSection(sectionName);
        if (s >= 0)
        {
            Line[] res;
            res.reserve(_sections[s].values.length);
            foreach (ref e; _sections[s].values)
                res ~= e.name;
            return res;
        }
        else
            return null;
    }

    /** Returns true if existing sectionName; otherwise returns false
    */
    final bool hasSection(Line sectionName) nothrow @safe
    {
        return indexOfSection(sectionName) >= 0;
    }

    /** Returns true if existing sectionName has existing name; otherwise returns false
    */
    final bool hasValue(Line sectionName, Line valueName) nothrow @safe
    {
        const s = indexOfSection(sectionName);
        if (s >= 0)
            return _sections[s].indexOfName(valueName) >= 0;
        else
            return false;
    }

    final void load(Flag!"throwIfError" throwIfError = No.throwIfError)()
    {
        auto inifile = File(inifileName, "r");
        auto inifileRange = inifile.byLine();
        load!throwIfError(inifileRange);
    }

    final void load(Flag!"throwIfError" throwIfError, Range)(Range input)
    if(isInputRange!Range)
    {
        clear();

        Line[] comments;
        Section section;
        while (!input.empty())
        {
            auto line = input.front().idup; // Need to duplicate (buffer is reused after popFront)
            Line name, value;
            switch (parseSection(line, name))
            {
                case IniFileLineKind.notSection:
                    switch (parseNameValue(line, name, value))
                    {
                        case IniFileLineKind.nameValue:
                        case IniFileLineKind.noValue:
                            if (section.name.length == 0)
                            {
                                _loadedError = true;
                                comments = null;
                                static if (throwIfError)
                                    throw new IniFileException(IniFileMessage.eInvalidKeyName);
                            }
                            else
                            {
                                section.values ~= Value(name, value, comments);
                                comments = null;
                            }
                            break;
                        case IniFileLineKind.comment:
                            comments ~= name;
                            break;
                        case IniFileLineKind.empty:
                            break;
                        case IniFileLineKind.invalidName:
                            _loadedError = true;
                            comments = null;
                            static if (throwIfError)
                                throw new IniFileException(IniFileMessage.eInvalidKeyName);
                            break;
                        default:
                            assert(0);
                    }
                    break;
                case IniFileLineKind.section:
                    if (section.name.length != 0)
                    {
                        section.comments = comments;
                        _sections ~= section;
                        comments = null;
                    }
                    section.name = name;
                    section.values = null;
                    section.comments = null;
                    break;
                case IniFileLineKind.comment:
                    comments ~= name;
                    break;
                case IniFileLineKind.empty:
                    break;
                case IniFileLineKind.invalidSection:
                    _loadedError = true;
                    comments = null;
                    section = Section(null, null, null);
                    static if (throwIfError)
                    {
                        string msg = format(IniFileMessage.eInvalidSectionName, name);
                        throw new IniFileException(msg);
                    }
                    break;
                default:
                    assert(0);
            }

            input.popFront();
        }

        _changed = false;
    }

    /** If found existing removedSectionName, remove it and returns true; otherwise returns false
    */
    final bool removeSection(Line removedName) nothrow @safe
    {
        const i = indexOfSection(removedName);
        if (i >= 0)
        {
            foundSection = FoundSection(null, -1);
            removeAt(_sections, i);
            _changed = true;
            return true;
        }
        else
            return false;
    }

    /** Removes existing value if removedName is found and returns true; otherwise returns false
    */
    final bool removeValue(Line sectionName, Line removedName) nothrow @safe
    {
        const s = indexOfSection(sectionName);
        if (s >= 0 && _sections[s].removeValue(removedName))
        {
            _changed = true;
            return true;
        }
        else
            return false;
    }

    /** Save content into the inifileName
    */
    final void save()
    {
        auto inifile = File(inifileName, "w");
        auto inifileRange = inifile.lockingTextWriter();
        save(inifileRange);
    }

    final void save(Range)(Range output) @safe
    if(isOutputRange!(Range, Line) || isOutputRange!(Range, string))
    {
        enum LN = '\n';

        void saveComments(in Line[] comments)
        {
            foreach (c; comments)
            {
                if (c.length != 0)
                {
                    if (c[0] != ';')
                        output.put(';');
                    output.put(c);
                    output.put(LN);
                }
            }
        }

        foreach (ref s; _sections)
        {
            if (s.comments.length != 0)
                saveComments(s.comments);

            output.put('[');
            output.put(s.name);
            output.put(']');
            output.put(LN);

            foreach (ref e; s.values)
            {
                if (e.comments.length != 0)
                    saveComments(e.comments);

                output.put(e.name);
                if (e.value !is null)
                {
                    output.put('=');
                    output.put(e.value);
                }
                output.put(LN);
            }

            output.put(LN);
        }

        _changed = false;
    }

    /** Set comment to the section, sectionName
    */
    final bool setSectionComment(L...)(Line sectionName, L sectionComments) nothrow @safe
    {
        const s = indexOfSection(sectionName);
        if (s >= 0)
        {
            _sections[s].comments = null;
            foreach (c; sectionComments)
                _sections[s].comments ~= c;

            _changed = true;
            return true;
        }
        else
            return false;
    }

    /** Set comment to the name, valueName
    */
    final bool setValueComment(L...)(Line sectionName, Line valueName, L valueComments) nothrow @safe
    {
        const s = indexOfSection(sectionName);
        if (s >= 0)
        {
            if (_sections[s].setValueComment(valueName, valueComments))
            {
                _changed = true;
                return true;
            }
        }

        return false;
    }

    final void setValue(Line sectionName, Line valueName, Line value)
    in
    {
        assert(sectionName.length != 0);
        assert(valueName.length != 0);
    }
    do
    {
        if (onSetValue)
            onSetValue(this, sectionName, valueName, &value);

        const s = indexOfSection(sectionName);
        if (s < 0)
        {
            auto section = Section(sectionName, null, null);
            section.setValue(valueName, value);
            _sections ~= section;
        }
        else
            _sections[s].setValue(valueName, value);

        _changed = true;
    }

public:
    pragma (inline, true)
    static bool isSpace(dchar c) pure nothrow @safe
    {
        return c == ' ' || c == '\t';
    }

    static IniFileLineKind parseSection(Line line, out Line name) pure nothrow @safe
    {
        enum notSet = -1;

        ptrdiff_t nb, ne;
        bool lb, rb;

        IniFileLineKind emptySection(IniFileLineKind res)
        {
            name = res == IniFileLineKind.comment ? line[nb..ne] : null;
            return res;
        }

        nb = ne = notSet;
	    foreach (i, c; line)
        {
		    if (isSpace(c))
            {
                if (lb && !rb && ne == notSet)
                    ne = i;
            }
		    else if (c == '[')
            {
                if (!lb)
                    lb = true;
                else
                    return emptySection(IniFileLineKind.invalidSection);
		    }
		    else if (c == ']')
            {
                if (!lb)
                    return emptySection(IniFileLineKind.notSection);

                if (!rb)
                {
                    rb = true;
                    if (ne == notSet)
                        ne = i;
                }
                else
                    return emptySection(IniFileLineKind.invalidSection);
		    }
            else
            {
                if (!lb)
                {
                    if (c == ';')
                    {
                        nb = i;
                        ne = line.length;
                        return emptySection(IniFileLineKind.comment);
                    }
                    else
                        return emptySection(IniFileLineKind.notSection);
                }
                else if (rb)
                    return emptySection(IniFileLineKind.invalidSection);

                if (nb == notSet)
                    nb = i;
                else
                    ne = notSet; // Reset
            }
	    }

        if (lb && rb && nb >= 0 && ne > nb)
        {
            name = line[nb..ne];
            return IniFileLineKind.section;
        }
        else
        {
            if (lb)
                return emptySection(IniFileLineKind.invalidSection);
            else
                return emptySection(IniFileLineKind.notSection);
        }
    }

    static IniFileLineKind parseNameValue(Line line, out Line name, out Line value) nothrow @safe
    {
        enum notSet = -1;

        ptrdiff_t kb, ke, kq, e, vb, ve;

        IniFileLineKind emptyKeyValue(IniFileLineKind res)
        {
            name = res == IniFileLineKind.comment ? line[vb..ve] : null;
            value = null;
            return res;
        }

        void adjustQuote(ref ptrdiff_t ab, ref ptrdiff_t ae)
        {
            if (line[ab] == '"' && line[ae - 1] == '"')
            {
                ++ab;
                --ae;
            }
        }

        kq = 0;
        kb = ke = e = vb = ve = notSet;
	    foreach (i, c; line)
        {
		    if (isSpace(c))
            {
                // Still in key range?
                if (e == notSet)
                {
                    // End name index set?
                    if (kb != notSet && ke == notSet && kq == 0)
                        ke = i;
                }
                else
                {
                    // End value index set?
                    if (vb != notSet && ve == notSet)
                        ve = i;
                }
            }
		    else if (c == '=' && e == notSet && kq != 1)
            {
                e = i;
                if (ke == notSet)
                    ke = i;
		    }
            else
            {
                // Allow quoted name
                if (c == '"')
                {
                    if (kb == notSet && kq == 0)
                    {
                        kq = 1;
                        kb = i;
                        continue;
                    }
                    else if (ke == notSet && kq == 1)
                    {
                        kq = 2;
                        ke = i + 1;
                        continue;
                    }
                }

                // Still in key range?
                if (e == notSet)
                {
                    // Begin name index set?
                    if (kb == notSet)
                    {
                        // Comment line?
                        if (c == ';')
                        {
                            vb = i;
                            ve = line.length;
                            return emptyKeyValue(IniFileLineKind.comment);
                        }

                        kb = i;
                    }
                    else
                    {
                        // Invalid?
                        if (kq == 2)
                            return emptyKeyValue(IniFileLineKind.invalidName);
                        else
                            ke = notSet; // Reset
                    }
                }
                else
                {
                    // Begin value index set?
                    if (vb == notSet)
                        vb = i;
                    else
                        ve = notSet; // Reset
                }
            }
	    }

        // Empty?
        if (kb == notSet)
            return emptyKeyValue(IniFileLineKind.empty);

        // No equal sign or no value?
        if (e == notSet || vb == notSet)
        {
            if (ke == notSet)
                ke = line.length;

            adjustQuote(kb, ke);

            name = line[kb..ke];
            value = null;
            return IniFileLineKind.noValue;
        }
        else
        {
            if (ve == notSet)
                ve = line.length;

            adjustQuote(kb, ke);
            adjustQuote(vb, ve);

            name = line[kb..ke];
            value = line[vb..ve];
            return IniFileLineKind.nameValue;
        }
    }

    @property final bool changed() const nothrow @safe
    {
        return _changed;
    }

    @property final const(char)[] inifileName() const nothrow @safe
    {
        return _inifileName;
    }

    @property final bool loadedError() const nothrow @safe
    {
        return _loadedError;
    }

    @property final bool needToSave() const nothrow @safe
    {
        return changed && _sections.length != 0 && inifileName.length != 0;
    }

    @property final IniFileOpenMode openMode() const nothrow @safe
    {
        return _openMode;
    }

    @property final Section[] sections() nothrow @safe
    {
        return _sections;
    }

protected:
    final ptrdiff_t indexOfSection(Line sectionName) nothrow @safe
    {
        if (sicmp(foundSection.name, sectionName) == 0)
            return foundSection.index;

        foreach (i, ref s; _sections)
        {
            if (sicmp(s.name, sectionName) == 0)
            {
                foundSection = FoundSection(s.name, i);
                return i;
            }
        }

        return -1;
    }

private:
    static struct FoundSection
    {
    nothrow @safe:

        Line name;
        ptrdiff_t index;
    }

    const(char)[] _inifileName;
    Section[] _sections;
    FoundSection foundSection = FoundSection(null, -1);
    IniFileOpenMode _openMode;
    bool _changed, _loadedError;
}

string loadMember(T)() @safe
{
	import std.format : format;

    enum arrayValueFmt = "\ncase \"%s\": \nt.%s = to!(typeof(t.%s))(inifile.getValue(sectionName, name).split(','));\n++matchedCount;\nbreak;\n";
    enum basicValueFmt = "\ncase \"%s\": \nt.%s = to!(typeof(t.%s))(inifile.getValue(sectionName, name));\n++matchedCount;\nbreak;\n";

	string res;

	foreach (it; __traits(allMembers, T))
    {
		if (hasUDA!(__traits(getMember, T, it), Ini))
        {
            if (isBasicType!(typeof(__traits(getMember, T, it)))
			    || isSomeString!(typeof(__traits(getMember, T, it))))
            {
                res ~= basicValueFmt.format(it, it, it);
            }
            else if (isArray!(typeof(__traits(getMember, T, it))))
            {
                res ~= arrayValueFmt.format(it, it, it);
            }
        }
	}

    assert(res.length != 0);

	return "switch (name)\n{" ~ res ~ "default: break;\n}";
}

size_t loadMembers(T)(IniFile inifile, IniFile.Line sectionName, ref T t)
{
    import std.conv : to;
    import std.string : split;

    auto names = inifile.getNames(sectionName);
    if (names.length != 0)
    {
        enum exp = loadMember!T();
        size_t matchedCount;
        foreach (name; names)
        {
            mixin(exp);
        }
        return matchedCount;
    }
    else
        return 0;
}

string saveMember(T)(T t)
{
	import std.format : format;
    import std.traits : fullyQualifiedName;

    static if (isBasicType!T || isSomeString!T)
        return format("%s", t);
    else static if (isArray!T && (isBasicType!(ElementType!T) || isSomeString!(ElementType!T)))
    {
        string value;
		foreach(it; t)
        {
            if (value.length != 0)
                value ~= format(",%s", it);
            else
                value = format("%s", it);
		}
        return value;
    }
    else
    {
        static assert(0, "Not support type: " ~ fullyQualifiedName!T);
        return null;
    }
}

size_t saveMembers(T)(IniFile inifile, IniFile.Line sectionName, ref T t)
{
    size_t matchedCount;
	foreach (it; __traits(allMembers, T))
    {
		if (hasUDA!(__traits(getMember, T, it), Ini))
        {
			static if (isBasicType!(typeof(__traits(getMember, T, it)))
			           || isSomeString!(typeof(__traits(getMember, T, it)))
                       || isArray!(typeof(__traits(getMember, T, it))))
			{
                inifile.setValue(sectionName, it, saveMember(__traits(getMember, t, it)));
                inifile.setValueComment(sectionName, it, getIni!(T, it)());
                ++matchedCount;
			}
		}
	}

    if (hasUDA!(T, Ini))
		inifile.setSectionComment(sectionName, getIni!T());

    return matchedCount;
}


// Any below codes are private
private:


unittest // IniFile.parseSection
{
    import pham.utl.test;
    traceUnitTest("unittest utl.inifile.IniFile.parseSection");

    IniFile.Line name;

    string gName()
    {
        return "'" ~ name.idup ~ "'";
    }

	assert(IniFile.parseSection("[SectionName]", name) == IniFileLineKind.section);
    assert(name == "SectionName", gName());

	assert(IniFile.parseSection("[SectionName.WithDot]", name) == IniFileLineKind.section);
    assert(name == "SectionName.WithDot", gName());

	assert(IniFile.parseSection(" [ SectionName]", name) == IniFileLineKind.section);
    assert(name == "SectionName", gName());

	assert(IniFile.parseSection(" [ SectionName.WithDot]", name) == IniFileLineKind.section);
    assert(name == "SectionName.WithDot", gName());

	assert(IniFile.parseSection(" [ SectionName ] ", name) == IniFileLineKind.section);
    assert(name == "SectionName", gName());

	assert(IniFile.parseSection(" [ SectionName.WithDot ] ", name) == IniFileLineKind.section);
    assert(name == "SectionName.WithDot", gName());

	assert(IniFile.parseSection("[]", name) == IniFileLineKind.invalidSection);
	assert(IniFile.parseSection("[[]", name) == IniFileLineKind.invalidSection);
	assert(IniFile.parseSection("[]]", name) == IniFileLineKind.invalidSection);
	assert(IniFile.parseSection("[[]]", name) == IniFileLineKind.invalidSection);

	assert(IniFile.parseSection("]", name) == IniFileLineKind.notSection);
	assert(IniFile.parseSection("", name) == IniFileLineKind.notSection);
	assert(IniFile.parseSection("abc", name) == IniFileLineKind.notSection);
	assert(IniFile.parseSection("", name) == IniFileLineKind.notSection);

	assert(IniFile.parseSection(";[SectionName] ", name) == IniFileLineKind.comment);
    assert(name == ";[SectionName] ", gName());

	assert(IniFile.parseSection(";[SectionName.WithDot] ", name) == IniFileLineKind.comment);
    assert(name == ";[SectionName.WithDot] ", gName());

	assert(IniFile.parseSection(" ;[SectionName.WithDot] ", name) == IniFileLineKind.comment);
    assert(name == ";[SectionName.WithDot] ", gName());
}

unittest // IniFile.parseNameValue
{
    import pham.utl.test;
    traceUnitTest("unittest utl.inifile.IniFile.parseNameValue");

    IniFile.Line name, value;

    string gName()
    {
        return "'" ~ name.idup ~ "'";
    }

    string gValue()
    {
        return "'" ~ value.idup ~ "'";
    }

	assert(IniFile.parseNameValue("", name, value) == IniFileLineKind.empty);
	assert(IniFile.parseNameValue("  ", name, value) == IniFileLineKind.empty);

	assert(IniFile.parseNameValue(";", name, value) == IniFileLineKind.comment);
    assert(name == ";", gName());

	assert(IniFile.parseNameValue(" ;comment=text", name, value) == IniFileLineKind.comment);
    assert(name == ";comment=text", gName());

	assert(IniFile.parseNameValue("key ", name, value) == IniFileLineKind.noValue);
    assert(name == "key", gName());
    assert(value is null, gValue());

	assert(IniFile.parseNameValue("key=", name, value) == IniFileLineKind.noValue);
    assert(name == "key", gName());
    assert(value is null, gValue());

	assert(IniFile.parseNameValue("key=value", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "value", gValue());

	assert(IniFile.parseNameValue(" key = value ", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "value", gValue());

	assert(IniFile.parseNameValue("key=\"=value\"", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "=value", gValue());

	assert(IniFile.parseNameValue("key= value\" ", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "value\"", gValue());

	assert(IniFile.parseNameValue("key = 123", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "123", gValue());

	assert(IniFile.parseNameValue(" key = abc defg ", name, value) == IniFileLineKind.nameValue);
    assert(name == "key", gName());
    assert(value == "abc defg", gValue());

	assert(IniFile.parseNameValue(" \"quoted=name\" = value=equal ", name, value) == IniFileLineKind.nameValue);
    assert(name == "quoted=name", gName());
    assert(value == "value=equal", gValue());

	assert(IniFile.parseNameValue(" \" quoted = name \" = \" value = equal \" ", name, value) == IniFileLineKind.nameValue);
    assert(name == " quoted = name ", gName());
    assert(value == " value = equal ", gValue());

	assert(IniFile.parseNameValue(" \"quoted=name ", name, value) == IniFileLineKind.noValue);
    assert(name == "\"quoted=name ", gName());
    assert(value is null, gValue());

	assert(IniFile.parseNameValue(" \"quoted=name\" abc", name, value) == IniFileLineKind.invalidName);
    assert(name is null, gName());
    assert(value is null, gValue());
}

unittest // IniFile
{
    import pham.utl.test;
    traceUnitTest("unittest utl.inifile.IniFile");

    IniFile inifile = new IniFile("unittestIniFile.ini", IniFileOpenMode.write);

    // Check for empty
    assert(inifile.hasSection("section") == false);
    assert(inifile.hasValue("section", "name") == false);

    assert(inifile.getSections() is null);
    assert(inifile.getValue("section", "name") is null);
    assert(inifile.getNames("section") is null);

    assert(inifile.removeValue("section", "name") == false);
    assert(inifile.removeSection("section") == false);

    // Check existing
    inifile.setValue("section", "name", "value");
    assert(inifile.hasSection("section") == true);
    assert(inifile.hasValue("section", "name") == true);

    assert(inifile.getSections().length == 1);
    assert(inifile.getValue("section", "name") == "value");
    assert(inifile.getNames("section").length == 1);

    assert(inifile.removeValue("section", "name") == true);
    assert(inifile.removeSection("section") == true);

    // Check after removed
    assert(inifile.hasSection("section") == false);
    assert(inifile.hasValue("section", "name") == false);

    assert(inifile.getSections() is null);
    assert(inifile.getValue("section", "name") is null);
    assert(inifile.getNames("section") is null);
}

version (unittest)
@Ini("Foo struct")
struct Foo
{
	@Ini("Foo name")
	string name;

	@Ini("Foo weight")
	float weight;

	@Ini("Foo age")
	int age;

	@Ini("Foo alive")
	bool alive;

	@Ini("Foo string array")
    string[] words;

	@Ini("Foo int array")
    int[] ints;

	bool opEquals(Foo other)
    {
		import std.math : isClose, isNaN;
        import std.algorithm.comparison : equal;

		return this.name == other.name
            && this.age == other.age
            && this.alive == other.alive
            && equal(this.words, other.words)
            && equal(this.ints, other.ints)
			&& (isClose(this.weight, other.weight) || (isNaN(this.weight) && isNaN(other.weight)));
	}
}

unittest // saveMembers & loadMembers
{
    import pham.utl.test;
    traceUnitTest("unittest utl.inifile.saveMembers & utl.inifile.loadMembers");

    IniFile inifile = new IniFile("unittestIniFile.ini", IniFileOpenMode.write);

    Foo p1;
	p1.name = "Foo";
	p1.age = 37;
	p1.weight = 153.0;
    p1.alive = true;
    p1.words = ["123", "asd"];
    p1.ints = [123, 0, int.max];

    Foo pU;
    assert(p1 != pU);

    size_t v1 = saveMembers(inifile, "Foo", p1);
    inifile.save();

    Foo p2;
    size_t v2 = loadMembers(inifile, "Foo", p2);
    assert(p1 == p2);

    IniFile inifile2 = new IniFile("unittestIniFile.ini", IniFileOpenMode.read);
    Foo p3;
    size_t v3 = loadMembers(inifile, "Foo", p3);
    assert(p1 == p3);

    inifile = null;
    inifile2 = null;
}
