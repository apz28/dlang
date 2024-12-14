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

module pham.dtm.dtm_time_zone;

import std.conv : to;
import std.math.algebraic : abs;
import std.uni : sicmp;

debug(debug_pham_dtm_dtm_time_zone) import std.stdio : writeln;
import pham.utl.utl_result : cmp;
import pham.dtm.dtm_date;
import pham.dtm.dtm_tick;
import pham.dtm.dtm_time;

@safe:

struct AdjustmentRule
{
@safe:

public:
    this(in DateTime dateBegin,
        in DateTime dateEnd,
        in ZoneOffset baseUtcOffsetDelta,
        in ZoneOffset daylightDelta,
        in ZoneOffset standardDelta,
        in TransitionTime daylightTransitionBegin,
        in TransitionTime daylightTransitionEnd,
        bool noDaylightTransitions) @nogc nothrow pure
    in
    {
        assert(isValidAdjustmentRule(dateBegin, dateEnd, daylightDelta, standardDelta,
            daylightTransitionBegin, daylightTransitionEnd, noDaylightTransitions) == AdjustmentRuleError.none);
    }
    do
    {
        //validateAdjustmentRule(dateBegin, dateEnd, daylightDelta, standardDelta,
        //    daylightTransitionBegin, daylightTransitionEnd, noDaylightTransitions);

        this._dateBegin = dateBegin;
        this._dateEnd = dateEnd;
        this._baseUtcOffsetDelta = baseUtcOffsetDelta;
        this._daylightDelta = daylightDelta;
        this._daylightTransitionBegin = daylightTransitionBegin;
        this._daylightTransitionEnd = daylightTransitionEnd;
        this._standardDelta = standardDelta;
        this._noDaylightTransitions = noDaylightTransitions;
    }

    bool opEquals(scope const(AdjustmentRule) rhs) const @nogc nothrow pure scope
    {
        return _dateBegin == rhs._dateBegin
            && _dateEnd == rhs._dateEnd
            && _baseUtcOffsetDelta == rhs._baseUtcOffsetDelta
            && _daylightDelta == rhs._daylightDelta
            && _daylightTransitionBegin == rhs._daylightTransitionBegin
            && _daylightTransitionEnd == rhs._daylightTransitionEnd
            && _standardDelta == rhs._standardDelta;
    }

    bool hasDaylightSaving() const @nogc nothrow pure scope
    {
        enum minPlus = DateTime.min.addMilliseconds(1);

        return daylightDelta.hasOffset
            || (daylightTransitionBegin != TransitionTime.init && daylightTransitionBegin.timeOfDay != DateTime.min)
            || (daylightTransitionEnd != TransitionTime.init && daylightTransitionEnd.timeOfDay != minPlus);
    }

    /**
     * When Windows sets the daylight transition begin Jan 1st at 12:00 AM, it means the year begins with the daylight saving on.
     * We have to special case this value and not adjust it when checking if any date is in the daylight saving period.
     */
    bool isBeginDateMarkerForBeginningOfYear() const @nogc nothrow pure scope
    {
        return !noDaylightTransitions
            && daylightTransitionBegin.month == 1 && daylightTransitionBegin.day == 1
            && daylightTransitionBegin.timeOfDay.time.sticks < Tick.ticksPerSecond; // < 12:00:01 AM
    }

    /**
     * When Windows sets the daylight transition end Jan 1st at 12:00 AM, it means the year ends with the daylight saving on.
     * We have to special case this value and not adjust it when checking if any date is in the daylight saving period.
     */
    bool isEndDateMarkerForEndOfYear() const @nogc nothrow pure scope
    {
        return !noDaylightTransitions
            && daylightTransitionEnd.month == 1 && daylightTransitionEnd.day == 1
            && daylightTransitionEnd.timeOfDay.time.sticks < Tick.ticksPerSecond; // < 12:00:01 AM
    }

    enum AdjustmentRuleError : ubyte
    {
        none,
        beginKind,
        beginTimeOfDay,
        beginGreater,
        beginSame,
        endKind,
        endTimeOfDay,
        daylightDelta,
        daylightDeltaOutOfRange,
        standardDelta,
    }

    static AdjustmentRuleError isValidAdjustmentRule(
        scope const(DateTime) dateBegin,
        scope const(DateTime) dateEnd,
        scope const(ZoneOffset) daylightDelta,
        scope const(ZoneOffset) standardDelta,
        scope const(TransitionTime) daylightTransitionBegin,
        scope const(TransitionTime) daylightTransitionEnd,
        bool noDaylightTransitions) @nogc nothrow pure
    {
        if (dateBegin.kind != DateTimeZoneKind.unspecified && dateBegin.kind != DateTimeZoneKind.utc)
            return AdjustmentRuleError.beginKind;

        if (dateBegin != DateTime.min && dateBegin.kind == DateTimeZoneKind.unspecified && dateBegin.time != Time.zero)
            return AdjustmentRuleError.beginTimeOfDay;

        if (dateBegin > dateEnd)
            return AdjustmentRuleError.beginGreater;

        if (daylightTransitionBegin == daylightTransitionEnd && !noDaylightTransitions)
            return AdjustmentRuleError.beginSame;

        if (dateEnd.kind != DateTimeZoneKind.unspecified && dateEnd.kind != DateTimeZoneKind.utc)
            return AdjustmentRuleError.endKind;

        if (dateEnd != DateTime.max && dateEnd.kind == DateTimeZoneKind.unspecified && dateEnd.time != Time.zero)
            return AdjustmentRuleError.endTimeOfDay;

        if (daylightDelta.toTicks() % Tick.ticksPerMinute != 0)
        {
            import std.stdio : writeln; debug writeln("isValidAdjustmentRule.daylightDelta=", daylightDelta.toString, ", ticks=", daylightDelta.toTicks());
            return AdjustmentRuleError.daylightDelta;
        }

        // This cannot use UtcOffsetOutOfRange to account for the scenario where Samoa moved across the International Date Line,
        // which caused their current BaseUtcOffset to be +13. But on the other side of the line it was UTC-11 (+1 for daylight).
        // So when trying to describe DaylightDeltas for those times, the DaylightDelta needs
        // to be -23 (what it takes to go from UTC+13 to UTC-10)
        if (daylightDelta.isValid() != ErrorOp.none)
        {
            import std.stdio : writeln; debug writeln("isValidAdjustmentRule.daylightDelta=", daylightDelta.toString);
            return AdjustmentRuleError.daylightDeltaOutOfRange;
        }

        if (standardDelta.toTicks() % Tick.ticksPerMinute != 0)
        {
            import std.stdio : writeln; debug writeln("isValidAdjustmentRule.standardDelta=", standardDelta.toString, ", ticks=", standardDelta.toTicks());
            return AdjustmentRuleError.standardDelta;
        }

        return AdjustmentRuleError.none;
    }

    static void validateAdjustmentRule(
        scope const(DateTime) dateBegin,
        scope const(DateTime) dateEnd,
        scope const(ZoneOffset) daylightDelta,
        scope const(ZoneOffset) standardDelta,
        scope const(TransitionTime) daylightTransitionBegin,
        scope const(TransitionTime) daylightTransitionEnd,
        bool noDaylightTransitions) pure
    {
        final switch (isValidAdjustmentRule(dateBegin, dateEnd, daylightDelta, standardDelta,
            daylightTransitionBegin, daylightTransitionEnd, noDaylightTransitions))
        {
            case AdjustmentRuleError.none:
                return;
            case AdjustmentRuleError.beginKind:
                throw new TimeException("dateBegin.kind must be either DateTimeZoneKind.unspecified or DateTimeZoneKind.utc");
            case AdjustmentRuleError.beginTimeOfDay:
                throw new TimeException("dateBegin has timeOfDay");
            case AdjustmentRuleError.beginGreater:
                throw new TimeException("dateBegin is greater than dateEnd");
            case AdjustmentRuleError.beginSame:
                throw new TimeException("Transition times are identical");
            case AdjustmentRuleError.endKind:
                throw new TimeException("dateEnd.kind must be either DateTimeZoneKind.unspecified or DateTimeZoneKind.utc");
            case AdjustmentRuleError.endTimeOfDay:
                throw new TimeException("dateEnd has timeOfDay");
            case AdjustmentRuleError.daylightDelta:
                throw new TimeException("daylightDelta has seconds");
            case AdjustmentRuleError.daylightDeltaOutOfRange:
                throwOutOfRange!(ErrorPart.hour)(daylightDelta.hour);
                break;
            case AdjustmentRuleError.standardDelta:
                throw new TimeException("standardDelta has seconds");
        }
    }

    /**
     * The time difference with the base UTC offset for the time zone during the adjustment-rule period
     */
    @property ZoneOffset baseUtcOffsetDelta() const @nogc nothrow pure scope
    {
        return _baseUtcOffsetDelta;
    }

    /**
     * The amount of time that is required to form the time zone's daylight saving
     * time. This amount of time is added to the time zone's offset from Coordinated
     * Universal Time (UTC).
     */
    @property ZoneOffset daylightDelta() const @nogc nothrow pure scope
    {
        return _daylightDelta;
    }

    /**
     * The information about the annual transition from standard time to daylight saving time
     */
    @property TransitionTime daylightTransitionBegin() const @nogc nothrow pure scope
    {
        return _daylightTransitionBegin;
    }

    /**
     * The information about the annual transition from daylight saving time back to standard time
     */
    @property TransitionTime daylightTransitionEnd() const @nogc nothrow pure scope
    {
        return _daylightTransitionEnd;
    }

    /**
     * The date when the adjustment rule takes effect
     */
    @property DateTime dateBegin() const @nogc nothrow pure scope
    {
        return _dateBegin;
    }

    /**
     * The date when the adjustment rule stops to be in effect
     */
    @property DateTime dateEnd() const @nogc nothrow pure scope
    {
        return _dateEnd;
    }

    /**
     * A value indicating that this AdjustmentRule fixes the time zone offset
     * from dateBegin to dateEnd without any daylight transitions in between
     */
    @property bool noDaylightTransitions() const @nogc nothrow pure scope
    {
        return _noDaylightTransitions;
    }

    /**
     * The amount of time that is required to form the time zone's standard
     * time. This amount of time is added to the time zone's offset from Coordinated
     * Universal Time (UTC).
     */
    @property ZoneOffset standardDelta() const @nogc nothrow pure scope
    {
        return _standardDelta;
    }

private:
    DateTime _dateBegin;
    DateTime _dateEnd;
    ZoneOffset _baseUtcOffsetDelta;
    ZoneOffset _daylightDelta;
    TransitionTime _daylightTransitionBegin;
    TransitionTime _daylightTransitionEnd;
    ZoneOffset _standardDelta;
    bool _noDaylightTransitions;
}

struct TimeZoneInfo
{
@safe:

public:
    this(string id, string displayName, string standardName, string daylightName,
        ZoneOffset baseUtcOffset, bool supportsDaylightSavingTime) @nogc nothrow pure
    in
    {
        assert(isValidTimeZoneInfo(id, baseUtcOffset, null) == ValidatedTimeZoneError.none);
    }
    do
    {
        this._id = id;
        this._displayName = displayName ;
        this._standardName = standardName;
        this._daylightName = daylightName;
        this._baseUtcOffset = baseUtcOffset;
        this._supportsDaylightSavingTime = supportsDaylightSavingTime;
    }

    this(string id, string displayName, string standardName, string daylightName,
        ZoneOffset baseUtcOffset, bool supportsDaylightSavingTime,
        AdjustmentRule[] adjustmentRules) @nogc nothrow pure
    in
    {
        assert(isValidTimeZoneInfo(id, baseUtcOffset, adjustmentRules) == ValidatedTimeZoneError.none);
    }
    do
    {
        this._id = id;
        this._displayName = displayName ;
        this._standardName = standardName;
        this._daylightName = daylightName;
        this._baseUtcOffset = baseUtcOffset;
        this._supportsDaylightSavingTime = supportsDaylightSavingTime && adjustmentRules.length != 0;
        this._adjustmentRules = adjustmentRules;
    }

    bool opEquals(scope const(TimeZoneInfo) rhs) const @nogc nothrow pure scope
    {
        scope (failure) assert(0, "Assume nothrow failed");

        bool equalsAdjustmentRules() const @nogc nothrow pure
        {
            if (_adjustmentRules.length != rhs._adjustmentRules.length)
                return false;
            foreach (i; 0.._adjustmentRules.length)
            {
                if (!(_adjustmentRules[i] == rhs._adjustmentRules[i]))
                    return false;
            }
            return true;
        }

        return _baseUtcOffset == rhs._baseUtcOffset
            && _supportsDaylightSavingTime == rhs._supportsDaylightSavingTime
            && sicmp(_id, rhs._id) == 0
            && equalsAdjustmentRules();
    }

    DateTime convertDateTimeToTimeZone(scope const(DateTime) dateTime, scope const ref TimeZoneInfo destinationTimeZone) const @nogc nothrow pure scope
    {
        const DateTimeZoneKind sourceKind = kind();

        //
        // check to see if the DateTime is in an invalid time range.  This check
        // requires the current AdjustmentRule and DaylightTime - which are also
        // needed to calculate 'sourceOffset' in the normal conversion case.
        // By calculating the 'sourceOffset' here we improve the
        // performance for the normal case at the expense of the 'ArgumentException'
        // case and Loss-less Local special cases.
        //
        ZoneOffset sourceOffset = baseUtcOffset;
        AdjustmentRule sourceRule = void;
        ptrdiff_t sourceRuleIndex = void;
        if (findAdjustmentRule(dateTime, false, sourceRule, sourceRuleIndex))
        {
            sourceOffset = ZoneOffset(sourceOffset.toMinutes() + sourceRule.baseUtcOffsetDelta.toMinutes());
            if (sourceRule.hasDaylightSaving)
            {
                const DaylightTimeInfo sourceDaylightTime = getDaylightTime(dateTime.year, sourceRule, sourceRuleIndex);
                const bool sourceIsDaylightSavings = getIsDaylightSavings(dateTime, sourceRule, sourceDaylightTime);

                // adjust the sourceOffset according to the Adjustment Rule / Daylight Saving Rule
                sourceOffset = ZoneOffset(sourceOffset.toMinutes() + (sourceIsDaylightSavings ? sourceRule.daylightDelta.toMinutes() : sourceRule.standardDelta.toMinutes()));
            }
        }

        const DateTimeZoneKind targetKind = destinationTimeZone.kind();

        // handle the special case of Loss-less Local->Local and UTC->UTC)
        if (dateTime.kind != DateTimeZoneKind.unspecified && sourceKind != DateTimeZoneKind.unspecified && sourceKind == targetKind)
            return dateTime;

        const long utcTicks = dateTime.sticks - sourceOffset.toTicks();

        // handle the normal case by converting from 'source' to UTC and then to 'target'
        const(DateTime) targetConverted = convertUtcToTimeZone(utcTicks, destinationTimeZone);
        return DateTime(targetConverted.sticks, targetKind);
    }

    DateTime convertDateTimeToUTC(scope const(DateTime) dateTime) const @nogc nothrow scope
    {
        return convertDateTimeToTimeZone(dateTime, utcTimeZone);
    }

    static DateTime convertUtcToLocal(scope const(DateTime) utcDateTime) nothrow
    in
    {
        assert(utcDateTime.kind == DateTimeZoneKind.utc);
    }
    do
    {
        const ltz = localTimeZone(utcDateTime.year);
        return convertUtcToLocal(utcDateTime, ltz);
    }

    static DateTime convertUtcToLocal(scope const(DateTime) utcDateTime, scope const ref TimeZoneInfo localTimeZone) @nogc nothrow pure
    in
    {
        assert(utcDateTime.kind == DateTimeZoneKind.utc);
    }
    do
    {
        bool isDaylightSavings = void;
        const loffset = localTimeZone.getUtcOffsetFromUtc(utcDateTime, isDaylightSavings);
        const lticks = utcDateTime.sticks + loffset.toTicks();
        return lticks < DateTime.minTicks
            ? DateTime(DateTime.minTicks, DateTimeZoneKind.local)
            : (lticks > DateTime.maxTicks ? DateTime(DateTime.maxTicks, DateTimeZoneKind.local) : DateTime(lticks, DateTimeZoneKind.local));
    }

    bool findAdjustmentRule(scope const(DateTime) dateTime, bool dateTimeIsUtc,
        out AdjustmentRule rule, out ptrdiff_t ruleIndex) const @nogc nothrow pure scope
    {
        if (_adjustmentRules.length == 0)
        {
            rule = AdjustmentRule.init;
            ruleIndex = -1;
            return false;
        }

        // Only check the whole-date portion of the dateTime for DateTimeZoneKind.Unspecified rules -
        // This is because the AdjustmentRule DateStart & DateEnd are stored as
        // Date-only values {4/2/2006 - 10/28/2006} but actually represent the
        // time span {4/2/2006@00:00:00.00000 - 10/28/2006@23:59:59.99999}
        const dateOnly = dateTimeIsUtc ? dateTime.addTicksClamp(baseUtcOffset.toTicks()).dateOnly : dateTime.dateOnly;

        ptrdiff_t low = 0;
        ptrdiff_t high = cast(ptrdiff_t)(_adjustmentRules.length) - 1;
        while (low <= high)
        {
            const medianIndex = low + ((high - low) >> 1);
            auto medianRule = _adjustmentRules[medianIndex];
            auto previousRule = medianIndex > 0 ? _adjustmentRules[medianIndex - 1] : medianRule;
            const compareResult = compareAdjustmentRuleToDateTime(medianRule, previousRule, dateTime, dateOnly, dateTimeIsUtc);
            if (compareResult == 0)
            {
                rule = medianRule;
                ruleIndex = medianIndex;
                return true;
            }
            else if (compareResult < 0)
            {
                low = medianIndex + 1;
            }
            else
            {
                high = medianIndex - 1;
            }
        }

        rule = AdjustmentRule.init;
        ruleIndex = -1;
        return false;
    }

    ZoneOffset getUtcOffsetFromUtc(scope const(DateTime) utcDateTime, out bool isDaylightSavings) const @nogc nothrow pure scope
    {
        DateTime searchDateTime = void;
        int searchYear = void;

        if (utcDateTime > s_maxDateOnly)
        {
            searchDateTime = DateTime.max;
            searchYear = DateTime.maxYear;
        }
        else if (utcDateTime < s_minDateOnly)
        {
            searchDateTime = DateTime.min;
            searchYear = DateTime.minYear;
        }
        else
        {
            searchDateTime = utcDateTime;
            searchYear = int.min; // Need adjustment
        }

        AdjustmentRule rule = void;
        ptrdiff_t ruleIndex = void;
        if (findAdjustmentRule(searchDateTime, true, rule, ruleIndex))
        {
            if (searchYear == int.min)
                searchYear = utcDateTime.addTicksClamp(baseUtcOffset.toTicks()).year;

            if (rule.hasDaylightSaving)
            {
                isDaylightSavings = getIsDaylightSavingsFromUtc(utcDateTime, searchYear, baseUtcOffset, rule, ruleIndex);
                return ZoneOffset(baseUtcOffset.toMinutes() 
                    + rule.baseUtcOffsetDelta.toMinutes() 
                    + (isDaylightSavings ? rule.daylightDelta.toMinutes() : rule.standardDelta.toMinutes()));
            }
        }

        isDaylightSavings = false;
        return baseUtcOffset;
    }

    bool isDaylightSavingTime(scope const(DateTime) dateTime) const nothrow scope
    {
        if (!_supportsDaylightSavingTime || _adjustmentRules.length == 0)
            return false;

        DateTime adjustedTime;

        //
        // handle any local/utc special cases...
        //
        if (dateTime.kind == DateTimeZoneKind.local)
        {
            auto ltz = localTimeZone(0); // Use default local
            adjustedTime = ltz.convertDateTimeToTimeZone(dateTime, this);
        }
        else if (dateTime.kind == DateTimeZoneKind.utc)
        {
            if (this.kind == DateTimeZoneKind.utc)
            {
                // simple always false case: TimeZoneInfo.utc.isDaylightSavingTime(dateTime);
                return false;
            }
            else
            {
                // passing in a UTC dateTime to a non-UTC TimeZoneInfo instance is a
                // special Loss-Less case.
                bool isDaylightSavings;
                getUtcOffsetFromUtc(dateTime, isDaylightSavings);
                return isDaylightSavings;
            }
        }
        else
        {
            adjustedTime = dateTime;
        }

        //
        // handle the normal cases...
        //
        AdjustmentRule rule = void;
        ptrdiff_t ruleIndex = void;
        if (!findAdjustmentRule(adjustedTime, false, rule, ruleIndex))
            return false;
        if (!rule.hasDaylightSaving)
            return false;

        auto daylightTime = getDaylightTime(adjustedTime.year, rule, ruleIndex);
        return getIsDaylightSavings(adjustedTime, rule, daylightTime);
    }

    static bool isValidAdjustmentRuleOffset(scope const(ZoneOffset) baseUtcOffset, scope const(AdjustmentRule) rule) @nogc nothrow pure
    {
        const utcOffset = getUtcOffset(baseUtcOffset, rule);
        return utcOffset.isValid() == ErrorOp.none;
    }

    DateTimeZoneKind kind() const @nogc nothrow pure scope
    {
        return _id == localId
            ? DateTimeZoneKind.local
            : (_id == utcId || _id == utcId2 ? DateTimeZoneKind.utc : DateTimeZoneKind.unspecified);
    }

    size_t toHash() const @nogc nothrow pure scope
    {
        return hashOf(_id);
    }

    enum ValidatedTimeZoneError : ubyte
    {
        none,
        id,
        offsetRange,
        offsetTick,
        ruleDelta,
        ruleOrder,
    }

    static ValidatedTimeZoneError isValidTimeZoneInfo(string id, scope const(ZoneOffset) baseUtcOffset, scope const(AdjustmentRule)[] adjustmentRules) @nogc nothrow pure
    {
        if (id.length == 0)
            return ValidatedTimeZoneError.id;

        if (baseUtcOffset.isValid() != ErrorOp.none)
            return ValidatedTimeZoneError.offsetRange;

        if (baseUtcOffset.toTicks() % Tick.ticksPerMinute != 0)
            return ValidatedTimeZoneError.offsetTick;

        // "adjustmentRules" can either be null or a valid array of AdjustmentRule objects.
        // A valid array is one that does not contain any null elements and all elements
        // are sorted in chronological order
        if (adjustmentRules.length != 0)
        {
            foreach (i; 0..adjustmentRules.length)
            {
                if (!isValidAdjustmentRuleOffset(baseUtcOffset, adjustmentRules[i]))
                    return ValidatedTimeZoneError.ruleDelta;

                if (i > 0 && adjustmentRules[i].dateBegin <= adjustmentRules[i - 1].dateEnd)
                    return ValidatedTimeZoneError.ruleOrder;
            }
        }

        return ValidatedTimeZoneError.none;
    }

    static void utcTimeZoneInit(ref TimeZoneInfo utcTZ, string useId) @nogc nothrow pure
    {
        utcTZ._id = useId.length != 0 ? useId : utcId;
        utcTZ._displayName = utcDisplayName;
        utcTZ._standardName = utcStandardName;
        utcTZ._daylightName = utcStandardName;
        utcTZ._baseUtcOffset = ZoneOffset(0);
        utcTZ._supportsDaylightSavingTime = false;
    }

    static void validateTimeZoneInfo(string id, scope const(ZoneOffset) baseUtcOffset, scope const(AdjustmentRule)[] adjustmentRules) pure
    {
        final switch (isValidTimeZoneInfo(id, baseUtcOffset, adjustmentRules))
        {
            case ValidatedTimeZoneError.none:
                break;
            case ValidatedTimeZoneError.id:
                throw new TimeException("TimeZone.id is empty");
            case ValidatedTimeZoneError.offsetRange:
                throwOutOfRange!(ErrorPart.tick)(baseUtcOffset.toTicks());
                break;
            case ValidatedTimeZoneError.offsetTick:
                throw new TimeException("baseUtcOffset has seconds");
            case ValidatedTimeZoneError.ruleDelta:
                throw new TimeException("daylightDelta is invalid");
            case ValidatedTimeZoneError.ruleOrder:
                throw new TimeException("daylightDelta is out of chronological order");
        }
    }

    @property const(AdjustmentRule[]) adjustmentRules() const @nogc nothrow pure
    {
        return _adjustmentRules;
    }

    @property static TimeZoneInfo localTimeZone() nothrow
    {
        version(Windows)
            return localTimeZoneWindows(null);
        else version(Posix)
            return localTimeZonePosix(null);
        else
            static assert(0, "Unsupport system for " ~ __FUNCTION__);
    }

    @property static ref TimeZoneInfo localTimeZone(const(int) year) nothrow
    {
        static CacheTimeZoneInfo cacheLocal; // Thread local storage
        if (cacheLocal.needInit(year))
        {
            cacheLocal.timeZone = localTimeZone;
            cacheLocal.timeZoneYear = year;
        }
        return cacheLocal.timeZone;
    }

    @property static ref TimeZoneInfo utcTimeZone() @nogc nothrow
    {
        static TimeZoneInfo utcTZ; // Thread local storage
        if (utcTZ.needInit())
            utcTimeZoneInit(utcTZ, null);
        return utcTZ;
    }

    @property ZoneOffset baseUtcOffset() const @nogc nothrow pure scope
    {
        return _baseUtcOffset;
    }

    @property string daylightName() const @nogc nothrow pure
    {
        return _daylightName;
    }

    @property string displayName() const @nogc nothrow pure
    {
        return _displayName;
    }

    @property string id() const @nogc nothrow pure
    {
        return _id;
    }

    @property string standardName() const @nogc nothrow pure
    {
        return _standardName;
    }

    @property bool supportsDaylightSavingTime() const @nogc nothrow pure scope
    {
        return _supportsDaylightSavingTime;
    }

public:
    // constants for TimeZone.local and TimeZone.utc
    static immutable string localId = "Local";
    static immutable string utcId = "UTC";
    static immutable string utcDisplayName = "(UTC) Coordinated Universal Time";
    static immutable string utcStandardName = "Coordinated Universal Time";
    static immutable string utcId2 = "GMT";

package(pham.dtm):
    void addRule(AdjustmentRule rule) nothrow pure
    {
        _adjustmentRules ~= rule;
    }

    void addEquivalentZone(TimeZoneInfo zone) nothrow pure
    {
        _equivalentZones ~= zone;
    }

    bool needInit() const @nogc nothrow pure scope
    {
        return _id.length == 0;
    }

private:
    static bool checkIsDst(DateTime startTime, DateTime time, DateTime endTime,
        const(bool) ignoreYearAdjustment, scope const(AdjustmentRule) rule) @nogc nothrow pure
    {
        // NoDaylightTransitions AdjustmentRules should never get their year adjusted since they adjust the offset for the
        // entire time period - which may be for multiple years
        if (!ignoreYearAdjustment && !rule.noDaylightTransitions)
        {
            const int startTimeYear = startTime.year;
            const int endTimeYear = endTime.year;
            if (startTimeYear != endTimeYear)
            {
                const copyEndTime = endTime;
                const r = copyEndTime.tryAddYears(startTimeYear - endTimeYear, endTime);
                assert(r == ErrorOp.none);
            }

            const int timeYear = time.year;
            if (startTimeYear != timeYear)
            {
                const copyTime = time;
                const r = copyTime.tryAddYears(startTimeYear - timeYear, time);
                assert(r == ErrorOp.none);
            }
        }

        if (startTime > endTime)
        {
            // In southern hemisphere, the daylight saving time starts later in the year, and ends in the beginning of next year.
            // Note, the summer in the southern hemisphere begins late in the year.
            return time < endTime || time >= startTime;
        }
        else if (rule.noDaylightTransitions)
        {
            // In NoDaylightTransitions AdjustmentRules, the startTime is always before the endTime,
            // and both the start and end times are inclusive
            return time >= startTime && time <= endTime;
        }
        else
        {
            // In northern hemisphere, the daylight saving time starts in the middle of the year.
            return time >= startTime && time < endTime;
        }
    }

    int compareAdjustmentRuleToDateTime(scope const(AdjustmentRule) rule, scope const(AdjustmentRule) previousRule,
        scope const(DateTime) dateTime, scope const(DateTime) dateOnly, const(bool) dateTimeIsUtc) const @nogc nothrow pure scope
    {
        bool isAfterBegin;
        if (rule.dateBegin.kind == DateTimeZoneKind.utc)
        {
            const dateTimeToCompare = dateTimeIsUtc
                ? dateTime
                // use the previous rule to compute the dateTimeToCompare, since the time daylight savings "switches"
                // is based on the previous rule's offset
                : convertToDaylightUtc(dateTime, baseUtcOffset, previousRule);
            isAfterBegin = dateTimeToCompare >= rule.dateBegin;
        }
        else
        {
            // if the rule's dateStart is unspecified, then use the whole-date portion
            isAfterBegin = dateOnly >= rule.dateBegin;
        }
        if (!isAfterBegin)
            return 1;

        bool isBeforeEnd;
        if (rule.dateEnd.kind == DateTimeZoneKind.utc)
        {
            const dateTimeToCompare = dateTimeIsUtc
                ? dateTime
                : convertToDaylightUtc(dateTime, baseUtcOffset, rule);
            isBeforeEnd = dateTimeToCompare <= rule.dateEnd;
        }
        else
        {
            // if the rule's dateEnd is Unspecified, then use the whole-date portion
            isBeforeEnd = dateOnly <= rule.dateEnd;
        }
        return isBeforeEnd ? 0 : -1;
    }

    static DateTime convertFromDaylightUtc(scope const(DateTime) dateTime, scope const(ZoneOffset) baseUtcOffset,
        scope const(AdjustmentRule) rule) @nogc nothrow pure
    {
        const offsetTicks = baseUtcOffset.toTicks() + rule.daylightDelta.toTicks();
        const long ticks = dateTime.sticks + offsetTicks;
        return ticks > DateTime.maxTicks
            ? DateTime.max
            : (ticks < DateTime.minTicks
                ? DateTime.min
                : DateTime(TickData.createDateTime(ticks, dateTime.kind)));
    }

    static DateTime convertToDaylightUtc(scope const(DateTime) dateTime, scope const(ZoneOffset) baseUtcOffset,
        scope const(AdjustmentRule) rule) @nogc nothrow pure
    {
        const offsetTicks = baseUtcOffset.toTicks() + rule.daylightDelta.toTicks();
        const long ticks = dateTime.sticks - offsetTicks;
        return ticks > DateTime.maxTicks
            ? DateTime.max
            : (ticks < DateTime.minTicks
                ? DateTime.min
                : DateTime(TickData.createDateTime(ticks, dateTime.kind)));
    }

    static DateTime convertUtcToTimeZone(long ticks, scope const(TimeZoneInfo) destinationTimeZone) @nogc nothrow pure
    {
        // used to calculate the UTC offset in the destinationTimeZone
        const(DateTime) utcConverted = ticks > DateTime.maxTicks
            ? DateTime.max
            : (ticks < DateTime.minTicks
                ? DateTime.min
                : DateTime(TickData.createDateTime(ticks, DateTimeZoneKind.unspecified)));

        // verify the time is between MinValue and MaxValue in the new time zone
        bool isDaylightSavings = void;
        const offset = destinationTimeZone.getUtcOffsetFromUtc(utcConverted, isDaylightSavings);
        ticks += offset.toTicks();

        return ticks > DateTime.maxTicks
            ? DateTime.max
            : (ticks < DateTime.minTicks
                ? DateTime.min
                : DateTime(TickData.createDateTime(ticks, DateTimeZoneKind.unspecified)));
    }

    DaylightTimeInfo getDaylightTime(const(int) year, scope const(AdjustmentRule) rule, const(ptrdiff_t) ruleIndex) const @nogc nothrow pure scope
    {
        DaylightTimeInfo result;
        result.delta = rule.daylightDelta;
        if (rule.noDaylightTransitions)
        {
            // NoDaylightTransitions rules don't use DaylightTransition Start and End, instead
            // the DateStart and DateEnd are UTC times that represent when daylight savings time changes.
            // Convert the UTC times into adjusted time zone times.

            // use the previous rule to calculate the startTime, since the DST change happens w.r.t. the previous rule
            const previousRule = ruleIndex > 0 ? _adjustmentRules[ruleIndex - 1] : rule;
            result.beginTime = convertFromDaylightUtc(rule.dateBegin, baseUtcOffset, previousRule);
            result.endTime = convertFromDaylightUtc(rule.dateEnd, baseUtcOffset, rule);
        }
        else
        {
            result.beginTime = transitionTimeToDateTime(year, rule.daylightTransitionBegin);
            result.endTime = transitionTimeToDateTime(year, rule.daylightTransitionEnd);
        }
        return result;
    }

    ZoneOffset getDaylightSavingsBeginOffsetFromUtc(scope const(ZoneOffset) baseUtcOffset,
        scope const(AdjustmentRule) rule, const(ptrdiff_t) ruleIndex) const @nogc nothrow pure scope
    {
        if (rule.noDaylightTransitions)
        {
            // use the previous rule to calculate the startTime, since the DST change happens w.r.t. the previous rule
            const previousRule = ruleIndex > 0 ? _adjustmentRules[ruleIndex - 1] : rule;
            return ZoneOffset(baseUtcOffset.toMinutes() + previousRule.baseUtcOffsetDelta.toMinutes() + previousRule.daylightDelta.toMinutes());
        }
        else
        {
            return ZoneOffset(baseUtcOffset.toMinutes() + rule.baseUtcOffsetDelta.toMinutes() + rule.standardDelta.toMinutes());
        }
    }

    ZoneOffset getDaylightSavingsEndOffsetFromUtc(scope const(ZoneOffset) baseUtcOffset,
        scope const(AdjustmentRule) rule, const(ptrdiff_t) ruleIndex) const @nogc nothrow pure scope
    {
        // NOTE: even rule.noDaylightTransitions rules use this logic since DST ends w.r.t. the current rule
        return ZoneOffset(baseUtcOffset.toMinutes() + rule.baseUtcOffsetDelta.toMinutes() + rule.daylightDelta.toMinutes()); /* FUTURE: + rule.StandardDelta; */
    }

    static bool getIsDaylightSavings(scope const(DateTime) dateTime, scope const(AdjustmentRule) rule, scope const(DaylightTimeInfo) daylightTime) @nogc nothrow pure
    {
        DateTime startTime = void, endTime = void;
        if (dateTime.kind == DateTimeZoneKind.local)
        {
            // startTime and endTime represent the period from either the start of
            // DST to the end and ***includes*** the potentially overlapped times
            startTime = rule.isBeginDateMarkerForBeginningOfYear()
                ? DateTime(daylightTime.beginTime.year, 1, 1, 0, 0, 0)
                : daylightTime.beginTime.addTicksClamp(daylightTime.delta.toTicks());

            endTime = rule.isEndDateMarkerForEndOfYear()
                ? DateTime(daylightTime.endTime.year + 1, 1, 1, 0, 0, 0).addTicksClamp(-1)
                : daylightTime.endTime;
        }
        else
        {
            // startTime and endTime represent the period from either the start of DST to the end and
            // ***does not include*** the potentially overlapped times
            //
            //         -=-=-=-=-=- Pacific Standard Time -=-=-=-=-=-=-
            //    April 2, 2006                            October 29, 2006
            // 2AM            3AM                        1AM              2AM
            // |      +1 hr     |                        |       -1 hr      |
            // | <invalid time> |                        | <ambiguous time> |
            //                  [========== DST ========>)
            //
            //        -=-=-=-=-=- Some Weird Time Zone -=-=-=-=-=-=-
            //    April 2, 2006                          October 29, 2006
            // 1AM              2AM                    2AM              3AM
            // |      -1 hr       |                      |       +1 hr      |
            // | <ambiguous time> |                      |  <invalid time>  |
            //                    [======== DST ========>)
            //
            const bool invalidAtStart = rule.daylightDelta.toMinutes() > 0;

            startTime = rule.isBeginDateMarkerForBeginningOfYear()
                ? DateTime(daylightTime.beginTime.year, 1, 1, 0, 0, 0)
                : daylightTime.beginTime.addTicksClamp(invalidAtStart ? rule.daylightDelta.toTicks() : rule.standardDelta.toTicks());

            endTime = rule.isEndDateMarkerForEndOfYear()
                ? DateTime(daylightTime.endTime.year + 1, 1, 1, 0, 0, 0).addTicksClamp(-1)
                : daylightTime.endTime.addTicksClamp(invalidAtStart ? -rule.daylightDelta.toTicks() : 0);
        }

        return checkIsDst(startTime, dateTime, endTime, false, rule);
    }

    bool getIsDaylightSavingsFromUtc(scope const(DateTime) utcDateTime, const(int) year, scope const(ZoneOffset) utc,
        scope const(AdjustmentRule) rule, const(ptrdiff_t) ruleIndex) const @nogc nothrow pure scope
    {
        // Get the daylight changes for the year of the specified time.
        const daylightTime = getDaylightTime(year, rule, ruleIndex);

        // The start and end times represent the range of universal times that are in DST for that year.
        // Within that there is an ambiguous hour, usually right at the end, but at the beginning in
        // the unusual case of a negative daylight savings delta.
        // We need to handle the case if the current rule has daylight saving end by the end of year. If so, we need to check if next year starts with daylight saving on
        // and get the actual daylight saving end time. Here is example for such case:
        //      Converting the UTC datetime "12/31/2011 8:00:00 PM" to "(UTC+03:00) Moscow, St. Petersburg, Volgograd (RTZ 2)" zone.
        //      In 2011 the daylight saving will go through the end of the year. If we use the end of 2011 as the daylight saving end,
        //      that will fail the conversion because the UTC time +4 hours (3 hours for the zone UTC offset and 1 hour for daylight saving) will move us to the next year "1/1/2012 12:00 AM",
        //      checking against the end of 2011 will tell we are not in daylight saving which is wrong and the conversion will be off by one hour.
        // Note we handle the similar case when rule year start with daylight saving and previous year end with daylight saving.

        bool ignoreYearAdjustment = false;
        const dstStartOffset = getDaylightSavingsBeginOffsetFromUtc(utc, rule, ruleIndex);
        DateTime startTime;
        if (rule.isBeginDateMarkerForBeginningOfYear() && daylightTime.beginTime.year > DateTime.minYear)
        {
            ptrdiff_t previousYearRuleIndex;
            AdjustmentRule previousYearRule;
            const isPreviousYearRule = findAdjustmentRule(DateTime(daylightTime.beginTime.year - 1, 12, 31), false, previousYearRule, previousYearRuleIndex);
            if (isPreviousYearRule && previousYearRule.isEndDateMarkerForEndOfYear())
            {
                const previousDaylightTime = getDaylightTime(daylightTime.beginTime.year - 1, previousYearRule, previousYearRuleIndex);
                startTime = previousDaylightTime.beginTime.addTicksClamp(-(utc.toTicks() + previousYearRule.baseUtcOffsetDelta.toTicks()));
                ignoreYearAdjustment = true;
            }
            else
            {
                startTime = DateTime(daylightTime.beginTime.year, 1, 1, 0, 0, 0).addTicksClamp(-dstStartOffset.toTicks());
            }
        }
        else
        {
            startTime = daylightTime.beginTime.addTicksClamp(-dstStartOffset.toTicks());
        }

        const dstEndOffset = getDaylightSavingsEndOffsetFromUtc(utc, rule, ruleIndex);
        DateTime endTime;
        if (rule.isEndDateMarkerForEndOfYear() && daylightTime.endTime.year < DateTime.maxYear)
        {
            ptrdiff_t nextYearRuleIndex;
            AdjustmentRule nextYearRule;
            const isNextYearRule = findAdjustmentRule(DateTime(daylightTime.endTime.year + 1, 1, 1), false, nextYearRule, nextYearRuleIndex);
            if (isNextYearRule && nextYearRule.isBeginDateMarkerForBeginningOfYear())
            {
                if (nextYearRule.isEndDateMarkerForEndOfYear())
                {
                    // next year end with daylight saving on too
                    endTime = DateTime(daylightTime.endTime.year + 1, 12, 31).addTicksClamp(-(utc.toTicks() + nextYearRule.baseUtcOffsetDelta.toTicks() + nextYearRule.daylightDelta.toTicks()));
                }
                else
                {
                    const nextdaylightTime = getDaylightTime(daylightTime.endTime.year + 1, nextYearRule, nextYearRuleIndex);
                    endTime = nextdaylightTime.endTime.addTicksClamp(-(utc.toTicks() + nextYearRule.baseUtcOffsetDelta.toTicks() + nextYearRule.daylightDelta.toTicks()));
                }
                ignoreYearAdjustment = true;
            }
            else
            {
                endTime = DateTime(daylightTime.endTime.year + 1, 1, 1, 0, 0, 0).addTicksClamp(-1).addTicksClamp(-dstEndOffset.toTicks());
            }
        }
        else
        {
            endTime = daylightTime.endTime.addTicksClamp(-dstEndOffset.toTicks());
        }

        return checkIsDst(startTime, utcDateTime, endTime, ignoreYearAdjustment, rule);
    }

    static ZoneOffset getUtcOffset(scope const(ZoneOffset) baseUtcOffset, scope const(AdjustmentRule) rule) @nogc nothrow pure
    {
        return ZoneOffset(baseUtcOffset.toMinutes()
            + rule.baseUtcOffsetDelta.toMinutes()
            + (rule.hasDaylightSaving ? rule.daylightDelta.toMinutes() : rule.standardDelta.toMinutes()));
    }

    static DateTime transitionTimeToDateTime(const(int) year, scope const(TransitionTime) transitionTime) @nogc nothrow pure
    {
        DateTime result;
        const timeOfDay = transitionTime.timeOfDay.time;

        int resultWeekDelta() @nogc nothrow pure
        {
            const int delta = cast(int)(transitionTime.dayOfWeek) - cast(int)(result.dayOfWeek);
            return delta < 0 ? delta + 7 : delta;
        }

        if (transitionTime.isFixedDateRule)
        {
            // create a DateTime from the passed in year and the properties on the transitionTime

            int day = transitionTime.day;
            // if the day is out of range for the month then use the last day of the month
            if (day > 28)
            {
                const daysInMonth = DateTime.daysInMonth(year, transitionTime.month);
                if (day > daysInMonth)
                    day = daysInMonth;
            }

            result = Date(year, transitionTime.month, day) + timeOfDay;
        }
        else
        {
            if (transitionTime.week <= 4)
            {
                //
                // Get the (transitionTime.Week)th Sunday.
                //
                result = Date(year, transitionTime.month, 1) + timeOfDay;

                int delta = resultWeekDelta();
                delta += 7 * (transitionTime.week - 1);
                if (delta > 0)
                {
                    const copyResult = result;
                    const r = copyResult.tryAddDays(delta, result);
                    assert(r == ErrorOp.none);
                }
            }
            else
            {
                //
                // If TransitionWeek is greater than 4, we will get the last week.
                //
                const int daysInMonth = DateTime.daysInMonth(year, transitionTime.month);
                result = Date(year, transitionTime.month, daysInMonth) + timeOfDay;

                // This is the day of week for the last day of the month.
                const int delta = resultWeekDelta();
                if (delta > 0)
                {
                    const copyResult = result;
                    const r = copyResult.tryAddDays(-delta, result);
                    assert(r == ErrorOp.none);
                }
            }
        }
        return result;
    }

private:
    // used by GetUtcOffsetFromUtc (DateTime.Now, DateTime.ToLocalTime) for max/min whole-day range checks
    enum DateTime s_maxDateOnly = DateTime(9999, 12, 31);
    enum DateTime s_minDateOnly = DateTime(1, 1, 2);

    string _id;
    string _displayName;
    string _standardName;
    string _daylightName;
    AdjustmentRule[] _adjustmentRules;
    // As we support IANA and Windows Ids, it is possible we create equivalent zone objects which differ only in the Ids.
    TimeZoneInfo[] _equivalentZones;
    ZoneOffset _baseUtcOffset;
    bool _supportsDaylightSavingTime;
}

struct TransitionTime
{
@safe:

public:
    this(in DateTime timeOfDay, int month, int week, int day, DayOfWeek dayOfWeek, bool isFixedDateRule) @nogc nothrow pure
    in
    {
        assert(isValidTransitionTime(timeOfDay, month, week, day, dayOfWeek) == ErrorPart.none);
    }
    do
    {
        this._timeOfDay = timeOfDay;
        this._month = cast(ubyte)month;
        this._week = cast(ubyte)week;
        this._day = cast(ubyte)day;
        this._dayOfWeek = dayOfWeek;
        this._isFixedDateRule = isFixedDateRule;
    }

    bool opEquals(scope const(TransitionTime) rhs) const @nogc nothrow pure scope
    {
        return _isFixedDateRule == rhs._isFixedDateRule
            && _timeOfDay == rhs._timeOfDay
            && _month == rhs._month
            && (rhs._isFixedDateRule
                ? _day == rhs._day
                : (_week == rhs._week && _dayOfWeek == rhs._dayOfWeek));
    }

    static TransitionTime createFixedDateRule(in DateTime timeOfDay, int month, int day) @nogc nothrow pure
    in
    {
        assert(isValidTransitionTime(timeOfDay, month, 1, day, DayOfWeek.sunday) == ErrorPart.none);
    }
    do
    {
        enum isFixedDateRule = true;
        return TransitionTime(timeOfDay, month, 1, day, DayOfWeek.sunday, isFixedDateRule);
    }

    static TransitionTime createFloatingDateRule(in DateTime timeOfDay, int month, int week, DayOfWeek dayOfWeek) @nogc nothrow pure
    in
    {
        assert(isValidTransitionTime(timeOfDay, month, week, 1, dayOfWeek) == ErrorPart.none);
    }
    do
    {
        enum isFixedDateRule = false;
        return TransitionTime(timeOfDay, month, week, 1, dayOfWeek, isFixedDateRule);
    }

    static ErrorPart isValidTransitionTime(scope const(DateTime) timeOfDay, int month, int week, int day, DayOfWeek dayOfWeek) @nogc nothrow pure
    {
        // Month range 1-12
        if (DateTime.isValidMonth(month) != ErrorOp.none)
            return ErrorPart.month;

        // Day range 1-31
        if (day < 1 || day > 31)
            return ErrorPart.day;

        // Week range 1-5
        if (week < 1 || week > 5)
            return ErrorPart.week;

        if (timeOfDay.kind != DateTimeZoneKind.unspecified)
            return ErrorPart.kind;

        int timeOfDayYear = void, timeOfDayMonth = void, timeOfDayDay = void;
        timeOfDay.getDate(timeOfDayYear, timeOfDayMonth, timeOfDayDay);
        if (timeOfDayYear != 1 || timeOfDayMonth != 1 || timeOfDayDay != 1 || (timeOfDay.sticks % Tick.ticksPerMillisecond != 0))
            return ErrorPart.tick;

        return ErrorPart.none;
    }

    static void validateTransitionTime(scope const(DateTime) timeOfDay, int month, int week, int day, DayOfWeek dayOfWeek) pure
    {
        const e = isValidTransitionTime(timeOfDay, month, week, day, dayOfWeek);
        if (e == ErrorPart.none)
            return;
        else if (e == ErrorPart.kind)
            throw new TimeException("timeOfDay.kind is not DateTimeZoneKind.unspecified");
        else if (e == ErrorPart.tick)
            throw new TimeException("timeOfDay has tick precision");
        else if (e == ErrorPart.month)
            throwOutOfRange!(ErrorPart.month)(month);
        else if (e == ErrorPart.day)
            throwOutOfRange!(ErrorPart.day)(day);
        else if (e == ErrorPart.week)
            throwOutOfRange!(ErrorPart.week)(week);
        else
            assert(0);
    }

    /**
     * The day on which the time change occurs
     */
    @property int day() const @nogc nothrow pure
    {
        return _day;
    }

    /**
     * The day of the week on which the time change occurs
     */
    @property DayOfWeek dayOfWeek() const @nogc nothrow pure
    {
        return _dayOfWeek;
    }

    /**
     * Returns a value indicating whether the time change occurs at a fixed date and time (such as November 30)
     * or a floating date and time (such as the last Sunday of November)
     */
    @property bool isFixedDateRule() const @nogc nothrow pure
    {
        return _isFixedDateRule;
    }

    /**
     * The month of the year on which the time change occurs
     */
    @property int month() const @nogc nothrow pure
    {
        return _month;
    }

    /**
     * The time of day at which the time change occurs
     */
    @property DateTime timeOfDay() const @nogc nothrow pure
    {
        return _timeOfDay;
    }

    /**
     * The week of the month in which the time change occurs
     */
    @property int week() const @nogc nothrow pure
    {
        return _week;
    }

private:
    DateTime _timeOfDay;
    ubyte _month;
    ubyte _week;
    ubyte _day;
    DayOfWeek _dayOfWeek;
    bool _isFixedDateRule;
}

struct ZoneOffset
{
nothrow @safe:

    this(const(int) hour, const(int) minute) @nogc pure
    in
    {
        assert(isValid(hour, minute) == ErrorOp.none);
    }
    do
    {
        this.hour = cast(byte)hour;
        this.minute = cast(byte)minute;
    }

    this(const(int) minutes) @nogc pure
    in
    {
        assert(isValid(minutes) == ErrorOp.none);
    }
    do
    {
        this.hour = cast(byte)(minutes / Tick.minutesPerHour);
        this.minute = this.hour == 0 ? cast(byte)(minutes % Tick.minutesPerHour) : cast(byte)(abs(minutes) % Tick.minutesPerHour);
    }

    this(scope const(Duration) minutes) @nogc pure
    {
        this(cast(int)minutes.total!"minutes"());
    }

    ref typeof(this) opAssign(const(int) minutes) @nogc pure return
    in
    {
        assert(isValid(minutes) == ErrorOp.none);
    }
    do
    {
        this.hour = cast(byte)(minutes / Tick.minutesPerHour);
        this.minute = this.hour == 0 ? cast(byte)(minutes % Tick.minutesPerHour) : cast(byte)(abs(minutes) % Tick.minutesPerHour);
        return this;
    }

    ref typeof(this) opAssign(scope const(Duration) minutes) @nogc pure return
    {
        return opAssign(cast(int)minutes.total!"minutes"());
    }

    bool opCast(C: bool)() const @nogc
    {
        return hasOffset;
    }

    int opCmp(scope const(ZoneOffset) rhs) const @nogc pure scope
    {
        const result = cmp(this.hour, rhs.hour);
        return result == 0 ? cmp(this.minute, rhs.minute) : result;
    }

    bool opEquals(scope const(ZoneOffset) rhs) const @nogc pure scope
    {
        return this.hour == rhs.hour && this.minute == rhs.minute;
    }

    pragma(inline, true)
    static ZoneOffset fromSystemBias(const(int) biasMinute) pure
    {
        return biasMinute != 0 ? ZoneOffset(-biasMinute) : ZoneOffset(0);
    }

    pragma(inline, true)
    ErrorOp isValid() const @nogc pure scope
    {
        return ZoneOffset.isValid(this.hour, this.minute);
    }
    
    static ErrorOp isValid(const(int) hour, const(int) minute) @nogc pure
    {
        return isValid(toMinutes(hour, minute));
    }

    static ErrorOp isValid(const(int) minutes) @nogc pure
    {
        return minutes < minOffsetInMinutes
            ? ErrorOp.underflow
            : (minutes > maxOffsetInMinutes ? ErrorOp.overflow : ErrorOp.none);
    }

    void reset() @nogc pure
    {
        hour = minute = 0;
    }

    Duration toDuration() const @nogc pure scope
    {
        return dur!"minutes"(toMinutes());
    }

    pragma(inline, true)
    size_t toHash() const @nogc pure scope
    {
        return (cast(ubyte)hour << 8) || cast(ubyte)minute;
    }

    int toMinutes() const @nogc pure scope
    {
        return toMinutes(hour, minute);
    }

    pragma(inline, true)
    static int toMinutes(const(int) hour, const(int) minute) @nogc pure
    /* Skip pre-condition because using by isValid
    in
    {
        assert(hour > -Tick.hoursPerDay && hour < Tick.hoursPerDay);
        assert(minute > -Tick.minutesPerHour && minute < Tick.minutesPerHour);
        assert(minute >= 0 || hour != 0); // minute cann't be negative if hour != 0
    }
    do
    */
    {
        return hour < 0 || minute < 0
            ? -(abs(hour)*Tick.minutesPerHour + abs(minute))
            : (hour*Tick.minutesPerHour + minute);
    }

    string toString() const scope
    {
        import pham.utl.utl_array_append : Appender;

        auto buffer = Appender!string(10);
        return toString(buffer).data;
    }

    ref Writer toString(Writer)(return ref Writer sink) const scope
    {
        import pham.utl.utl_object : nToString = toString;

        sink.put(hour < 0 || minute < 0 ? '-' : '+');
        sink.nToString(abs(hour), 2);
        sink.put(':');
        sink.nToString(abs(minute), 2);
        return sink;
    }

    pragma(inline, true)
    long toTicks() const @nogc pure scope
    {
        return toMinutes() * Tick.ticksPerMinute;
    }
    
    pragma(inline, true)
    @property bool hasOffset() const @nogc pure scope
    {
        return hour != 0 || minute != 0;
    }
    
    static @property ZoneOffset max() @nogc pure
    {
        return ZoneOffset(maxOffsetInHours - 1, Tick.minutesPerHour - 1);
    }

    static @property ZoneOffset min() @nogc pure
    {
        return ZoneOffset(minOffsetInHours + 1, Tick.minutesPerHour - 1);
    }

    byte hour;
    byte minute;

private:
    // https://en.wikipedia.org/wiki/Time_zone
    // +/-1 for day light saving
    enum maxOffsetInHours = 14 + 1;    
    enum maxOffsetInMinutes = toMinutes(maxOffsetInHours - 1, Tick.minutesPerHour - 1);
    //enum minOffsetInHours = -14 - 1;
    enum minOffsetInHours = -23; // -23 = see comment in isValidAdjustmentRule
    enum minOffsetInMinutes = toMinutes(minOffsetInHours + 1, Tick.minutesPerHour - 1);
}

package(pham.dtm):

struct CacheTimeZoneInfo
{
@safe:

    bool needInit(const(int) year) const @nogc nothrow pure scope
    {
        return timeZoneYear != year || timeZone.needInit();
    }

    TimeZoneInfo timeZone;
    int timeZoneYear;
}

struct DaylightTimeInfo
{
@safe:

    DateTime beginTime;
    DateTime endTime;
    ZoneOffset delta;
}

TimeZoneInfo notFoundLocalTimeZone(string useId) @nogc nothrow pure
{
    TimeZoneInfo result;
    result._id = useId.length != 0 ? useId : TimeZoneInfo.localId;
    result._displayName = TimeZoneInfo.localId;
    result._standardName = TimeZoneInfo.localId;
    result._daylightName = TimeZoneInfo.localId;
    result._baseUtcOffset = ZoneOffset.init;
    result._supportsDaylightSavingTime = false;
    return result;
}


private:

version(Windows)
{
    import core.sys.windows.winbase : GetTimeZoneInformation, SYSTEMTIME, TIME_ZONE_INFORMATION, TIME_ZONE_ID_INVALID;
    import core.sys.windows.winnt : WCHAR;

    TimeZoneInfo localTimeZoneWindows(string useId) nothrow @trusted
    {
        scope (failure) assert(0, "Assume nothrow failed");

        static string toName(scope const(WCHAR)[] systemName) nothrow pure @safe
        {
            scope (failure) assert(0, "Assume nothrow failed");

            auto result = systemName.to!string();
            auto len = result.length;
            while (len && result[len - 1] <= ' ')
                len--;
            return result[0..len];
        }

        TIME_ZONE_INFORMATION tzInfo;
        if (GetTimeZoneInformation(&tzInfo) != TIME_ZONE_ID_INVALID)
        {
            debug(debug_pham_dtm_dtm_time_zone) debug writeln(__FUNCTION__, "(tzInfo.Bias=", tzInfo.Bias, ", tzInfo.DaylightBias=",
                tzInfo.DaylightBias, ", tzInfo.StandardBias=", tzInfo.StandardBias, ")");

            const standardName = toName(tzInfo.StandardName);
            const daylightName = toName(tzInfo.DaylightName);
            TimeZoneInfo result;
            result._id = useId.length != 0 ? useId : (standardName.length != 0 ? standardName : TimeZoneInfo.localId);
            result._displayName = standardName;
            result._standardName = standardName;
            result._daylightName = daylightName;
            result._baseUtcOffset = ZoneOffset.fromSystemBias(tzInfo.Bias);

            TransitionTime transitionBegin = void, transitionEnd = void;
            result._supportsDaylightSavingTime = isSupportsDaylightSavingTime(tzInfo, transitionBegin, transitionEnd);
            if (result._supportsDaylightSavingTime)
            {
                auto adjustmentRule = AdjustmentRule(DateTime.min.dateOnly,
                    DateTime.max.dateOnly,
                    ZoneOffset.fromSystemBias(0), //Tick.durationFromSystemBias(tzInfo.Bias - tzInfo.Bias),
                    ZoneOffset.fromSystemBias(tzInfo.DaylightBias),
                    ZoneOffset.fromSystemBias(tzInfo.StandardBias),
                    transitionBegin,
                    transitionEnd,
                    false /* noDaylightTransitions */);
                result._adjustmentRules = [adjustmentRule];
            }
            return result;
        }
        else
            return notFoundLocalTimeZone(useId);
    }

    TransitionTime createTransitionTime(scope const(SYSTEMTIME) systemTime) @nogc nothrow pure
    {
        return systemTime.wYear == 0
            ? TransitionTime.createFloatingDateRule(
                DateTime(1 /* year */, 1 /* month */, 1 /* day */,
                    systemTime.wHour, systemTime.wMinute, systemTime.wSecond, systemTime.wMilliseconds),
                systemTime.wMonth,
                systemTime.wDay,
                cast(DayOfWeek)systemTime.wDayOfWeek /* Week 1-5 */)
            : TransitionTime.createFixedDateRule(
                DateTime(1 /* year */, 1 /* month */, 1 /* day */,
                    systemTime.wHour, systemTime.wMinute, systemTime.wSecond, systemTime.wMilliseconds),
                systemTime.wMonth,
                systemTime.wDay);
    }

    bool isSupportsDaylightSavingTime(scope const(TIME_ZONE_INFORMATION) tzInfo,
        out TransitionTime transitionBegin, out TransitionTime transitionEnd) @nogc nothrow pure
    {
        transitionBegin = tzInfo.DaylightDate.wMonth == 0 ? TransitionTime.init : createTransitionTime(tzInfo.DaylightDate);
        transitionEnd = tzInfo.StandardDate.wMonth == 0 ? TransitionTime.init : createTransitionTime(tzInfo.StandardDate);
        return tzInfo.DaylightDate.wMonth != 0 && !(transitionBegin == transitionEnd);
    }
}
else version(Posix)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.file : dirEntries, exists, read, readLink, SpanMode;
    import std.process : environment;
    import std.path : absolutePath, dirName;

    //immutable string ZoneTabFileName = "zone.tab";

    TimeZoneInfo localTimeZonePosix(string useId) nothrow
    {
        ubyte[] rawData = void;
        string id = void;
        if (tryGetLocalTzFile(rawData, id))
        {
            TimeZoneInfo result = void;
            if (tryGetTimeZoneFromTzData(rawData, id, result, useId))
                return result;
        }
        return notFoundLocalTimeZone(useId);
    }

    string findTimeZoneId(string tzPath, scope const(ubyte)[] rawData)
    {
        const string localtimeFilePath = tzPath ~ "localtime";
        const string posixRulesFilePath = tzPath ~ "posixrules";
        try
        {
            foreach (DirEntry e; dirEntries(tzPath, SpanMode.shallow))
            {
                // skip the localtime and posixrules file, since they won't give us the correct id
                if (!e.isFile || e.name == localtimeFilePath || e.name == posixRulesFilePath)
                    continue;

                if (rawData == cast(ubyte[])read(e.name))
                {
                    string result = e.name;
                    return result.startsWith(tzPath) ? result[tzPath.length..$] : result;
                }
            }
        }
        catch (Exception)
        {}
        return TimeZoneInfo.localId;
    }

    string findTimeZoneIdUsingReadLink(string tzPath, string tzFilePath)
    {
        string symlinkPath = readLink(tzFilePath);
        if (symlinkPath.length != 0)
        {
            // symlinkPath can be relative path, use Path to get the full absolute path.
            symlinkPath = absolutePath(symlinkPath, dirName(tzFilePath));
            if (symlinkPath.startsWith(tzPath))
                return symlinkPath[tzPath.length..$];
        }
        return null;
    }

    string getTzEnvironmentVariable()
    {
        static immutable string timeZoneEnvironmentVariable = "TZ";

        string result = environment.get(timeZoneEnvironmentVariable);
        // strip off the ':' prefix
        if (result.length != 0 && result[0] == ':')
            return result[1..$];
        else
            return result;
    }

    string getTzPath()
    {
        static immutable string defaultTimeZoneDirectory = "/usr/share/zoneinfo/";
        static immutable string timeZoneDirectoryEnvironmentVariable = "TZDIR";

        auto result = environment.get(timeZoneDirectoryEnvironmentVariable);
        if (result.length == 0)
            return defaultTimeZoneDirectory;
        else if (result[$ - 1] == '/')
            return result;
        else
            return result ~ "/";
    }

    bool isUtcId(scope const(char)[] id) @nogc nothrow pure
    {
        static immutable utcIds = ["Etc/UTC", "Etc/UCT", "Etc/Universal", "Etc/Zulu", "UCT", "UTC", "Universal", "Zulu"];

        return canFind(utcIds, id);
    }

    bool tryGetLocalTzFile(out ubyte[] rawData, out string id)
    {
        bool notFound() @nogc nothrow
        {
            rawData = null;
            id = null;
            return false;
        }

        id = null;
        const string tzVariable = getTzEnvironmentVariable();
        const string tzPath = getTzPath();

        // If the env var is null, use the localtime file
        if (tzVariable.length == 0)
        {
            if (tryLoadTzFile(tzPath, "/etc/localtime", rawData, id))
                return true;
            if (tryLoadTzFile(tzPath, tzPath ~ "localtime", rawData, id))
                return true;
            return notFound();
        }

        // Otherwise, use the path from the env var.  If it's not absolute, make it relative
            // to the system timezone directory
        string tzFilePath;
        if (tzVariable[0] != '/')
        {
            id = tzVariable;
            tzFilePath = tzPath ~ tzVariable;
        }
        else
        {
            tzFilePath = tzVariable;
        }
        if (tryLoadTzFile(tzPath, tzFilePath, rawData, id))
            return true;
        else
            return notFound();
    }

    bool tryGetTimeZoneFromTzData(ubyte[] rawData, string id, out TimeZoneInfo timeZone, string useId)
    {
        if (isUtcId(id))
        {
            TimeZoneInfo.utcTimeZoneInit(timeZone, useId.length != 0 ? useId : id);
            return true;
        }

        /* TODO
        try
        {
            return new TimeZoneInfo(rawData, id, dstDisabled: false); // create a TimeZoneInfo instance from the TZif data w/ DST support
        }
        catch (ArgumentException) { }
        catch (InvalidTimeZoneException) { }

        try
        {
            return new TimeZoneInfo(rawData, id, dstDisabled: true); // create a TimeZoneInfo instance from the TZif data w/o DST support
        }
        catch (ArgumentException) { }
        catch (InvalidTimeZoneException) { }
        */
    }

    bool tryLoadTzFile(string tzPath, string tzFilePath, ref ubyte[] rawData, ref string id)
    {
        if (!exists(tzFilePath))
            return false;

        try
        {
            rawData = cast(ubyte[])read(tzFilePath);
            if (id.length == 0)
            {
                id = findTimeZoneIdUsingReadLink(tzPath, tzFilePath);
                if (id.length == 0 && rawData.length != 0)
                    id = findTimeZoneId(tzPath, rawData);
            }
            return rawData.length != 0;
        }
        catch (Exception)
        {}
        return false;
    }

    // Converts an array of bytes into an int
    // always using standard byte order (Big Endian) per TZif file standard
    int TZif_ToInt32(scope const(ubyte)[] value, size_t beginIndex)
    {
        //todo => BinaryPrimitives.ReadInt32BigEndian(value.AsSpan(beginIndex));
    }

    // Converts an array of bytes into a long
    // always using standard byte order (Big Endian) per TZif file standard
    long TZif_ToInt64(scope const(ubyte)[] value, size_t beginIndex)
    {
        //todo => BinaryPrimitives.ReadInt64BigEndian(value.AsSpan(beginIndex));
    }

    struct TZifType
    {
        enum minLength = 6;

        Duration utcOffset;
        bool isDst;
        ubyte abbreviationIndex;

        this(scope const(ubyte)[] data, size_t index)
        in
        {
            assert(data.length >= index + minLength);
        }
        do
        {
            this.utcOffset = dur!"seconds"(TZif_ToInt32(data, index + 0));
            this.isDst = data[index + 4] != 0;
            this.abbreviationIndex = data[index + 5];
        }
    }

    struct TZifHead
    {
        enum minDatalength = 44;

        uint magic; // TZ_MAGIC "TZif"
        TZVersion version_; // 1 byte for a \0 or 2 or 3
        //byte[15] reserved; // reserved for future use
        uint isGmtCount; // number of transition time flags
        uint isStdCount; // number of transition time flags
        uint leapCount; // number of leap seconds
        uint timeCount; // number of transition times
        uint typeCount; // number of local time types
        uint charCount; // number of abbreviated characters

        this(scope const(ubyte)[] data, size_t index)
        in
        {
            assert(data.length >= index + minDatalength);
        }
        do
        {
            this.magic = cast(uint)TZif_ToInt32(data, index + 0);

            // 0x545A6966 = {0x54, 0x5A, 0x69, 0x66} = "TZif"
            if (this.magic != 0x545A6966)
                assert(0);

            const byte version_ = data[index + 4];
            this.version_ = version_ == '2'
                ? TZVersion.v2
                : (version_ == '3' ? TZVersion.v3 : TZVersion.v1);

            // skip the 15 byte reserved field

            // don't use the BitConverter class which parses data
            // based on the Endianess of the machine architecture.
            // this data is expected to always be in "standard byte order",
            // regardless of the machine it is being processed on.

            this.isGmtCount = cast(uint)TZif_ToInt32(data, index + 20);
            this.isStdCount = cast(uint)TZif_ToInt32(data, index + 24);
            this.leapCount = cast(uint)TZif_ToInt32(data, index + 28);
            this.timeCount = cast(uint)TZif_ToInt32(data, index + 32);
            this.typeCount = cast(uint)TZif_ToInt32(data, index + 36);
            this.charCount = cast(uint)TZif_ToInt32(data, index + 40);
        }
    }

    enum TZVersion : ubyte
    {
        V1,
        V2,
        V3,
    }

    struct RawDataInfo
    {
        TZifHead t;
        DateTime[] dts;
        ubyte[] typeOfLocalTime;
        TZifType[] transitionType;
        string zoneAbbreviations;
        bool[] standardTime;
        bool[] gmtTime;
        string futureTransitionsPosixFormat;
        string standardAbbrevName;
        string daylightAbbrevName;
    }
}
else
    pragma(msg, "Unsupport system for " ~ __MODULE__);

unittest // ZoneOffset
{
    //import std.stdio : writeln;
    //writeln("ZoneOffset.min=", ZoneOffset.min.toString()); // -23:00
    //writeln("ZoneOffset.max=", ZoneOffset.max.toString()); // +14:00

    auto zone = ZoneOffset(1, 10);
    assert(zone.toString() == "+01:10");

    zone = ZoneOffset(-1, 5);
    assert(zone.toString() == "-01:05");

    assert(ZoneOffset(1, 10) == ZoneOffset(1, 10));
    assert(ZoneOffset(1, 10) != ZoneOffset(-1, 10));

    zone = ZoneOffset(70);
    assert(zone.toString() == "+01:10");
    assert(zone == ZoneOffset(1, 10));

    zone = ZoneOffset(-65);
    assert(zone.toString() == "-01:05");
    assert(zone == ZoneOffset(-1, 5));

    assert(ZoneOffset(1, 10) > ZoneOffset(-1, 5));
    assert(ZoneOffset(-1, 5) < ZoneOffset(1, 10));
    assert(ZoneOffset.min < ZoneOffset.max);
    
    assert(ZoneOffset.fromSystemBias(0).toMinutes() == 0);
    assert(ZoneOffset.fromSystemBias(0).toString() == "+00:00");
    assert(ZoneOffset.fromSystemBias(5).toMinutes() == -5);
    assert(ZoneOffset.fromSystemBias(5).toString() == "-00:05");
}

unittest // TimeZoneInfo.localTimeZone
{
    auto ltz = TimeZoneInfo.localTimeZone();

    version(none)
    dgWriteln("ltz.baseUtcOffset=", ltz.baseUtcOffset,
              ", ltz.daylightName=", ltz.daylightName,
              ", ltz.dislayName=", ltz.displayName,
              ", ltz.id=", ltz.id,
              ", ltz.standardName=", ltz.standardName,
              ", ltz.supportsDaylightSavingTime=", ltz.supportsDaylightSavingTime);
}
