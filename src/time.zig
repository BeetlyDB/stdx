// -------------------------------------------------------------------------- //
// Copyright (c) 2019-2022, Jairus Martin.                                    //
// Distributed under the terms of the MIT License.                            //
// The full license is in the file LICENSE, distributed with this software.   //
// -------------------------------------------------------------------------- //
// MODIFED VERSION
const std = @import("std");
const time = std.time;
const math = std.math;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const testing = std.testing;
const assert = std.debug.assert;
const create = Timezone.create;

pub const DstZones = enum(u8) {
    no_dst,
    eastern_european_summer_time,
    atlantic_daylight_time,
    australian_central_daylight_time,
    lord_howe_summer_time,
    new_zealand_daylight_time,
    chile_summer_time,
    egypt_daylight_time,
    isreal_daylight_time,
    eastern_island_summer_time,
};

const EPOCH_SECONDS: i64 = @as(i64, @intCast(EPOCH)) * time.s_per_day;

pub fn getDstZoneData(year: u16, dst_zone: DstZones) [3]i64 {
    switch (dst_zone) {
        .eastern_european_summer_time => {
            return getEESTData(year);
        },
        .atlantic_daylight_time => {
            return getADTData(year);
        },
        .australian_central_daylight_time => {
            return getACDTData(year);
        },
        .lord_howe_summer_time => {
            return getLHSTData(year);
        },
        .new_zealand_daylight_time => {
            return getNZDTData(year);
        },
        .chile_summer_time => {
            return getCLSTData(year);
        },
        .egypt_daylight_time => {
            return getEgyptDstData(year);
        },
        .isreal_daylight_time => {
            return getIDTData(year);
        },
        .eastern_island_summer_time => {
            return getEASSTData(year);
        },
        else => {
            return [3]i64{ 0, 0, 0 };
        },
    }
}

const Weekdays = enum {
    thursday, // because 1970-01-01 is a Thursday
    friday,
    saturday,
    sunday,
    monday,
    tuesday,
    wednesday,

    pub fn toNumber(self: Weekdays) u3 {
        return @intFromEnum(self);
    }

    pub fn fromNumber(number: i64) Weekdays {
        return @enumFromInt(number);
    }
};

const Occurrence = enum(u8) {
    first = 1,
    second,
    third,
    fourth,
    fifth,
};

pub fn getEESTData(year: u16) [3]i64 {
    const start = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.mar), .sunday);
    const end = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.oct), .sunday);
    return [3]i64{ start, end, 60 };
}

pub fn getADTData(year: u16) [3]i64 {
    const start = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.mar), .sunday, .second);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.nov), .sunday, .first);
    return [3]i64{ start, end, 60 };
}

pub fn getACDTData(year: u16) [3]i64 {
    const start = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.oct), .sunday, .first);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.apr), .sunday, .first);
    return [3]i64{ start, end, 60 };
}

pub fn getEASSTData(year: u16) [3]i64 {
    const start = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.sep), .saturday, .first);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.apr), .saturday, .first);
    return [3]i64{ start, end, 60 };
}

pub fn getLHSTData(year: u16) [3]i64 {
    const start = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.oct), .sunday, .first);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.apr), .sunday, .first);
    return [3]i64{ start, end, 30 };
}

pub fn getNZDTData(year: u16) [3]i64 {
    const start = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.sep), .sunday);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.apr), .sunday, .first);
    return [3]i64{ start, end, 60 };
}

pub fn getCLSTData(year: u16) [3]i64 {
    const start = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.sep), .saturday, .first);
    const end = nthOccurrenceOfTheMonth(year, @intFromEnum(time.epoch.Month.apr), .saturday, .first);
    return [3]i64{ start, end, 60 };
}

pub fn getEgyptDstData(year: u16) [3]i64 {
    const start = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.apr), .friday);
    const end = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.oct), .thursday);
    return [3]i64{ start, end, 60 };
}

pub fn getIDTData(year: u16) [3]i64 {
    var start = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.mar), .sunday);
    start -= 2 * 24 * 3600; //Friday before last Sunday in March at 02:00
    const end = lastWeekdayOfMonth(year, @intFromEnum(time.epoch.Month.oct), .sunday);
    return [3]i64{ start, end, 60 };
}

fn weekdayToNumber(wd: Weekdays) u3 {
    return @intFromEnum(wd);
}

inline fn nthOccurrenceOfTheMonth(year: u32, month: u16, target_wd: Weekdays, occurrence: Occurrence) i64 {
    const y: u16 = @intCast(year);
    const m: u4 = @intCast(month);
    const date_first = Date{ .year = y, .month = m, .day = 1 };
    const first_dow_date = date_first.dayOfWeek(); // Monday=1..Sunday=7
    const first_dow_num: i64 = @as(i64, @intFromEnum(first_dow_date)) - 1; // 0=Mon..6=Sun
    const target_num: u8 = (weekdayToNumber(target_wd) + 3) % 7;
    const diff: i64 = @as(i64, @intCast(target_num)) - first_dow_num; // -6..+6
    const mod_diff: i64 = @mod(diff, 7); // -6..+6,
    const offset_days: i64 = @mod(mod_diff + 7, 7); //
    const occ_num: u8 = @intFromEnum(occurrence); // 1-5
    const nth_day: u8 = @intCast(1 + offset_days + (@as(i64, @intCast(occ_num - 1)) * 7)); // Max 35 < u8
    const days_in_m = daysInMonth(year, month);
    if (nth_day > days_in_m) return 0;
    const date_nth = Date{ .year = y, .month = m, .day = nth_day };
    const ordinal_nth = date_nth.toOrdinal();
    const timestamp_0001 = (@as(i64, @intCast(ordinal_nth)) * time.s_per_day);
    return timestamp_0001 - EPOCH_SECONDS;
}

inline fn lastWeekdayOfMonth(year: u32, month: u16, target_wd: Weekdays) i64 {
    const y: u16 = @intCast(year);
    const m: u4 = @intCast(month);
    const date_first = Date{ .year = y, .month = m, .day = 1 };
    const first_dow_date = date_first.dayOfWeek();
    const first_dow_num: i64 = @as(i64, @intFromEnum(first_dow_date)) - 1; // 0=Mon..6=Sun
    const target_num: u8 = (weekdayToNumber(target_wd) + 3) % 7; // 0-6
    const last_day_num: u8 = daysInMonth(year, month);
    const days_from_first: i64 = @as(i64, @intCast(last_day_num - 1)); // 0..30
    const last_dow_num: i64 = @mod(first_dow_num + days_from_first, 7);
    const diff_back: i64 = last_dow_num - @as(i64, @intCast(target_num)); // -6..+6
    const mod_diff_back: i64 = @mod(diff_back, 7);
    const offset_back: i64 = @mod(mod_diff_back + 7, 7); // 0-6
    var result_day: i64 = @as(i64, @intCast(last_day_num)) - offset_back;
    if (result_day < 1) result_day += 7;
    const result_day_u8: u8 = @intCast(result_day);
    const date_last = Date{ .year = y, .month = m, .day = result_day_u8 };
    const ordinal_last = date_last.toOrdinal();
    const timestamp_0001 = (@as(i64, @intCast(ordinal_last)) * time.s_per_day);
    return timestamp_0001 - EPOCH_SECONDS;
}

fn getDayNameFromTimestamp(timestamp: i64) Weekdays {
    const hours = @divFloor(timestamp, 3600);
    const days = @divFloor(hours, 24);
    const offset = @mod(days, 7);
    return Weekdays.fromNumber(offset);
}

test "get-europe-dst-data" {
    const dst_data = getDstZoneData(2025, .eastern_european_summer_time);
    try std.testing.expectEqual(1743292800, dst_data[0]);
    try std.testing.expectEqual(1761436800, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-us-dst-data" {
    const dst_data = getDstZoneData(2025, .atlantic_daylight_time);
    try std.testing.expectEqual(1741478400, dst_data[0]);
    try std.testing.expectEqual(1762041600, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-australia-dst-data" {
    const dst_data = getDstZoneData(2025, .australian_central_daylight_time);
    try std.testing.expectEqual(1759622400, dst_data[0]);
    try std.testing.expectEqual(1743897600, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-lord-howe-dst-data" {
    const dst_data = getDstZoneData(2025, .lord_howe_summer_time);
    try std.testing.expectEqual(1759622400, dst_data[0]);
    try std.testing.expectEqual(1743897600, dst_data[1]);
    try std.testing.expectEqual(30, dst_data[2]);
}

test "get-new-zeland-dst-data" {
    const dst_data = getDstZoneData(2025, .new_zealand_daylight_time);
    try std.testing.expectEqual(1759017600, dst_data[0]);
    try std.testing.expectEqual(1743897600, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-chile-dst-data" {
    const dst_data = getDstZoneData(2025, .chile_summer_time);
    try std.testing.expectEqual(1757116800, dst_data[0]);
    try std.testing.expectEqual(1743811200, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-egypt-dst-data" {
    const dst_data = getDstZoneData(2025, .egypt_daylight_time);
    try std.testing.expectEqual(1745539200, dst_data[0]);
    try std.testing.expectEqual(1761782400, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-israel-dst-data" {
    const dst_data = getDstZoneData(2025, .isreal_daylight_time);
    try std.testing.expectEqual(1743120000, dst_data[0]);
    try std.testing.expectEqual(1761436800, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

test "get-eastern-island-dst-data" {
    const dst_data = getDstZoneData(2025, .eastern_island_summer_time);
    try std.testing.expectEqual(1757116800, dst_data[0]);
    try std.testing.expectEqual(1743811200, dst_data[1]);
    try std.testing.expectEqual(60, dst_data[2]);
}

// Number of days in each month not accounting for leap year
pub const Weekday = enum(u3) {
    Monday = 1,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
};

pub const Month = enum(u4) {
    January = 1,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December,

    // Convert an abbreviation, eg Jan to the enum value
    pub fn parseAbbr(month: []const u8) !Month {
        if (month.len == 3) {
            inline for (std.meta.fields(Month)) |f| {
                if (ascii.eqlIgnoreCase(f.name[0..3], month)) {
                    return @enumFromInt(f.value);
                }
            }
        }
        return error.InvalidFormat;
    }

    pub fn parseName(month: []const u8) !Month {
        inline for (std.meta.fields(Month)) |f| {
            if (ascii.eqlIgnoreCase(f.name, month)) {
                return @enumFromInt(f.value);
            }
        }
        return error.InvalidFormat;
    }
};

test "month-parse-abbr" {
    try testing.expectEqual(try Month.parseAbbr("Jan"), .January);
    try testing.expectEqual(try Month.parseAbbr("Oct"), .October);
    try testing.expectEqual(try Month.parseAbbr("sep"), .September);
    try testing.expectError(error.InvalidFormat, Month.parseAbbr("cra"));
}

test "month-parse" {
    try testing.expectEqual(try Month.parseName("January"), .January);
    try testing.expectEqual(try Month.parseName("OCTOBER"), .October);
    try testing.expectEqual(try Month.parseName("july"), .July);
    try testing.expectError(error.InvalidFormat, Month.parseName("NoShaveNov"));
}

pub const MIN_YEAR: u16 = 1;
pub const MAX_YEAR: u16 = 9999;
pub const MAX_ORDINAL: u32 = 3652059;

const DAYS_IN_MONTH = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
const DAYS_BEFORE_MONTH = [12]u16{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

pub fn isLeapYear(year: u32) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

pub fn isLeapDay(year: u32, month: u32, day: u32) bool {
    return isLeapYear(year) and month == 2 and day == 29;
}

test "leapyear" {
    try testing.expect(isLeapYear(2019) == false);
    try testing.expect(isLeapYear(2018) == false);
    try testing.expect(isLeapYear(2017) == false);
    try testing.expect(isLeapYear(2016) == true);
    try testing.expect(isLeapYear(2000) == true);
    try testing.expect(isLeapYear(1900) == false);
}

// Number of days before Jan 1st of year
pub fn daysBeforeYear(year: u32) u32 {
    const y: u32 = year - 1;
    return y * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400);
}

// Days before 1 Jan 1970
const EPOCH = daysBeforeYear(1970) + 1;

test "daysBeforeYear" {
    try testing.expect(daysBeforeYear(1996) == 728658);
    try testing.expect(daysBeforeYear(2019) == 737059);
}

// Number of days in that month for the year
pub fn daysInMonth(year: u32, month: u32) u8 {
    assert(1 <= month and month <= 12);
    if (month == 2 and isLeapYear(year)) return 29;
    return DAYS_IN_MONTH[month - 1];
}

test "daysInMonth" {
    try testing.expect(daysInMonth(2019, 1) == 31);
    try testing.expect(daysInMonth(2019, 2) == 28);
    try testing.expect(daysInMonth(2016, 2) == 29);
}

// Number of days in year preceding the first day of month
pub fn daysBeforeMonth(year: u32, month: u32) u32 {
    assert(month >= 1 and month <= 12);
    var d = DAYS_BEFORE_MONTH[month - 1];
    if (month > 2 and isLeapYear(year)) d += 1;
    return d;
}

// Return number of days since 01-Jan-0001
fn ymd2ord(year: u16, month: u8, day: u8) u32 {
    assert(month >= 1 and month <= 12);
    assert(day >= 1 and day <= daysInMonth(year, month));
    return daysBeforeYear(year) + daysBeforeMonth(year, month) + day;
}

test "ymd2ord" {
    try testing.expect(ymd2ord(1970, 1, 1) == 719163);
    try testing.expect(ymd2ord(28, 2, 29) == 9921);
    try testing.expect(ymd2ord(2019, 11, 27) == 737390);
    try testing.expect(ymd2ord(2019, 11, 28) == 737391);
}

test "days-before-year" {
    const DI400Y = daysBeforeYear(401); // Num of days in 400 years
    const DI100Y = daysBeforeYear(101); // Num of days in 100 years
    const DI4Y = daysBeforeYear(5); // Num of days in 4   years

    // A 4-year cycle has an extra leap day over what we'd get from pasting
    // together 4 single years.
    try testing.expect(DI4Y == 4 * 365 + 1);

    // Similarly, a 400-year cycle has an extra leap day over what we'd get from
    // pasting together 4 100-year cycles.
    try testing.expect(DI400Y == 4 * DI100Y + 1);

    // OTOH, a 100-year cycle has one fewer leap day than we'd get from
    // pasting together 25 4-year cycles.
    try testing.expect(DI100Y == 25 * DI4Y - 1);
}

// Calculate the number of days of the first monday for week 1 iso calendar
// for the given year since 01-Jan-0001
pub fn daysBeforeFirstMonday(year: u16) u32 {
    // From cpython/datetime.py _isoweek1monday
    const THURSDAY = 3;
    const first_day = ymd2ord(year, 1, 1);
    const first_weekday = (first_day + 6) % 7;
    var week1_monday = first_day - first_weekday;
    if (first_weekday > THURSDAY) {
        week1_monday += 7;
    }
    return week1_monday;
}

test "iso-first-monday" {
    // Created using python
    const years = [20]u16{ 1816, 1823, 1839, 1849, 1849, 1870, 1879, 1882, 1909, 1910, 1917, 1934, 1948, 1965, 1989, 2008, 2064, 2072, 2091, 2096 };
    const output = [20]u32{ 662915, 665470, 671315, 674969, 674969, 682641, 685924, 687023, 696886, 697250, 699805, 706014, 711124, 717340, 726104, 733041, 753495, 756421, 763358, 765185 };
    for (years, 0..) |year, i| {
        try testing.expectEqual(daysBeforeFirstMonday(year), output[i]);
    }
}

pub const ISOCalendar = struct {
    year: u16,
    week: u6, // Week of year 1-53
    weekday: u3, // Day of week 1-7
};

pub const Date = struct {
    year: u16,
    month: u4 = 1, // Month of year
    day: u8 = 1, // Day of month
    pub fn toTimestampSeconds(self: Date) i64 {
        const days: i64 = @intCast(self.toOrdinal());
        return days * time.s_per_day;
    }

    // Create and validate the date
    pub fn create(year: u32, month: u32, day: u32) !Date {
        if (year < MIN_YEAR or year > MAX_YEAR) return error.InvalidDate;
        if (month < 1 or month > 12) return error.InvalidDate;
        if (day < 1 or day > daysInMonth(year, month)) return error.InvalidDate;
        // Since we just validated the ranges we can now savely cast
        return Date{
            .year = @intCast(year),
            .month = @intCast(month),
            .day = @intCast(day),
        };
    }

    // Return a copy of the date
    pub fn copy(self: Date) !Date {
        return Date.create(self.year, self.month, self.day);
    }

    // Create a Date from the number of days since 01-Jan-0001
    pub fn fromOrdinal(ordinal: u32) Date {
        // n is a 1-based index, starting at 1-Jan-1.  The pattern of leap years
        // repeats exactly every 400 years.  The basic strategy is to find the
        // closest 400-year boundary at or before n, then work with the offset
        // from that boundary to n.  Life is much clearer if we subtract 1 from
        // n first -- then the values of n at 400-year boundaries are exactly
        // those divisible by DI400Y:
        //
        //     D  M   Y            n              n-1
        //     -- --- ----        ----------     ----------------
        //     31 Dec -400        -DI400Y        -DI400Y -1
        //      1 Jan -399        -DI400Y +1     -DI400Y       400-year boundary
        //     ...
        //     30 Dec  000        -1             -2
        //     31 Dec  000         0             -1
        //      1 Jan  001         1              0            400-year boundary
        //      2 Jan  001         2              1
        //      3 Jan  001         3              2
        //     ...
        //     31 Dec  400         DI400Y        DI400Y -1
        //      1 Jan  401         DI400Y +1     DI400Y        400-year boundary
        assert(ordinal >= 1 and ordinal <= MAX_ORDINAL);

        var n = ordinal - 1;
        const DI400Y = comptime daysBeforeYear(401); // Num of days in 400 years
        const DI100Y = comptime daysBeforeYear(101); // Num of days in 100 years
        const DI4Y = comptime daysBeforeYear(5); // Num of days in 4   years
        const n400 = @divFloor(n, DI400Y);
        n = @mod(n, DI400Y);
        var year = n400 * 400 + 1; //  ..., -399, 1, 401, ...

        // Now n is the (non-negative) offset, in days, from January 1 of year, to
        // the desired date.  Now compute how many 100-year cycles precede n.
        // Note that it's possible for n100 to equal 4!  In that case 4 full
        // 100-year cycles precede the desired day, which implies the desired
        // day is December 31 at the end of a 400-year cycle.
        const n100 = @divFloor(n, DI100Y);
        n = @mod(n, DI100Y);

        // Now compute how many 4-year cycles precede it.
        const n4 = @divFloor(n, DI4Y);
        n = @mod(n, DI4Y);

        // And now how many single years.  Again n1 can be 4, and again meaning
        // that the desired day is December 31 at the end of the 4-year cycle.
        const n1 = @divFloor(n, 365);
        n = @mod(n, 365);

        year += n100 * 100 + n4 * 4 + n1;

        if (n1 == 4 or n100 == 4) {
            assert(n == 0);
            return Date.create(year - 1, 12, 31) catch unreachable;
        }

        // Now the year is correct, and n is the offset from January 1.  We find
        // the month via an estimate that's either exact or one too large.
        const leapyear = (n1 == 3) and (n4 != 24 or n100 == 3);
        assert(leapyear == isLeapYear(year));
        var month = (n + 50) >> 5;
        if (month == 0) month = 12; // Loop around
        var preceding = daysBeforeMonth(year, month);

        if (preceding > n) { // estimate is too large
            month -= 1;
            if (month == 0) month = 12; // Loop around
            preceding -= daysInMonth(year, month);
        }
        n -= preceding;
        // assert(n > 0 and n < daysInMonth(year, month));

        // Now the year and month are correct, and n is the offset from the
        // start of that month:  we're done!
        return Date.create(year, month, n + 1) catch unreachable;
    }

    // Return proleptic Gregorian ordinal for the year, month and day.
    // January 1 of year 1 is day 1.  Only the year, month and day values
    // contribute to the result.
    pub fn toOrdinal(self: Date) u32 {
        return ymd2ord(self.year, self.month, self.day);
    }

    // Returns todays date
    pub fn now() Date {
        return Date.fromTimestamp(time.milliTimestamp());
    }

    // Create a date from the number of seconds since 1 Jan 1970
    pub fn fromSeconds(seconds: f64) Date {
        const r = math.modf(seconds);
        const timestamp: i64 = @intFromFloat(r.ipart); // Seconds
        const days = @divFloor(timestamp, time.s_per_day) + @as(i64, EPOCH);
        assert(days >= 0 and days <= MAX_ORDINAL);
        return Date.fromOrdinal(@intCast(days));
    }

    // Return the number of seconds since 1 Jan 1970
    pub fn toSeconds(self: Date) f64 {
        const days = @as(i64, @intCast(self.toOrdinal())) - @as(i64, EPOCH);
        return @floatFromInt(days * time.s_per_day);
    }

    // Create a date from a UTC timestamp in milliseconds relative to Jan 1st 1970
    pub fn fromTimestamp(timestamp: i64) Date {
        const days = @divFloor(timestamp, time.ms_per_day) + @as(i64, EPOCH);
        assert(days >= 0 and days <= MAX_ORDINAL);
        return Date.fromOrdinal(@intCast(days));
    }

    // Create a UTC timestamp in milliseconds relative to Jan 1st 1970
    pub fn toTimestamp(self: Date) i64 {
        const d: i64 = @intCast(daysBeforeYear(self.year));
        const days = d - @as(i64, EPOCH) + @as(i64, @intCast(self.dayOfYear()));
        return days * time.ms_per_day;
    }

    // Convert to an ISOCalendar date containing the year, week number, and
    // weekday. First week is 1. Monday is 1, Sunday is 7.
    pub fn isoCalendar(self: Date) ISOCalendar {
        // Ported from python's isocalendar.
        var y = self.year;
        var first_monday = daysBeforeFirstMonday(y);
        const today = ymd2ord(self.year, self.month, self.day);
        if (today < first_monday) {
            y -= 1;
            first_monday = daysBeforeFirstMonday(y);
        }
        const days_between = today - first_monday;
        var week = @divFloor(days_between, 7);
        const day = @mod(days_between, 7);
        if (week >= 52 and today >= daysBeforeFirstMonday(y + 1)) {
            y += 1;
            week = 0;
        }
        assert(week >= 0 and week < 53);
        assert(day >= 0 and day < 8);
        return ISOCalendar{ .year = y, .week = @intCast(week + 1), .weekday = @intCast(day + 1) };
    }

    // ------------------------------------------------------------------------
    // Comparisons
    // ------------------------------------------------------------------------
    pub fn eql(self: Date, other: Date) bool {
        return self.cmp(other) == .eq;
    }

    pub fn cmp(self: Date, other: Date) Order {
        if (self.year > other.year) return .gt;
        if (self.year < other.year) return .lt;
        if (self.month > other.month) return .gt;
        if (self.month < other.month) return .lt;
        if (self.day > other.day) return .gt;
        if (self.day < other.day) return .lt;
        return .eq;
    }

    pub fn gt(self: Date, other: Date) bool {
        return self.cmp(other) == .gt;
    }

    pub fn gte(self: Date, other: Date) bool {
        const r = self.cmp(other);
        return r == .eq or r == .gt;
    }

    pub fn lt(self: Date, other: Date) bool {
        return self.cmp(other) == .lt;
    }

    pub fn lte(self: Date, other: Date) bool {
        const r = self.cmp(other);
        return r == .eq or r == .lt;
    }

    // ------------------------------------------------------------------------
    // Parsing
    // ------------------------------------------------------------------------
    // Parse date in format YYYY-MM-DD. Numbers must be zero padded.
    pub fn parseIso(ymd: []const u8) !Date {
        const value = std.mem.trim(u8, ymd, " ");
        if (value.len != 10) return error.InvalidFormat;
        const year = std.fmt.parseInt(u16, value[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, value[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, value[8..10], 10) catch return error.InvalidFormat;
        return Date.create(year, month, day);
    }

    // ------------------------------------------------------------------------
    // Formatting
    // ------------------------------------------------------------------------

    // Return date in ISO format YYYY-MM-DD
    const ISO_DATE_FMT = "{:0>4}-{:0>2}-{:0>2}";

    pub fn formatIso(self: Date, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, ISO_DATE_FMT, .{ self.year, self.month, self.day });
    }

    pub fn formatIsoBuf(self: Date, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, ISO_DATE_FMT, .{ self.year, self.month, self.day });
    }

    pub fn writeIso(self: Date, writer: anytype) !void {
        try std.fmt.format(writer, ISO_DATE_FMT, .{ self.year, self.month, self.day });
    }

    // ------------------------------------------------------------------------
    // Properties
    // ------------------------------------------------------------------------

    // Return day of year starting with 1
    pub fn dayOfYear(self: Date) u16 {
        const d = self.toOrdinal() - daysBeforeYear(self.year);
        assert(d >= 1 and d <= 366);
        return @intCast(d);
    }

    // Return day of week starting with Monday = 1 and Sunday = 7
    pub fn dayOfWeek(self: Date) Weekday {
        const dow: u3 = @intCast(self.toOrdinal() % 7);
        return @enumFromInt(if (dow == 0) 7 else dow);
    }

    // Return the ISO calendar based week of year. With 1 being the first week.
    pub fn weekOfYear(self: Date) u8 {
        return self.isoCalendar().week;
    }

    // Return day of week starting with Monday = 0 and Sunday = 6
    pub fn weekday(self: Date) u4 {
        return @intFromEnum(self.dayOfWeek()) - 1;
    }

    // Return whether the date is a weekend (Saturday or Sunday)
    pub fn isWeekend(self: Date) bool {
        return self.weekday() >= 5;
    }

    // Return the name of the day of the week, eg "Sunday"
    pub fn weekdayName(self: Date) []const u8 {
        return @tagName(self.dayOfWeek());
    }

    // Return the name of the day of the month, eg "January"
    pub fn monthName(self: Date) []const u8 {
        assert(self.month >= 1 and self.month <= 12);
        return @tagName(@as(Month, @enumFromInt(self.month)));
    }

    // ------------------------------------------------------------------------
    // Operations
    // ------------------------------------------------------------------------

    // Return a copy of the date shifted by the given number of days
    pub fn shiftDays(self: Date, days: i32) Date {
        return self.shift(Delta{ .days = days });
    }

    // Return a copy of the date shifted by the given number of years
    pub fn shiftYears(self: Date, years: i16) Date {
        return self.shift(Delta{ .years = years });
    }

    pub const Delta = struct {
        years: i16 = 0,
        days: i32 = 0,
    };

    // Return a copy of the date shifted in time by the delta
    pub fn shift(self: Date, delta: Delta) Date {
        if (delta.years == 0 and delta.days == 0) {
            return self.copy() catch unreachable;
        }

        // Shift year
        var year = self.year;
        if (delta.years < 0) {
            year -= @intCast(-delta.years);
        } else {
            year += @intCast(delta.years);
        }
        var ord = daysBeforeYear(year);
        var days = self.dayOfYear();
        const from_leap = isLeapYear(self.year);
        const to_leap = isLeapYear(year);
        if (days == 59 and from_leap and to_leap) {
            // No change before leap day
        } else if (days < 59) {
            // No change when jumping from leap day to leap day
        } else if (to_leap and !from_leap) {
            // When jumping to a leap year to non-leap year
            // we have to add a leap day to the day of year
            days += 1;
        } else if (from_leap and !to_leap) {
            // When jumping from leap year to non-leap year we have to undo
            // the leap day added to the day of yearear
            days -= 1;
        }
        ord += days;

        // Shift days
        if (delta.days < 0) {
            ord -= @intCast(-delta.days);
        } else {
            ord += @intCast(delta.days);
        }
        return Date.fromOrdinal(ord);
    }
};

test "date-now" {
    _ = Date.now();
}

test "date-compare" {
    const d1 = try Date.create(2019, 7, 3);
    const d2 = try Date.create(2019, 7, 3);
    const d3 = try Date.create(2019, 6, 3);
    const d4 = try Date.create(2020, 7, 3);
    try testing.expect(d1.eql(d2));
    try testing.expect(d1.gt(d3));
    try testing.expect(d3.lt(d2));
    try testing.expect(d4.gt(d2));
}

test "date-from-ordinal" {
    var date = Date.fromOrdinal(9921);
    try testing.expectEqual(date.year, 28);
    try testing.expectEqual(date.month, 2);
    try testing.expectEqual(date.day, 29);
    try testing.expectEqual(date.toOrdinal(), 9921);

    date = Date.fromOrdinal(737390);
    try testing.expectEqual(date.year, 2019);
    try testing.expectEqual(date.month, 11);
    try testing.expectEqual(date.day, 27);
    try testing.expectEqual(date.toOrdinal(), 737390);

    date = Date.fromOrdinal(719163);
    try testing.expectEqual(date.year, 1970);
    try testing.expectEqual(date.month, 1);
    try testing.expectEqual(date.day, 1);
    try testing.expectEqual(date.toOrdinal(), 719163);
}

test "date-from-seconds" {
    var seconds: f64 = 0;
    var date = Date.fromSeconds(seconds);
    try testing.expectEqual(date, try Date.create(1970, 1, 1));
    try testing.expectEqual(date.toSeconds(), seconds);

    seconds = -@as(f64, EPOCH - 1) * time.s_per_day;
    date = Date.fromSeconds(seconds);
    try testing.expectEqual(date, try Date.create(1, 1, 1));
    try testing.expectEqual(date.toSeconds(), seconds);

    seconds = @as(f64, MAX_ORDINAL - EPOCH) * time.s_per_day;
    date = Date.fromSeconds(seconds);
    try testing.expectEqual(date, try Date.create(9999, 12, 31));
    try testing.expectEqual(date.toSeconds(), seconds);
    //
    //
    //     const t = 63710928000.000;
    //     date = Date.fromSeconds(t);
    //     try testing.expectEqual(date.year, 2019);
    //     try testing.expectEqual(date.month, 12);
    //     try testing.expectEqual(date.day, 3);
    //     try testing.expectEqual(date.toSeconds(), t);
    //
    //     Max check
    //     var max_date = try Date.create(9999, 12, 31);
    //     const tmax: f64 = @intToFloat(f64, MAX_ORDINAL-1) * time.s_per_day;
    //     date = Date.fromSeconds(tmax);
    //     try testing.expect(date.eql(max_date));
    //     try testing.expectEqual(date.toSeconds(), tmax);
}

test "date-day-of-year" {
    var date = try Date.create(1970, 1, 1);
    try testing.expect(date.dayOfYear() == 1);
}

test "date-day-of-week" {
    var date = try Date.create(2019, 11, 27);
    try testing.expectEqual(date.weekday(), 2);
    try testing.expectEqual(date.dayOfWeek(), .Wednesday);
    try testing.expectEqualSlices(u8, date.monthName(), "November");
    try testing.expectEqualSlices(u8, date.weekdayName(), "Wednesday");
    try testing.expect(!date.isWeekend());

    date = try Date.create(1776, 6, 4);
    try testing.expectEqual(date.weekday(), 1);
    try testing.expectEqual(date.dayOfWeek(), .Tuesday);
    try testing.expectEqualSlices(u8, date.monthName(), "June");
    try testing.expectEqualSlices(u8, date.weekdayName(), "Tuesday");
    try testing.expect(!date.isWeekend());

    date = try Date.create(2019, 12, 1);
    try testing.expectEqualSlices(u8, date.monthName(), "December");
    try testing.expectEqualSlices(u8, date.weekdayName(), "Sunday");
    try testing.expect(date.isWeekend());
}

test "date-shift-days" {
    var date = try Date.create(2019, 11, 27);
    var d = date.shiftDays(-2);
    try testing.expectEqual(d.day, 25);
    try testing.expectEqualSlices(u8, d.weekdayName(), "Monday");

    // Ahead one week
    d = date.shiftDays(7);
    try testing.expectEqualSlices(u8, d.weekdayName(), date.weekdayName());
    try testing.expectEqual(d.month, 12);
    try testing.expectEqualSlices(u8, d.monthName(), "December");
    try testing.expectEqual(d.day, 4);

    d = date.shiftDays(0);
    try testing.expect(date.eql(d));
}

test "date-shift-years" {
    // Shift including a leap year
    var date = try Date.create(2019, 11, 27);
    var d = date.shiftYears(-4);
    try testing.expect(d.eql(try Date.create(2015, 11, 27)));

    d = date.shiftYears(15);
    try testing.expect(d.eql(try Date.create(2034, 11, 27)));

    // Shifting from leap day
    var leap_day = try Date.create(2020, 2, 29);
    d = leap_day.shiftYears(1);
    try testing.expect(d.eql(try Date.create(2021, 2, 28)));

    // Before leap day
    date = try Date.create(2020, 2, 2);
    d = date.shiftYears(1);
    try testing.expect(d.eql(try Date.create(2021, 2, 2)));

    // After leap day
    date = try Date.create(2020, 3, 1);
    d = date.shiftYears(1);
    try testing.expect(d.eql(try Date.create(2021, 3, 1)));

    // From leap day to leap day
    d = leap_day.shiftYears(4);
    try testing.expect(d.eql(try Date.create(2024, 2, 29)));
}

test "date-create" {
    try testing.expectError(error.InvalidDate, Date.create(2019, 2, 29));

    var date = Date.fromTimestamp(1574908586928);
    try testing.expect(date.eql(try Date.create(2019, 11, 28)));
}

test "date-copy" {
    const d1 = try Date.create(2020, 1, 1);
    const d2 = try d1.copy();
    try testing.expect(d1.eql(d2));
}

test "date-parse-iso" {
    try testing.expectEqual(try Date.parseIso("2018-12-15"), try Date.create(2018, 12, 15));
    try testing.expectEqual(try Date.parseIso("2021-01-07"), try Date.create(2021, 1, 7));
    try testing.expectError(error.InvalidDate, Date.parseIso("2021-13-01"));
    try testing.expectError(error.InvalidFormat, Date.parseIso("20-01-01"));
    try testing.expectError(error.InvalidFormat, Date.parseIso("2000-1-1"));
}

test "date-format-iso" {
    const date_strs = [_][]const u8{
        "0959-02-05",
        "2018-12-15",
    };

    for (date_strs) |date_str| {
        var d = try Date.parseIso(date_str);
        const parsed_date_str = try d.formatIso(std.testing.allocator);
        defer std.testing.allocator.free(parsed_date_str);
        try testing.expectEqualStrings(date_str, parsed_date_str);
    }
}

test "date-format-iso-buf" {
    const date_strs = [_][]const u8{
        "0959-02-05",
        "2018-12-15",
    };

    for (date_strs) |date_str| {
        var d = try Date.parseIso(date_str);
        var buf: [32]u8 = undefined;
        try testing.expectEqualStrings(date_str, try d.formatIsoBuf(buf[0..]));
    }
}

test "date-write-iso" {
    const date_strs = [_][]const u8{
        "0959-02-05",
        "2018-12-15",
    };

    for (date_strs) |date_str| {
        var buf: [32]u8 = undefined;
        var stream = std.io.fixedBufferStream(buf[0..]);
        var d = try Date.parseIso(date_str);
        try d.writeIso(stream.writer());
        try testing.expectEqualStrings(date_str, stream.getWritten());
    }
}

test "date-isocalendar" {
    const today = try Date.create(2021, 8, 12);
    try testing.expectEqual(today.isoCalendar(), ISOCalendar{ .year = 2021, .week = 32, .weekday = 4 });

    // Some random dates and outputs generated with python
    const dates = [15][]const u8{
        "2018-12-15",
        "2019-01-19",
        "2019-10-14",
        "2020-09-26",

        // Border cases
        "2020-12-27",
        "2020-12-30",
        "2020-12-31",

        "2021-01-01",
        "2021-01-03",
        "2021-01-04",
        "2021-01-10",

        "2021-09-14",
        "2022-09-12",
        "2023-04-10",
        "2024-01-16",
    };

    const expect = [15]ISOCalendar{
        ISOCalendar{ .year = 2018, .week = 50, .weekday = 6 },
        ISOCalendar{ .year = 2019, .week = 3, .weekday = 6 },
        ISOCalendar{ .year = 2019, .week = 42, .weekday = 1 },
        ISOCalendar{ .year = 2020, .week = 39, .weekday = 6 },

        ISOCalendar{ .year = 2020, .week = 52, .weekday = 7 },
        ISOCalendar{ .year = 2020, .week = 53, .weekday = 3 },
        ISOCalendar{ .year = 2020, .week = 53, .weekday = 4 },

        ISOCalendar{ .year = 2020, .week = 53, .weekday = 5 },
        ISOCalendar{ .year = 2020, .week = 53, .weekday = 7 },
        ISOCalendar{ .year = 2021, .week = 1, .weekday = 1 },
        ISOCalendar{ .year = 2021, .week = 1, .weekday = 7 },

        ISOCalendar{ .year = 2021, .week = 37, .weekday = 2 },
        ISOCalendar{ .year = 2022, .week = 37, .weekday = 1 },
        ISOCalendar{ .year = 2023, .week = 15, .weekday = 1 },
        ISOCalendar{ .year = 2024, .week = 3, .weekday = 2 },
    };

    for (dates, 0..) |d, i| {
        const date = try Date.parseIso(d);
        const cal = date.isoCalendar();
        try testing.expectEqual(cal, expect[i]);
        try testing.expectEqual(date.weekOfYear(), expect[i].week);
    }
}

pub const Timezone = struct {
    offset: i16, // In minutes
    name: []const u8,
    dst_zone: DstZones,

    // Auto register timezones
    pub fn create(name: []const u8, offset: i16, dst_zone: DstZones) Timezone {
        const self = Timezone{ .offset = offset, .name = name, .dst_zone = dst_zone };
        return self;
    }

    pub fn offsetSeconds(self: Timezone) i32 {
        return @as(i32, self.offset) * time.s_per_min;
    }

    fn setDST(self: *Timezone, date: Datetime) void {
        if (self.dst_zone == DstZones.no_dst) return;

        const dst_data = getDstZoneData(date.date.year, self.dst_zone);
        const dst_start = dst_data[0];
        const dst_end = dst_data[1];
        const shift: i16 = @as(i16, @intCast(dst_data[2]));
        const timestamp: i128 = @intFromFloat(date.toSeconds());

        if (timestamp >= dst_start) {
            if (dst_start < dst_end and timestamp < dst_end) {
                self.*.offset = self.offset + shift;
            }
            if (dst_start > dst_end) {
                self.*.offset = self.offset + shift; //some regions has start in october and end in march
            }
        }
    }

    pub fn copy(self: *const Timezone) Timezone {
        return Timezone.create(self.name, self.offset, self.dst_zone);
    }
};

pub const Time = struct {
    hour: u8 = 0, // 0 to 23
    minute: u8 = 0, // 0 to 59
    second: u8 = 0, // 0 to 59
    nanosecond: u32 = 0, // 0 to 999999999 TODO: Should this be u20?

    // ------------------------------------------------------------------------
    // Constructors
    // ------------------------------------------------------------------------
    pub fn now() Time {
        return Time.fromTimestamp(time.milliTimestamp());
    }

    // Create a Time struct and validate that all fields are in range
    pub fn create(hour: u32, minute: u32, second: u32, nanosecond: u32) !Time {
        if (hour > 23 or minute > 59 or second > 59 or nanosecond > 999999999) {
            return error.InvalidTime;
        }
        return Time{
            .hour = @intCast(hour),
            .minute = @intCast(minute),
            .second = @intCast(second),
            .nanosecond = nanosecond,
        };
    }

    // Create a copy of the Time
    pub fn copy(self: Time) !Time {
        return Time.create(self.hour, self.minute, self.second, self.nanosecond);
    }

    // Create Time from a UTC Timestamp in milliseconds
    pub fn fromTimestamp(timestamp: i64) Time {
        const remainder = @mod(timestamp, time.ms_per_day);
        var t: u64 = @abs(remainder);
        // t is now only the time part of the day
        const h: u32 = @intCast(@divFloor(t, time.ms_per_hour));
        t -= h * time.ms_per_hour;
        const m: u32 = @intCast(@divFloor(t, time.ms_per_min));
        t -= m * time.ms_per_min;
        const s: u32 = @intCast(@divFloor(t, time.ms_per_s));
        t -= s * time.ms_per_s;
        const ns: u32 = @intCast(t * time.ns_per_ms);
        return Time.create(h, m, s, ns) catch unreachable;
    }

    // From seconds since the start of the day
    pub fn fromSeconds(seconds: f64) Time {
        assert(seconds >= 0);
        // Convert to s and us
        const r = math.modf(seconds);
        var s: u32 = @intFromFloat(@mod(r.ipart, time.s_per_day)); // s
        const h = @divFloor(s, time.s_per_hour);
        s -= h * time.s_per_hour;
        const m = @divFloor(s, time.s_per_min);
        s -= m * time.s_per_min;

        // Rounding seems to only be accurate to within 100ns
        // for normal timestamps
        var frac = math.round(r.fpart * time.ns_per_s / 100) * 100;
        if (frac >= time.ns_per_s) {
            s += 1;
            frac -= time.ns_per_s;
        } else if (frac < 0) {
            s -= 1;
            frac += time.ns_per_s;
        }
        const ns: u32 = @intFromFloat(frac);
        return Time.create(h, m, s, ns) catch unreachable; // If this fails it's a bug
    }

    // Convert to a time in seconds relative to the UTC timezones
    // including the nanosecond component
    pub fn toSeconds(self: Time) f64 {
        const s: f64 = @floatFromInt(self.totalSeconds());
        const ns = @as(f64, @floatFromInt(self.nanosecond)) / time.ns_per_s;
        return s + ns;
    }

    // Convert to a timestamp in milliseconds from UTC
    pub fn toTimestamp(self: Time) i64 {
        const h = @as(i64, @intCast(self.hour)) * time.ms_per_hour;
        const m = @as(i64, @intCast(self.minute)) * time.ms_per_min;
        const s = @as(i64, @intCast(self.second)) * time.ms_per_s;
        const ms: i64 = @intCast(self.nanosecond / time.ns_per_ms);
        return h + m + s + ms;
    }

    // Total seconds from the start of day
    pub fn totalSeconds(self: Time) i32 {
        const h = @as(i32, @intCast(self.hour)) * time.s_per_hour;
        const m = @as(i32, @intCast(self.minute)) * time.s_per_min;
        const s: i32 = @intCast(self.second);
        return h + m + s;
    }

    // -----------------------------------------------------------------------
    // Comparisons
    // -----------------------------------------------------------------------
    pub fn eql(self: Time, other: Time) bool {
        return self.cmp(other) == .eq;
    }

    pub fn cmp(self: Time, other: Time) Order {
        const t1 = self.totalSeconds();
        const t2 = other.totalSeconds();
        if (t1 > t2) return .gt;
        if (t1 < t2) return .lt;
        if (self.nanosecond > other.nanosecond) return .gt;
        if (self.nanosecond < other.nanosecond) return .lt;
        return .eq;
    }

    pub fn gt(self: Time, other: Time) bool {
        return self.cmp(other) == .gt;
    }

    pub fn gte(self: Time, other: Time) bool {
        const r = self.cmp(other);
        return r == .eq or r == .gt;
    }

    pub fn lt(self: Time, other: Time) bool {
        return self.cmp(other) == .lt;
    }

    pub fn lte(self: Time, other: Time) bool {
        const r = self.cmp(other);
        return r == .eq or r == .lt;
    }

    // -----------------------------------------------------------------------
    // Methods
    // -----------------------------------------------------------------------
    pub fn amOrPm(self: Time) []const u8 {
        return if (self.hour > 12) return "PM" else "AM";
    }

    // -----------------------------------------------------------------------
    // Formatting Methods
    // -----------------------------------------------------------------------
    const ISO_HM_FORMAT = "T{d:0>2}:{d:0>2}";
    const ISO_HMS_FORMAT = "T{d:0>2}:{d:0>2}:{d:0>2}";

    pub fn writeIsoHM(self: Time, writer: anytype) !void {
        try std.fmt.format(writer, ISO_HM_FORMAT, .{ self.hour, self.minute });
    }

    pub fn writeIsoHMS(self: Time, writer: anytype) !void {
        try std.fmt.format(writer, ISO_HMS_FORMAT, .{ self.hour, self.minute, self.second });
    }
};

test "time-create" {
    const t = Time.fromTimestamp(1574908586928);
    try testing.expect(t.hour == 2);
    try testing.expect(t.minute == 36);
    try testing.expect(t.second == 26);
    try testing.expect(t.nanosecond == 928000000);

    try testing.expectError(error.InvalidTime, Time.create(25, 1, 1, 0));
    try testing.expectError(error.InvalidTime, Time.create(1, 60, 1, 0));
    try testing.expectError(error.InvalidTime, Time.create(12, 30, 281, 0));
    try testing.expectError(error.InvalidTime, Time.create(12, 30, 28, 1000000000));
}

test "time-now" {
    _ = Time.now();
}

test "time-from-seconds" {
    var seconds: f64 = 15.12;
    var t = Time.fromSeconds(seconds);
    try testing.expect(t.hour == 0);
    try testing.expect(t.minute == 0);
    try testing.expect(t.second == 15);
    try testing.expect(t.nanosecond == 120000000);
    try testing.expect(t.toSeconds() == seconds);

    seconds = 315.12; // + 5 min
    t = Time.fromSeconds(seconds);
    try testing.expect(t.hour == 0);
    try testing.expect(t.minute == 5);
    try testing.expect(t.second == 15);
    try testing.expect(t.nanosecond == 120000000);
    try testing.expect(t.toSeconds() == seconds);

    seconds = 36000 + 315.12; // + 10 hr
    t = Time.fromSeconds(seconds);
    try testing.expect(t.hour == 10);
    try testing.expect(t.minute == 5);
    try testing.expect(t.second == 15);
    try testing.expect(t.nanosecond == 120000000);
    try testing.expect(t.toSeconds() == seconds);

    seconds = 108000 + 315.12; // + 30 hr
    t = Time.fromSeconds(seconds);
    try testing.expect(t.hour == 6);
    try testing.expect(t.minute == 5);
    try testing.expect(t.second == 15);
    try testing.expect(t.nanosecond == 120000000);
    try testing.expectEqual(t.totalSeconds(), 6 * 3600 + 315);
    //testing.expectAlmostEqual(t.toSeconds(), seconds-time.s_per_day);
}

test "time-copy" {
    const t1 = try Time.create(8, 30, 0, 0);
    const t2 = try t1.copy();
    try testing.expect(t1.eql(t2));
}

test "time-compare" {
    const t1 = try Time.create(8, 30, 0, 0);
    const t2 = try Time.create(9, 30, 0, 0);
    const t3 = try Time.create(8, 0, 0, 0);
    const t4 = try Time.create(9, 30, 17, 0);

    try testing.expect(t1.lt(t2));
    try testing.expect(t1.gt(t3));
    try testing.expect(t2.lt(t4));
    try testing.expect(t3.lt(t4));
}

test "time-write-iso-hm" {
    const t = Time.fromTimestamp(1574908586928);

    var buf: [6]u8 = undefined;
    var fbs = std.io.fixedBufferStream(buf[0..]);

    try t.writeIsoHM(fbs.writer());

    try testing.expectEqualSlices(u8, "T02:36", fbs.getWritten());
}

test "time-write-iso-hms" {
    const t = Time.fromTimestamp(1574908586928);

    var buf: [9]u8 = undefined;
    var fbs = std.io.fixedBufferStream(buf[0..]);

    try t.writeIsoHMS(fbs.writer());

    try testing.expectEqualSlices(u8, "T02:36:26", fbs.getWritten());
}

pub const Datetime = struct {
    date: Date,
    time: Time,
    zone: Timezone,

    // An absolute or relative delta
    // if years is defined a date is date
    // TODO: Validate years before allowing it to be created
    pub const Delta = struct {
        years: i16 = 0,
        days: i32 = 0,
        seconds: i64 = 0,
        nanoseconds: i32 = 0,
        relative_to: ?Datetime = null,

        pub fn sub(self: Delta, other: Delta) Delta {
            return Delta{
                .years = self.years - other.years,
                .days = self.days - other.days,
                .seconds = self.seconds - other.seconds,
                .nanoseconds = self.nanoseconds - other.nanoseconds,
                .relative_to = self.relative_to,
            };
        }

        pub fn add(self: Delta, other: Delta) Delta {
            return Delta{
                .years = self.years + other.years,
                .days = self.days + other.days,
                .seconds = self.seconds + other.seconds,
                .nanoseconds = self.nanoseconds + other.nanoseconds,
                .relative_to = self.relative_to,
            };
        }

        // Total seconds in the duration ignoring the nanoseconds fraction
        pub fn totalSeconds(self: Delta) i64 {
            // Calculate the total number of days we're shifting
            var days = self.days;
            if (self.relative_to) |dt| {
                if (self.years != 0) {
                    const a = daysBeforeYear(dt.date.year);
                    // Must always subtract greater of the two
                    if (self.years > 0) {
                        const y: u32 = @intCast(self.years);
                        const b = daysBeforeYear(dt.date.year + y);
                        days += @intCast(b - a);
                    } else {
                        const y: u32 = @intCast(-self.years);
                        assert(y < dt.date.year); // Does not work below year 1
                        const b = daysBeforeYear(dt.date.year - y);
                        days -= @intCast(a - b);
                    }
                }
            } else {
                // Cannot use years without a relative to date
                // otherwise any leap days will screw up results
                assert(self.years == 0);
            }
            var s = self.seconds;
            var ns = self.nanoseconds;
            if (ns >= time.ns_per_s) {
                const ds = @divFloor(ns, time.ns_per_s);
                ns -= ds * time.ns_per_s;
                s += ds;
            } else if (ns <= -time.ns_per_s) {
                const ds = @divFloor(ns, -time.ns_per_s);
                ns += ds * time.us_per_s;
                s -= ds;
            }
            return (days * time.s_per_day + s);
        }
    };

    // ------------------------------------------------------------------------
    // Constructors
    // ------------------------------------------------------------------------
    pub fn now() Datetime {
        return Datetime.fromTimestamp(time.milliTimestamp());
    }

    pub fn create(year: u32, month: u32, day: u32, hour: u32, minute: u32, second: u32, nanosecond: u32, zone: ?Timezone) !Datetime {
        return Datetime{
            .date = try Date.create(year, month, day),
            .time = try Time.create(hour, minute, second, nanosecond),
            .zone = zone orelse UTC,
        };
    }

    // Return a copy
    pub fn copy(self: Datetime) !Datetime {
        return Datetime{
            .date = try self.date.copy(),
            .time = try self.time.copy(),
            .zone = self.zone,
        };
    }

    pub fn fromDate(year: u16, month: u8, day: u8) !Datetime {
        return Datetime{
            .date = try Date.create(year, month, day),
            .time = try Time.create(0, 0, 0, 0),
            .zone = UTC,
        };
    }

    // From seconds since 1 Jan 1970
    pub fn fromSeconds(seconds: f64) Datetime {
        return Datetime{
            .date = Date.fromSeconds(seconds),
            .time = Time.fromSeconds(seconds),
            .zone = UTC,
        };
    }

    // Seconds since 1 Jan 0001 including nanoseconds
    pub fn toSeconds(self: Datetime) f64 {
        return self.date.toSeconds() + self.time.toSeconds();
    }

    // From POSIX timestamp in milliseconds relative to 1 Jan 1970
    pub fn fromTimestamp(timestamp: i64) Datetime {
        const t = @divFloor(timestamp, time.ms_per_day);
        const d: u64 = @abs(t);
        const days = if (timestamp >= 0) d + EPOCH else EPOCH - d;
        assert(days >= 0 and days <= MAX_ORDINAL);
        return Datetime{
            .date = Date.fromOrdinal(@intCast(days)),
            .time = Time.fromTimestamp(timestamp - @as(i64, @intCast(d)) * time.ns_per_day),
            .zone = UTC,
        };
    }

    // From a file modified time in ns
    pub fn fromModifiedTime(mtime: i128) Datetime {
        const ts: i64 = @intCast(@divFloor(mtime, time.ns_per_ms));
        return Datetime.fromTimestamp(ts);
    }

    // To a UTC POSIX timestamp in milliseconds relative to 1 Jan 1970
    pub fn toTimestamp(self: Datetime) i128 {
        const ds = self.date.toTimestamp();
        const ts = self.time.toTimestamp();
        const zs = self.zone.offsetSeconds() * time.ms_per_s;
        return ds + ts - zs;
    }

    // -----------------------------------------------------------------------
    // Comparisons
    // -----------------------------------------------------------------------
    pub fn eql(self: Datetime, other: Datetime) bool {
        return self.cmp(other) == .eq;
    }

    pub fn cmpSameTimezone(self: Datetime, other: Datetime) Order {
        assert(self.zone.offset == other.zone.offset);
        const r = self.date.cmp(other.date);
        if (r != .eq) return r;
        return self.time.cmp(other.time);
    }

    pub fn cmp(self: Datetime, other: Datetime) Order {
        if (self.zone.offset == other.zone.offset) {
            return self.cmpSameTimezone(other);
        }
        // Shift both to utc;;
        const a = self.shiftTimezone(UTC);
        const b = other.shiftTimezone(UTC);
        return a.cmpSameTimezone(b);
    }

    pub fn gt(self: Datetime, other: Datetime) bool {
        return self.cmp(other) == .gt;
    }

    pub fn gte(self: Datetime, other: Datetime) bool {
        const r = self.cmp(other);
        return r == .eq or r == .gt;
    }

    pub fn lt(self: Datetime, other: Datetime) bool {
        return self.cmp(other) == .lt;
    }

    pub fn lte(self: Datetime, other: Datetime) bool {
        const r = self.cmp(other);
        return r == .eq or r == .lt;
    }

    // -----------------------------------------------------------------------
    // Methods
    // -----------------------------------------------------------------------

    // Return a Datetime.Delta relative to this date
    pub fn sub(self: Datetime, other: Datetime) Delta {
        var days = @as(i32, @intCast(self.date.toOrdinal())) - @as(i32, @intCast(other.date.toOrdinal()));
        const offset = (self.zone.offset - other.zone.offset) * time.s_per_min;
        var seconds = (self.time.totalSeconds() - other.time.totalSeconds()) - offset;
        var ns = @as(i32, @intCast(self.time.nanosecond)) - @as(i32, @intCast(other.time.nanosecond));
        while (seconds > 0 and ns < 0) {
            seconds -= 1;
            ns += time.ns_per_s;
        }
        while (days > 0 and seconds < 0) {
            days -= 1;
            seconds += time.s_per_day;
        }
        return Delta{ .days = days, .seconds = seconds, .nanoseconds = ns };
    }

    // Create a Datetime shifted by the given number of years
    pub fn shiftYears(self: Datetime, years: i16) Datetime {
        return self.shift(Delta{ .years = years });
    }

    // Create a Datetime shifted by the given number of days
    pub fn shiftDays(self: Datetime, days: i32) Datetime {
        return self.shift(Delta{ .days = days });
    }

    // Create a Datetime shifted by the given number of hours
    pub fn shiftHours(self: Datetime, hours: i32) Datetime {
        return self.shift(Delta{ .seconds = hours * time.s_per_hour });
    }

    // Create a Datetime shifted by the given number of minutes
    pub fn shiftMinutes(self: Datetime, minutes: i32) Datetime {
        return self.shift(Delta{ .seconds = minutes * time.s_per_min });
    }

    // Convert to the given timeszone
    pub fn shiftTimezone(self: Datetime, zone: Timezone) Datetime {
        var mutable_zone = zone.copy();
        mutable_zone.setDST(self);
        var dt =
            if (self.zone.offset == mutable_zone.offset)
                (self.copy() catch unreachable)
            else
                self.shiftMinutes(mutable_zone.offset - self.zone.offset);

        dt.zone = mutable_zone;
        return dt;
    }

    // Create a Datetime shifted by the given number of seconds
    pub fn shiftSeconds(self: Datetime, seconds: i64) Datetime {
        return self.shift(Delta{ .seconds = seconds });
    }

    // Create a Datetime shifted by the given Delta
    pub fn shift(self: Datetime, delta: Delta) Datetime {
        var days = delta.days;
        var s = delta.seconds + self.time.totalSeconds();

        // Rollover ns to s
        var ns = delta.nanoseconds + @as(i32, @intCast(self.time.nanosecond));
        if (ns >= time.ns_per_s) {
            s += 1;
            ns -= time.ns_per_s;
        } else if (ns < -time.ns_per_s) {
            s -= 1;
            ns += time.ns_per_s;
        }
        assert(ns >= 0 and ns < time.ns_per_s);
        const nanosecond: u32 = @intCast(ns);

        // Rollover s to days
        if (s >= time.s_per_day) {
            const d = @divFloor(s, time.s_per_day);
            days += @intCast(d);
            s -= d * time.s_per_day;
        } else if (s < 0) {
            if (s < -time.s_per_day) { // Wrap multiple
                const d = @divFloor(s, -time.s_per_day);
                days -= @intCast(d);
                s += d * time.s_per_day;
            }
            days -= 1;
            s = time.s_per_day + s;
        }
        assert(s >= 0 and s < time.s_per_day);

        var second: u32 = @intCast(s);
        const hour = @divFloor(second, time.s_per_hour);
        second -= hour * time.s_per_hour;
        const minute = @divFloor(second, time.s_per_min);
        second -= minute * time.s_per_min;

        return Datetime{
            .date = self.date.shift(Date.Delta{ .years = delta.years, .days = days }),
            .time = Time.create(hour, minute, second, nanosecond) catch unreachable, // Error here would mean a bug
            .zone = self.zone,
        };
    }

    // ------------------------------------------------------------------------
    // Formatting methods
    // ------------------------------------------------------------------------

    // Formats a timestamp in the format used by HTTP.
    // eg "Tue, 15 Nov 1994 08:12:31 GMT"
    pub fn formatHttp(self: Datetime, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s}", .{
            self.date.weekdayName()[0..3],
            self.date.day,
            self.date.monthName()[0..3],
            self.date.year,
            self.time.hour,
            self.time.minute,
            self.time.second,
            self.zone.name, // TODO: Should be GMT
        });
    }

    pub fn formatHttpBuf(self: Datetime, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s}", .{
            self.date.weekdayName()[0..3],
            self.date.day,
            self.date.monthName()[0..3],
            self.date.year,
            self.time.hour,
            self.time.minute,
            self.time.second,
            self.zone.name, // TODO: Should be GMT
        });
    }

    // Formats a timestamp in the format used by HTTP.
    // eg "Tue, 15 Nov 1994 08:12:31 GMT"
    pub fn formatHttpFromTimestamp(buf: []u8, timestamp: i64) ![]const u8 {
        return Datetime.fromTimestamp(timestamp).formatHttpBuf(buf);
    }

    // From time in nanoseconds
    pub fn formatHttpFromModifiedDate(buf: []u8, mtime: i128) ![]const u8 {
        const ts: i64 = @intCast(@divFloor(mtime, time.ns_per_ms));
        return Datetime.formatHttpFromTimestamp(buf, ts);
    }

    /// Format datetime to ISO8601 format
    /// e.g. "2023-06-10T14:06:40.015006+08:00"
    pub fn formatISO8601(self: Datetime, allocator: Allocator, with_micro: bool) ![]const u8 {
        var sign: u8 = '+';
        if (self.zone.offset < 0) {
            sign = '-';
        }
        const offset = @abs(self.zone.offset);

        var micro_part_len: u3 = 0;
        var micro_part: [7]u8 = undefined;
        if (with_micro) {
            _ = try std.fmt.bufPrint(&micro_part, ".{:0>6}", .{self.time.nanosecond / 1000});
            micro_part_len = 7;
        }

        return try std.fmt.allocPrint(
            allocator,
            "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}{s}{c}{d:0>2}:{d:0>2}",
            .{
                self.date.year,
                self.date.month,
                self.date.day,
                self.time.hour,
                self.time.minute,
                self.time.second,
                micro_part[0..micro_part_len],
                sign,
                @divFloor(offset, 60),
                @mod(offset, 60),
            },
        );
    }

    pub fn formatISO8601Buf(self: Datetime, buf: []u8, with_micro: bool) ![]const u8 {
        var sign: u8 = '+';
        if (self.zone.offset < 0) {
            sign = '-';
        }
        const offset = @abs(self.zone.offset);

        var micro_part_len: usize = 0;
        var micro_part: [7]u8 = undefined;
        if (with_micro) {
            _ = try std.fmt.bufPrint(&micro_part, ".{:0>6}", .{self.time.nanosecond / 1000});
            micro_part_len = 7;
        }

        return try std.fmt.bufPrint(
            buf,
            "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}{s}{c}{d:0>2}:{d:0>2}",
            .{
                self.date.year,
                self.date.month,
                self.date.day,
                self.time.hour,
                self.time.minute,
                self.time.second,
                micro_part[0..micro_part_len],
                sign,
                @divFloor(offset, 60),
                @mod(offset, 60),
            },
        );
    }

    // ------------------------------------------------------------------------
    // Parsing methods
    // ------------------------------------------------------------------------

    // Parse a HTTP If-Modified-Since header
    // in the format "<day-name>, <day> <month> <year> <hour>:<minute>:<second> GMT"
    // eg, "Wed, 21 Oct 2015 07:28:00 GMT"
    pub fn parseModifiedSince(ims: []const u8) !Datetime {
        const value = std.mem.trim(u8, ims, " ");
        if (value.len < 29) return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, value[5..7], 10) catch return error.InvalidFormat;
        const month = @intFromEnum(try Month.parseAbbr(value[8..11]));
        const year = std.fmt.parseInt(u16, value[12..16], 10) catch return error.InvalidFormat;
        const hour = std.fmt.parseInt(u8, value[17..19], 10) catch return error.InvalidFormat;
        const minute = std.fmt.parseInt(u8, value[20..22], 10) catch return error.InvalidFormat;
        const second = std.fmt.parseInt(u8, value[23..25], 10) catch return error.InvalidFormat;
        return Datetime.create(year, month, day, hour, minute, second, 0, GMT);
    }
};

test "datetime-now" {
    _ = Datetime.now();
}

test "datetime-create-timestamp" {
    //var t = Datetime.now();
    const ts = 1574908586928;
    const t = Datetime.fromTimestamp(ts);
    try testing.expect(t.date.eql(try Date.create(2019, 11, 28)));
    try testing.expect(t.time.eql(try Time.create(2, 36, 26, 928000000)));
    try testing.expectEqualSlices(u8, t.zone.name, "UTC");
    try testing.expectEqual(t.toTimestamp(), ts);
}

test "datetime-from-seconds" {
    // datetime.utcfromtimestamp(1592417521.9326444)
    // datetime.datetime(2020, 6, 17, 18, 12, 1, 932644)
    const ts: f64 = 1592417521.9326444;
    const t = Datetime.fromSeconds(ts);
    try testing.expect(t.date.year == 2020);
    try testing.expectEqual(t.date, try Date.create(2020, 6, 17));
    try testing.expectEqual(t.time, try Time.create(18, 12, 1, 932644400));
    try testing.expectEqual(t.toSeconds(), ts);
}

test "datetime-shift-timezones" {
    const ts = 1574908586928;
    const utc = Datetime.fromTimestamp(ts);
    var t = utc.shiftTimezone(America.New_York);

    const t_new = try Date.create(2019, 11, 27);
    try testing.expect(t.date.eql(t_new));
    try testing.expectEqual(t.time.hour, 21);
    try testing.expectEqual(t.time.minute, 36);
    try testing.expectEqual(t.time.second, 26);
    try testing.expectEqual(t.time.nanosecond, 928000000);
    try testing.expectEqualSlices(u8, t.zone.name, "America/New_York");
    try testing.expectEqual(t.toTimestamp(), ts);

    // Shifting to same timezone has no effect
    const same = t.shiftTimezone(America.New_York);
    try testing.expectEqualDeep(t, same);

    // Shift back works
    const original = t.shiftTimezone(UTC);
    //std.log.warn("\nutc={}\n", .{utc});
    //std.log.warn("original={}\n", .{original});
    try testing.expect(utc.date.eql(original.date));
    try testing.expect(utc.time.eql(original.time));
    try testing.expect(utc.eql(original));
}

test "datetime-shift" {
    var dt = try Datetime.create(2019, 12, 2, 11, 51, 13, 466545, null);

    try testing.expect(dt.shiftYears(0).eql(dt));
    try testing.expect(dt.shiftDays(0).eql(dt));
    try testing.expect(dt.shiftHours(0).eql(dt));

    var t = dt.shiftDays(7);
    try testing.expect(t.date.eql(try Date.create(2019, 12, 9)));
    try testing.expect(t.time.eql(dt.time));

    t = dt.shiftDays(-3);
    try testing.expect(t.date.eql(try Date.create(2019, 11, 29)));
    try testing.expect(t.time.eql(dt.time));

    t = dt.shiftHours(18);
    try testing.expect(t.date.eql(try Date.create(2019, 12, 3)));
    try testing.expect(t.time.eql(try Time.create(5, 51, 13, 466545)));

    t = dt.shiftHours(-36);
    try testing.expect(t.date.eql(try Date.create(2019, 11, 30)));
    try testing.expect(t.time.eql(try Time.create(23, 51, 13, 466545)));

    t = dt.shiftYears(1);
    try testing.expect(t.date.eql(try Date.create(2020, 12, 2)));
    try testing.expect(t.time.eql(dt.time));

    t = dt.shiftYears(-3);
    try testing.expect(t.date.eql(try Date.create(2016, 12, 2)));
    try testing.expect(t.time.eql(dt.time));
}

test "datetime-shift-seconds" {
    // Issue 1
    const midnight_utc = try Datetime.create(2020, 12, 17, 0, 0, 0, 0, null);
    const midnight_copenhagen = try Datetime.create(2020, 12, 17, 1, 0, 0, 0, Europe.Copenhagen);
    try testing.expect(midnight_utc.eql(midnight_copenhagen));

    // Check rollover issues
    var hour: u8 = 0;
    while (hour < 24) : (hour += 1) {
        var minute: u8 = 0;
        while (minute < 60) : (minute += 1) {
            var sec: u8 = 0;
            while (sec < 60) : (sec += 1) {
                const dt_utc = try Datetime.create(2020, 12, 17, hour, minute, sec, 0, null);
                const dt_cop = dt_utc.shiftTimezone(Europe.Copenhagen);
                const dt_nyc = dt_utc.shiftTimezone(America.New_York);
                try testing.expect(dt_utc.eql(dt_cop));
                try testing.expect(dt_utc.eql(dt_nyc));
                try testing.expect(dt_nyc.eql(dt_cop));
            }
        }
    }
}

test "datetime-compare" {
    const dt1 = try Datetime.create(2019, 12, 2, 11, 51, 13, 466545, null);
    const dt2 = try Datetime.fromDate(2016, 12, 2);
    try testing.expect(dt2.lt(dt1));

    const dt3 = Datetime.now();
    try testing.expect(dt3.gt(dt2));

    const dt4 = try dt3.copy();
    try testing.expect(dt3.eql(dt4));

    const dt5 = dt1.shiftTimezone(America.Louisville);
    try testing.expect(dt5.eql(dt1));
}

test "datetime-subtract" {
    var a = try Datetime.create(2019, 12, 2, 11, 51, 13, 466545, null);
    var b = try Datetime.create(2019, 12, 5, 11, 51, 13, 466545, null);
    var delta = a.sub(b);
    try testing.expectEqual(delta.days, -3);
    try testing.expectEqual(delta.totalSeconds(), -3 * time.s_per_day);
    delta = b.sub(a);
    try testing.expectEqual(delta.days, 3);
    try testing.expectEqual(delta.totalSeconds(), 3 * time.s_per_day);

    b = try Datetime.create(2019, 12, 2, 11, 0, 0, 466545, null);
    delta = a.sub(b);
    try testing.expectEqual(delta.totalSeconds(), 13 + 51 * time.s_per_min);
}

test "datetime-subtract-timezone" {
    var a = try Datetime.create(2024, 7, 10, 23, 35, 0, 0, Timezone.create("+0400", 4 * 60, DstZones.no_dst));
    var b = try Datetime.create(2024, 7, 10, 19, 34, 0, 0, null);
    var delta = a.sub(b);
    try testing.expectEqual(delta.days, 0);
    try testing.expectEqual(delta.totalSeconds(), 60);
    delta = b.sub(a);
    try testing.expectEqual(delta.days, 0);
    try testing.expectEqual(delta.totalSeconds(), -60);
}

test "datetime-subtract-delta" {
    var now = Datetime.fromSeconds(1686183930);
    var future = Datetime.fromSeconds(1686268800);
    var delta = future.sub(now);
    try testing.expect(delta.days == 0);
    try testing.expect(delta.seconds == 84870);

    delta = now.sub(future);
    try testing.expect(delta.days == -1);
    try testing.expect(delta.seconds == 1530);

    now = Datetime.fromSeconds(1686183930);
    future = Datetime.fromSeconds(1686270330);
    delta = future.sub(now);
    try testing.expect(delta.days == 1);
    try testing.expect(delta.seconds == 0);
}

test "datetime-parse-modified-since" {
    const str = " Wed, 21 Oct 2015 07:28:00 GMT ";
    try testing.expectEqual(try Datetime.parseModifiedSince(str), try Datetime.create(2015, 10, 21, 7, 28, 0, 0, GMT));

    try testing.expectError(error.InvalidFormat, Datetime.parseModifiedSince("21/10/2015"));
}

test "readme-example" {
    const allocator = std.testing.allocator;
    const date = try Date.create(2019, 12, 25);
    const next_year = date.shiftDays(7);
    assert(next_year.year == 2020);
    assert(next_year.month == 1);
    assert(next_year.day == 1);

    // In UTC
    const now = Datetime.now();
    const now_str = try now.formatHttp(allocator);
    defer allocator.free(now_str);
    std.log.warn("The time is now: {s}\n", .{now_str});
    // The time is now: Fri, 20 Dec 2019 22:03:02 UTC

}

test "datetime-format-ISO8601" {
    const allocator = std.testing.allocator;

    var dt = try Datetime.create(2023, 6, 10, 9, 12, 52, 49612000, null);
    var dt_str = try dt.formatISO8601(allocator, false);
    try testing.expectEqualStrings("2023-06-10T09:12:52+00:00", dt_str);
    allocator.free(dt_str);

    // test positive tz
    dt = try Datetime.create(2023, 6, 10, 18, 12, 52, 49612000, Japan);
    dt_str = try dt.formatISO8601(allocator, false);
    try testing.expectEqualStrings("2023-06-10T18:12:52+09:00", dt_str);
    allocator.free(dt_str);

    // test negative tz
    dt = try Datetime.create(2023, 6, 10, 6, 12, 52, 49612000, Atlantic.Stanley);
    dt_str = try dt.formatISO8601(allocator, false);
    try testing.expectEqualStrings("2023-06-10T06:12:52-03:00", dt_str);
    allocator.free(dt_str);

    // test tz offset div and mod
    dt = try Datetime.create(2023, 6, 10, 22, 57, 52, 49612000, Pacific.Chatham);
    dt_str = try dt.formatISO8601(allocator, false);
    try testing.expectEqualStrings("2023-06-10T22:57:52+12:45", dt_str);
    allocator.free(dt_str);

    // test microseconds
    dt = try Datetime.create(2023, 6, 10, 5, 57, 52, 49612000, America.Aruba);
    dt_str = try dt.formatISO8601(allocator, true);
    try testing.expectEqualStrings("2023-06-10T05:57:52.049612-04:00", dt_str);
    allocator.free(dt_str);

    // test format buf
    var buf: [64]u8 = undefined;
    dt = try Datetime.create(2023, 6, 10, 14, 6, 40, 15006000, Hongkong);
    dt_str = try dt.formatISO8601Buf(&buf, true);
    try testing.expectEqualStrings("2023-06-10T14:06:40.015006+08:00", dt_str);
}

test "dst-in-different-years" {
    const dt1 = try Datetime.create(2025, 6, 10, 18, 12, 52, 49612000, UTC);
    const new_dt1 = dt1.shiftTimezone(Europe.Amsterdam);
    const dt2 = try Datetime.create(1980, 6, 10, 18, 12, 52, 49612000, UTC);
    const new_dt2 = dt2.shiftTimezone(Europe.Amsterdam);

    try testing.expectEqual(new_dt1.time.hour, new_dt2.time.hour);
    try testing.expectEqual(new_dt1.time.minute, new_dt2.time.minute);
    try testing.expectEqual(new_dt1.time.second, new_dt2.time.second);
}

test "dst-in-different-years-and-months" {
    const dt1 = try Datetime.create(2013, 6, 10, 18, 12, 52, 49612000, UTC);
    const new_dt1 = dt1.shiftTimezone(Europe.Amsterdam);
    const dt2 = try Datetime.create(1990, 2, 10, 18, 12, 52, 49612000, UTC);
    const new_dt2 = dt2.shiftTimezone(Europe.Amsterdam);

    try testing.expectEqual(new_dt1.time.hour, new_dt2.time.hour + 1); // there will be dst active/passive difference
    try testing.expectEqual(new_dt1.time.minute, new_dt2.time.minute);
    try testing.expectEqual(new_dt1.time.second, new_dt2.time.second);
}

// Timezones
pub const Africa = struct {
    pub const Abidjan = create("Africa/Abidjan", 0, .no_dst);
    pub const Accra = create("Africa/Accra", 0, .no_dst);
    pub const Addis_Ababa = create("Africa/Addis_Ababa", 180, .no_dst);
    pub const Algiers = create("Africa/Algiers", 60, .no_dst);
    pub const Asmara = create("Africa/Asmara", 180, .no_dst);
    pub const Bamako = create("Africa/Bamako", 0, .no_dst);
    pub const Bangui = create("Africa/Bangui", 60, .no_dst);
    pub const Banjul = create("Africa/Banjul", 0, .no_dst);
    pub const Bissau = create("Africa/Bissau", 0, .no_dst);
    pub const Blantyre = create("Africa/Blantyre", 120, .no_dst);
    pub const Brazzaville = create("Africa/Brazzaville", 60, .no_dst);
    pub const Bujumbura = create("Africa/Bujumbura", 120, .no_dst);
    pub const Cairo = create("Africa/Cairo", 120, .egypt_daylight_time);
    pub const Casablanca = create("Africa/Casablanca", 60, .no_dst);
    pub const Ceuta = create("Africa/Ceuta", 60, .eastern_european_summer_time);
    pub const Conakry = create("Africa/Conakry", 0, .no_dst);
    pub const Dakar = create("Africa/Dakar", 0, .no_dst);
    pub const Dar_es_Salaam = create("Africa/Dar_es_Salaam", 180, .no_dst);
    pub const Djibouti = create("Africa/Djibouti", 180, .no_dst);
    pub const Douala = create("Africa/Douala", 60, .no_dst);
    pub const El_Aaiun = create("Africa/El_Aaiun", 0, .no_dst);
    pub const Freetown = create("Africa/Freetown", 0, .no_dst);
    pub const Gaborone = create("Africa/Gaborone", 120, .no_dst);
    pub const Harare = create("Africa/Harare", 120, .no_dst);
    pub const Johannesburg = create("Africa/Johannesburg", 120, .no_dst);
    pub const Juba = create("Africa/Juba", 180, .no_dst);
    pub const Kampala = create("Africa/Kampala", 180, .no_dst);
    pub const Khartoum = create("Africa/Khartoum", 120, .no_dst);
    pub const Kigali = create("Africa/Kigali", 120, .no_dst);
    pub const Kinshasa = create("Africa/Kinshasa", 60, .no_dst);
    pub const Lagos = create("Africa/Lagos", 60, .no_dst);
    pub const Libreville = create("Africa/Libreville", 60, .no_dst);
    pub const Lome = create("Africa/Lome", 0, .no_dst);
    pub const Luanda = create("Africa/Luanda", 60, .no_dst);
    pub const Lubumbashi = create("Africa/Lubumbashi", 120, .no_dst);
    pub const Lusaka = create("Africa/Lusaka", 120, .no_dst);
    pub const Malabo = create("Africa/Malabo", 60, .no_dst);
    pub const Maputo = create("Africa/Maputo", 120, .no_dst);
    pub const Maseru = create("Africa/Maseru", 120, .no_dst);
    pub const Mbabane = create("Africa/Mbabane", 120, .no_dst);
    pub const Mogadishu = create("Africa/Mogadishu", 180, .no_dst);
    pub const Monrovia = create("Africa/Monrovia", 0, .no_dst);
    pub const Nairobi = create("Africa/Nairobi", 180, .no_dst);
    pub const Ndjamena = create("Africa/Ndjamena", 60, .no_dst);
    pub const Niamey = create("Africa/Niamey", 60, .no_dst);
    pub const Nouakchott = create("Africa/Nouakchott", 0, .no_dst);
    pub const Ouagadougou = create("Africa/Ouagadougou", 0, .no_dst);
    pub const Porto_Novo = create("Africa/Porto-Novo", 60, .no_dst);
    pub const Sao_Tome = create("Africa/Sao_Tome", 0, .no_dst);
    pub const Timbuktu = create("Africa/Timbuktu", 0, .no_dst);
    pub const Tripoli = create("Africa/Tripoli", 120, .no_dst);
    pub const Tunis = create("Africa/Tunis", 60, .no_dst);
    pub const Windhoek = create("Africa/Windhoek", 120, .no_dst);
};

pub const America = struct {
    pub const Adak = create("America/Adak", -600, .atlantic_daylight_time);
    pub const Anchorage = create("America/Anchorage", -540, .atlantic_daylight_time);
    pub const Anguilla = create("America/Anguilla", -240, .no_dst);
    pub const Antigua = create("America/Antigua", -240, .no_dst);
    pub const Araguaina = create("America/Araguaina", -180, .no_dst);
    pub const Argentina = struct {
        pub const Buenos_Aires = create("America/Argentina/Buenos_Aires", -180, .no_dst);
        pub const Catamarca = create("America/Argentina/Catamarca", -180, .no_dst);
        pub const ComodRivadavia = create("America/Argentina/ComodRivadavia", -180, .no_dst);
        pub const Cordoba = create("America/Argentina/Cordoba", -180, .no_dst);
        pub const Jujuy = create("America/Argentina/Jujuy", -180, .no_dst);
        pub const La_Rioja = create("America/Argentina/La_Rioja", -180, .no_dst);
        pub const Mendoza = create("America/Argentina/Mendoza", -180, .no_dst);
        pub const Rio_Gallegos = create("America/Argentina/Rio_Gallegos", -180, .no_dst);
        pub const Salta = create("America/Argentina/Salta", -180, .no_dst);
        pub const San_Juan = create("America/Argentina/San_Juan", -180, .no_dst);
        pub const San_Luis = create("America/Argentina/San_Luis", -180, .no_dst);
        pub const Tucuman = create("America/Argentina/Tucuman", -180, .no_dst);
        pub const Ushuaia = create("America/Argentina/Ushuaia", -180, .no_dst);
    };
    pub const Aruba = create("America/Aruba", -240, .no_dst);
    pub const Asuncion = create("America/Asuncion", -240, .no_dst);
    pub const Atikokan = create("America/Atikokan", -300, .no_dst);
    pub const Atka = create("America/Atka", -600, .no_dst);
    pub const Bahia = create("America/Bahia", -180, .no_dst);
    pub const Bahia_Banderas = create("America/Bahia_Banderas", -360, .no_dst);
    pub const Barbados = create("America/Barbados", -240, .no_dst);
    pub const Belem = create("America/Belem", -180, .no_dst);
    pub const Belize = create("America/Belize", -360, .no_dst);
    pub const Blanc_Sablon = create("America/Blanc-Sablon", -240, .no_dst);
    pub const Boa_Vista = create("America/Boa_Vista", -240, .no_dst);
    pub const Bogota = create("America/Bogota", -300, .no_dst);
    pub const Boise = create("America/Boise", -420, .atlantic_daylight_time);
    pub const Buenos_Aires = create("America/Buenos_Aires", -180, .no_dst);
    pub const Cambridge_Bay = create("America/Cambridge_Bay", -420, .atlantic_daylight_time);
    pub const Campo_Grande = create("America/Campo_Grande", -240, .no_dst);
    pub const Cancun = create("America/Cancun", -300, .no_dst);
    pub const Caracas = create("America/Caracas", -240, .no_dst);
    pub const Catamarca = create("America/Catamarca", -180, .no_dst);
    pub const Cayenne = create("America/Cayenne", -180, .no_dst);
    pub const Cayman = create("America/Cayman", -300, .no_dst);
    pub const Chicago = create("America/Chicago", -360, .atlantic_daylight_time);
    pub const Chihuahua = create("America/Chihuahua", -420, .no_dst);
    pub const Coral_Harbour = create("America/Coral_Harbour", -300, .no_dst);
    pub const Cordoba = create("America/Cordoba", -180, .no_dst);
    pub const Costa_Rica = create("America/Costa_Rica", -360, .no_dst);
    pub const Creston = create("America/Creston", -420, .no_dst);
    pub const Cuiaba = create("America/Cuiaba", -240, .no_dst);
    pub const Curacao = create("America/Curacao", -240, .no_dst);
    pub const Danmarkshavn = create("America/Danmarkshavn", 0, .no_dst);
    pub const Dawson = create("America/Dawson", -480, .no_dst);
    pub const Dawson_Creek = create("America/Dawson_Creek", -420, .no_dst);
    pub const Denver = create("America/Denver", -420, .atlantic_daylight_time);
    pub const Detroit = create("America/Detroit", -300, .atlantic_daylight_time);
    pub const Dominica = create("America/Dominica", -240, .no_dst);
    pub const Edmonton = create("America/Edmonton", -420, .atlantic_daylight_time);
    pub const Eirunepe = create("America/Eirunepe", -300, .no_dst);
    pub const El_Salvador = create("America/El_Salvador", -360, .no_dst);
    pub const Ensenada = create("America/Ensenada", -480, .no_dst);
    pub const Fort_Nelson = create("America/Fort_Nelson", -420, .no_dst);
    pub const Fort_Wayne = create("America/Fort_Wayne", -300, .no_dst);
    pub const Fortaleza = create("America/Fortaleza", -180, .no_dst);
    pub const Glace_Bay = create("America/Glace_Bay", -240, .atlantic_daylight_time);
    pub const Godthab = create("America/Godthab", -180, .no_dst);
    pub const Goose_Bay = create("America/Goose_Bay", -240, .atlantic_daylight_time);
    pub const Grand_Turk = create("America/Grand_Turk", -300, .atlantic_daylight_time);
    pub const Grenada = create("America/Grenada", -240, .no_dst);
    pub const Guadeloupe = create("America/Guadeloupe", -240, .no_dst);
    pub const Guatemala = create("America/Guatemala", -360, .no_dst);
    pub const Guayaquil = create("America/Guayaquil", -300, .no_dst);
    pub const Guyana = create("America/Guyana", -240, .no_dst);
    pub const Halifax = create("America/Halifax", -240, .atlantic_daylight_time);
    pub const Havana = create("America/Havana", -300, .atlantic_daylight_time);
    pub const Hermosillo = create("America/Hermosillo", -420, .no_dst);
    pub const Indiana = struct {
        // FIXME: Name conflict
        pub const Indianapolis_ = create("America/Indiana/Indianapolis", -300, .atlantic_daylight_time);
        pub const Knox = create("America/Indiana/Knox", -360, .atlantic_daylight_time);
        pub const Marengo = create("America/Indiana/Marengo", -300, .atlantic_daylight_time);
        pub const Petersburg = create("America/Indiana/Petersburg", -300, .atlantic_daylight_time);
        pub const Tell_City = create("America/Indiana/Tell_City", -360, .atlantic_daylight_time);
        pub const Vevay = create("America/Indiana/Vevay", -300, .atlantic_daylight_time);
        pub const Vincennes = create("America/Indiana/Vincennes", -300, .atlantic_daylight_time);
        pub const Winamac = create("America/Indiana/Winamac", -300, .atlantic_daylight_time);
    };
    pub const Indianapolis = create("America/Indianapolis", -300, .no_dst);
    pub const Inuvik = create("America/Inuvik", -420, .atlantic_daylight_time);
    pub const Iqaluit = create("America/Iqaluit", -300, .atlantic_daylight_time);
    pub const Jamaica = create("America/Jamaica", -300, .no_dst);
    pub const Jujuy = create("America/Jujuy", -180, .no_dst);
    pub const Juneau = create("America/Juneau", -540, .atlantic_daylight_time);
    pub const Kentucky = struct {
        // FIXME: Name conflict
        pub const Louisville_ = create("America/Kentucky/Louisville", -300, .atlantic_daylight_time);
        pub const Monticello = create("America/Kentucky/Monticello", -300, .atlantic_daylight_time);
    };
    pub const Knox_IN = create("America/Knox_IN", -360, .no_dst);
    pub const Kralendijk = create("America/Kralendijk", -240, .no_dst);
    pub const La_Paz = create("America/La_Paz", -240, .no_dst);
    pub const Lima = create("America/Lima", -300, .no_dst);
    pub const Los_Angeles = create("America/Los_Angeles", -480, .atlantic_daylight_time);
    pub const Louisville = create("America/Louisville", -300, .no_dst);
    pub const Lower_Princes = create("America/Lower_Princes", -240, .no_dst);
    pub const Maceio = create("America/Maceio", -180, .no_dst);
    pub const Managua = create("America/Managua", -360, .no_dst);
    pub const Manaus = create("America/Manaus", -240, .no_dst);
    pub const Marigot = create("America/Marigot", -240, .no_dst);
    pub const Martinique = create("America/Martinique", -240, .no_dst);
    pub const Matamoros = create("America/Matamoros", -360, .atlantic_daylight_time);
    pub const Mazatlan = create("America/Mazatlan", -420, .no_dst);
    pub const Mendoza = create("America/Mendoza", -180, .no_dst);
    pub const Menominee = create("America/Menominee", -360, .atlantic_daylight_time);
    pub const Merida = create("America/Merida", -360, .no_dst);
    pub const Metlakatla = create("America/Metlakatla", -540, .atlantic_daylight_time);
    pub const Mexico_City = create("America/Mexico_City", -360, .no_dst);
    pub const Miquelon = create("America/Miquelon", -180, .atlantic_daylight_time);
    pub const Moncton = create("America/Moncton", -240, .atlantic_daylight_time);
    pub const Monterrey = create("America/Monterrey", -360, .no_dst);
    pub const Montevideo = create("America/Montevideo", -180, .no_dst);
    pub const Montreal = create("America/Montreal", -300, .no_dst);
    pub const Montserrat = create("America/Montserrat", -240, .no_dst);
    pub const Nassau = create("America/Nassau", -300, .atlantic_daylight_time);
    pub const New_York = create("America/New_York", -300, .atlantic_daylight_time);
    pub const Nipigon = create("America/Nipigon", -300, .no_dst);
    pub const Nome = create("America/Nome", -540, .atlantic_daylight_time);
    pub const Noronha = create("America/Noronha", -120, .no_dst);
    pub const North_Dakota = struct {
        pub const Beulah = create("America/North_Dakota/Beulah", -360, .atlantic_daylight_time);
        pub const Center = create("America/North_Dakota/Center", -360, .atlantic_daylight_time);
        pub const New_Salem = create("America/North_Dakota/New_Salem", -360, .atlantic_daylight_time);
    };
    pub const Ojinaga = create("America/Ojinaga", -420, .atlantic_daylight_time);
    pub const Panama = create("America/Panama", -300, .no_dst);
    pub const Pangnirtung = create("America/Pangnirtung", -300, .no_dst);
    pub const Paramaribo = create("America/Paramaribo", -180, .no_dst);
    pub const Phoenix = create("America/Phoenix", -420, .no_dst);
    pub const Port_of_Spain = create("America/Port_of_Spain", -240, .no_dst);
    pub const Port_au_Prince = create("America/Port-au-Prince", -300, .atlantic_daylight_time);
    pub const Porto_Acre = create("America/Porto_Acre", -300, .no_dst);
    pub const Porto_Velho = create("America/Porto_Velho", -240, .no_dst);
    pub const Puerto_Rico = create("America/Puerto_Rico", -240, .no_dst);
    pub const Punta_Arenas = create("America/Punta_Arenas", -180, .atlantic_daylight_time);
    pub const Rainy_River = create("America/Rainy_River", -360, .no_dst);
    pub const Rankin_Inlet = create("America/Rankin_Inlet", -360, .atlantic_daylight_time);
    pub const Recife = create("America/Recife", -180, .no_dst);
    pub const Regina = create("America/Regina", -360, .no_dst);
    pub const Resolute = create("America/Resolute", -360, .atlantic_daylight_time);
    pub const Rio_Branco = create("America/Rio_Branco", -300, .no_dst);
    pub const Rosario = create("America/Rosario", -180, .no_dst);
    pub const Santa_Isabel = create("America/Santa_Isabel", -480, .no_dst);
    pub const Santarem = create("America/Santarem", -180, .no_dst);
    pub const Santiago = create("America/Santiago", -240, .atlantic_daylight_time);
    pub const Santo_Domingo = create("America/Santo_Domingo", -240, .no_dst);
    pub const Sao_Paulo = create("America/Sao_Paulo", -180, .no_dst);
    pub const Scoresbysund = create("America/Scoresbysund", -60, .atlantic_daylight_time);
    pub const Shiprock = create("America/Shiprock", -420, .no_dst);
    pub const Sitka = create("America/Sitka", -540, .atlantic_daylight_time);
    pub const St_Barthelemy = create("America/St_Barthelemy", -240, .no_dst);
    pub const St_Johns = create("America/St_Johns", -210, .atlantic_daylight_time);
    pub const St_Kitts = create("America/St_Kitts", -240, .no_dst);
    pub const St_Lucia = create("America/St_Lucia", -240, .no_dst);
    pub const St_Thomas = create("America/St_Thomas", -240, .no_dst);
    pub const St_Vincent = create("America/St_Vincent", -240, .no_dst);
    pub const Swift_Current = create("America/Swift_Current", -360, .no_dst);
    pub const Tegucigalpa = create("America/Tegucigalpa", -360, .no_dst);
    pub const Thule = create("America/Thule", -240, .atlantic_daylight_time);
    pub const Thunder_Bay = create("America/Thunder_Bay", -300, .no_dst);
    pub const Tijuana = create("America/Tijuana", -480, .atlantic_daylight_time);
    pub const Toronto = create("America/Toronto", -300, .atlantic_daylight_time);
    pub const Tortola = create("America/Tortola", -240, .no_dst);
    pub const Vancouver = create("America/Vancouver", -480, .atlantic_daylight_time);
    pub const Virgin = create("America/Virgin", -240, .no_dst);
    pub const Whitehorse = create("America/Whitehorse", -480, .no_dst);
    pub const Winnipeg = create("America/Winnipeg", -360, .atlantic_daylight_time);
    pub const Yakutat = create("America/Yakutat", -540, .atlantic_daylight_time);
    pub const Yellowknife = create("America/Yellowknife", -420, .no_dst);
};

pub const Antarctica = struct {
    pub const Casey = create("Antarctica/Casey", 660, .no_dst);
    pub const Davis = create("Antarctica/Davis", 420, .no_dst);
    pub const DumontDUrville = create("Antarctica/DumontDUrville", 600, .no_dst);
    pub const Macquarie = create("Antarctica/Macquarie", 660, .new_zealand_daylight_time);
    pub const Mawson = create("Antarctica/Mawson", 300, .no_dst);
    pub const McMurdo = create("Antarctica/McMurdo", 720, .new_zealand_daylight_time);
    pub const Palmer = create("Antarctica/Palmer", -180, .new_zealand_daylight_time);
    pub const Rothera = create("Antarctica/Rothera", -180, .no_dst);
    pub const South_Pole = create("Antarctica/South_Pole", 720, .no_dst);
    pub const Syowa = create("Antarctica/Syowa", 180, .no_dst);
    pub const Troll = create("Antarctica/Troll", 0, .new_zealand_daylight_time);
    pub const Vostok = create("Antarctica/Vostok", 360, .no_dst);
};

pub const Arctic = struct {
    pub const Longyearbyen = create("Arctic/Longyearbyen", 60, .eastern_european_summer_time);
};

pub const Asia = struct {
    pub const Aden = create("Asia/Aden", 180, .no_dst);
    pub const Almaty = create("Asia/Almaty", 360, .no_dst);
    pub const Amman = create("Asia/Amman", 180, .no_dst);
    pub const Anadyr = create("Asia/Anadyr", 720, .no_dst);
    pub const Aqtau = create("Asia/Aqtau", 300, .no_dst);
    pub const Aqtobe = create("Asia/Aqtobe", 300, .no_dst);
    pub const Ashgabat = create("Asia/Ashgabat", 300, .no_dst);
    pub const Ashkhabad = create("Asia/Ashkhabad", 300, .no_dst);
    pub const Atyrau = create("Asia/Atyrau", 300, .no_dst);
    pub const Baghdad = create("Asia/Baghdad", 180, .no_dst);
    pub const Bahrain = create("Asia/Bahrain", 180, .no_dst);
    pub const Baku = create("Asia/Baku", 240, .no_dst);
    pub const Bangkok = create("Asia/Bangkok", 420, .no_dst);
    pub const Barnaul = create("Asia/Barnaul", 420, .no_dst);
    pub const Beirut = create("Asia/Beirut", 120, .eastern_european_summer_time);
    pub const Bishkek = create("Asia/Bishkek", 360, .no_dst);
    pub const Brunei = create("Asia/Brunei", 480, .no_dst);
    pub const Calcutta = create("Asia/Calcutta", 330, .no_dst);
    pub const Chita = create("Asia/Chita", 540, .no_dst);
    pub const Choibalsan = create("Asia/Choibalsan", 480, .no_dst);
    pub const Chongqing = create("Asia/Chongqing", 480, .no_dst);
    pub const Chungking = create("Asia/Chungking", 480, .no_dst);
    pub const Colombo = create("Asia/Colombo", 330, .no_dst);
    pub const Dacca = create("Asia/Dacca", 360, .no_dst);
    pub const Damascus = create("Asia/Damascus", 180, .no_dst);
    pub const Dhaka = create("Asia/Dhaka", 360, .no_dst);
    pub const Dili = create("Asia/Dili", 540, .no_dst);
    pub const Dubai = create("Asia/Dubai", 240, .no_dst);
    pub const Dushanbe = create("Asia/Dushanbe", 300, .no_dst);
    pub const Famagusta = create("Asia/Famagusta", 120, .eastern_european_summer_time);
    pub const Gaza = create("Asia/Gaza", 120, .no_dst);
    pub const Harbin = create("Asia/Harbin", 480, .no_dst);
    pub const Hebron = create("Asia/Hebron", 120, .no_dst);
    pub const Ho_Chi_Minh = create("Asia/Ho_Chi_Minh", 420, .no_dst);
    pub const Hong_Kong = create("Asia/Hong_Kong", 480, .no_dst);
    pub const Hovd = create("Asia/Hovd", 420, .no_dst);
    pub const Irkutsk = create("Asia/Irkutsk", 480, .no_dst);
    pub const Istanbul = create("Asia/Istanbul", 180, .no_dst);
    pub const Jakarta = create("Asia/Jakarta", 420, .no_dst);
    pub const Jayapura = create("Asia/Jayapura", 540, .no_dst);
    pub const Jerusalem = create("Asia/Jerusalem", 120, .isreal_daylight_time);
    pub const Kabul = create("Asia/Kabul", 270, .no_dst);
    pub const Kamchatka = create("Asia/Kamchatka", 720, .no_dst);
    pub const Karachi = create("Asia/Karachi", 300, .no_dst);
    pub const Kashgar = create("Asia/Kashgar", 360, .no_dst);
    pub const Kathmandu = create("Asia/Kathmandu", 345, .no_dst);
    pub const Katmandu = create("Asia/Katmandu", 345, .no_dst);
    pub const Khandyga = create("Asia/Khandyga", 540, .no_dst);
    pub const Kolkata = create("Asia/Kolkata", 330, .no_dst);
    pub const Krasnoyarsk = create("Asia/Krasnoyarsk", 420, .no_dst);
    pub const Kuala_Lumpur = create("Asia/Kuala_Lumpur", 480, .no_dst);
    pub const Kuching = create("Asia/Kuching", 480, .no_dst);
    pub const Kuwait = create("Asia/Kuwait", 180, .no_dst);
    pub const Macao = create("Asia/Macao", 480, .no_dst);
    pub const Macau = create("Asia/Macau", 480, .no_dst);
    pub const Magadan = create("Asia/Magadan", 660, .no_dst);
    pub const Makassar = create("Asia/Makassar", 480, .no_dst);
    pub const Manila = create("Asia/Manila", 480, .no_dst);
    pub const Muscat = create("Asia/Muscat", 240, .no_dst);
    pub const Nicosia = create("Asia/Nicosia", 120, .eastern_european_summer_time);
    pub const Novokuznetsk = create("Asia/Novokuznetsk", 420, .no_dst);
    pub const Novosibirsk = create("Asia/Novosibirsk", 420, .no_dst);
    pub const Omsk = create("Asia/Omsk", 360, .no_dst);
    pub const Oral = create("Asia/Oral", 300, .no_dst);
    pub const Phnom_Penh = create("Asia/Phnom_Penh", 420, .no_dst);
    pub const Pontianak = create("Asia/Pontianak", 420, .no_dst);
    pub const Pyongyang = create("Asia/Pyongyang", 540, .no_dst);
    pub const Qatar = create("Asia/Qatar", 180, .no_dst);
    pub const Qyzylorda = create("Asia/Qyzylorda", 300, .no_dst);
    pub const Rangoon = create("Asia/Rangoon", 390, .no_dst);
    pub const Riyadh = create("Asia/Riyadh", 180, .no_dst);
    pub const Saigon = create("Asia/Saigon", 420, .no_dst);
    pub const Sakhalin = create("Asia/Sakhalin", 660, .no_dst);
    pub const Samarkand = create("Asia/Samarkand", 300, .no_dst);
    pub const Seoul = create("Asia/Seoul", 540, .no_dst);
    pub const Shanghai = create("Asia/Shanghai", 480, .no_dst);
    pub const Singapore = create("Asia/Singapore", 480, .no_dst);
    pub const Srednekolymsk = create("Asia/Srednekolymsk", 660, .no_dst);
    pub const Taipei = create("Asia/Taipei", 480, .no_dst);
    pub const Tashkent = create("Asia/Tashkent", 300, .no_dst);
    pub const Tbilisi = create("Asia/Tbilisi", 240, .no_dst);
    pub const Tehran = create("Asia/Tehran", 210, .no_dst);
    pub const Tel_Aviv = create("Asia/Tel_Aviv", 120, .isreal_daylight_time);
    pub const Thimbu = create("Asia/Thimbu", 360, .no_dst);
    pub const Thimphu = create("Asia/Thimphu", 360, .no_dst);
    pub const Tokyo = create("Asia/Tokyo", 540, .no_dst);
    pub const Tomsk = create("Asia/Tomsk", 420, .no_dst);
    pub const Ujung_Pandang = create("Asia/Ujung_Pandang", 480, .no_dst);
    pub const Ulaanbaatar = create("Asia/Ulaanbaatar", 480, .no_dst);
    pub const Ulan_Bator = create("Asia/Ulan_Bator", 480, .no_dst);
    pub const Urumqi = create("Asia/Urumqi", 360, .no_dst);
    pub const Ust_Nera = create("Asia/Ust-Nera", 600, .no_dst);
    pub const Vientiane = create("Asia/Vientiane", 420, .no_dst);
    pub const Vladivostok = create("Asia/Vladivostok", 600, .no_dst);
    pub const Yakutsk = create("Asia/Yakutsk", 540, .no_dst);
    pub const Yangon = create("Asia/Yangon", 390, .no_dst);
    pub const Yekaterinburg = create("Asia/Yekaterinburg", 300, .no_dst);
    pub const Yerevan = create("Asia/Yerevan", 240, .no_dst);
};

pub const Atlantic = struct {
    pub const Azores = create("Atlantic/Azores", -60, .eastern_european_summer_time);
    pub const Bermuda = create("Atlantic/Bermuda", -240, .atlantic_daylight_time);
    pub const Canary = create("Atlantic/Canary", 0, .eastern_european_summer_time);
    pub const Cape_Verde = create("Atlantic/Cape_Verde", -60, .no_dst);
    pub const Faeroe = create("Atlantic/Faeroe", 0, .no_dst);
    pub const Faroe = create("Atlantic/Faroe", 0, .eastern_european_summer_time);
    pub const Jan_Mayen = create("Atlantic/Jan_Mayen", 60, .no_dst);
    pub const Madeira = create("Atlantic/Madeira", 0, .eastern_european_summer_time);
    pub const Reykjavik = create("Atlantic/Reykjavik", 0, .no_dst);
    pub const South_Georgia = create("Atlantic/South_Georgia", -120, .no_dst);
    pub const St_Helena = create("Atlantic/St_Helena", 0, .no_dst);
    pub const Stanley = create("Atlantic/Stanley", -180, .no_dst);
};

pub const Australia = struct {
    pub const ACT = create("Australia/ACT", 600, .no_dst);
    pub const Adelaide = create("Australia/Adelaide", 570, .australian_central_daylight_time);
    pub const Brisbane = create("Australia/Brisbane", 600, .no_dst);
    pub const Broken_Hill = create("Australia/Broken_Hill", 570, .australian_central_daylight_time);
    pub const Canberra = create("Australia/Canberra", 600, .no_dst);
    pub const Currie = create("Australia/Currie", 600, .no_dst);
    pub const Darwin = create("Australia/Darwin", 570, .no_dst);
    pub const Eucla = create("Australia/Eucla", 525, .no_dst);
    pub const Hobart = create("Australia/Hobart", 600, .australian_central_daylight_time);
    pub const LHI = create("Australia/LHI", 630, .no_dst);
    pub const Lindeman = create("Australia/Lindeman", 600, .no_dst);
    pub const Lord_Howe = create("Australia/Lord_Howe", 630, .lord_howe_summer_time);
    pub const Melbourne = create("Australia/Melbourne", 600, .australian_central_daylight_time);
    pub const North = create("Australia/North", 570, .no_dst);
    pub const NSW = create("Australia/NSW", 600, .no_dst);
    pub const Perth = create("Australia/Perth", 480, .no_dst);
    pub const Queensland = create("Australia/Queensland", 600, .no_dst);
    pub const South = create("Australia/South", 570, .no_dst);
    pub const Sydney = create("Australia/Sydney", 600, .australian_central_daylight_time);
    pub const Tasmania = create("Australia/Tasmania", 600, .no_dst);
    pub const Victoria = create("Australia/Victoria", 600, .no_dst);
    pub const West = create("Australia/West", 480, .no_dst);
    pub const Yancowinna = create("Australia/Yancowinna", 570, .no_dst);
};

pub const Brazil = struct {
    pub const Acre = create("Brazil/Acre", -300, .no_dst);
    pub const DeNoronha = create("Brazil/DeNoronha", -120, .no_dst);
    pub const East = create("Brazil/East", -180, .no_dst);
    pub const West = create("Brazil/West", -240, .no_dst);
};

pub const Canada = struct {
    pub const Atlantic = create("Canada/Atlantic", -240, .no_dst);
    pub const Central = create("Canada/Central", -360, .no_dst);
    pub const Eastern = create("Canada/Eastern", -300, .no_dst);
    pub const Mountain = create("Canada/Mountain", -420, .no_dst);
    pub const Newfoundland = create("Canada/Newfoundland", -210, .no_dst);
    pub const Pacific = create("Canada/Pacific", -480, .no_dst);
    pub const Saskatchewan = create("Canada/Saskatchewan", -360, .no_dst);
    pub const Yukon = create("Canada/Yukon", -480, .no_dst);
};
pub const CET = create("CET", 60, .no_dst);

pub const Chile = struct {
    pub const Continental = create("Chile/Continental", -240, .chile_summer_time);
    pub const EasterIsland = create("Chile/EasterIsland", -360, .eastern_island_summer_time);
};
pub const CST6CDT = create("CST6CDT", -360, .no_dst);
pub const Cuba = create("Cuba", -300, .no_dst);
pub const EET = create("EET", 120, .no_dst);
pub const Egypt = create("Egypt", 120, .egypt_daylight_time);
pub const Eire = create("Eire", 0, .no_dst);
pub const EST = create("EST", -300, .no_dst);
pub const EST5EDT = create("EST5EDT", -300, .no_dst);

pub const Etc = struct {
    // NOTE: The signs are intentionally inverted. See the Etc area description.
    pub const GMT = create("Etc/GMT", 0, .no_dst);
    pub const GMTp0 = create("Etc/GMT+0", 0, .no_dst);
    pub const GMTp1 = create("Etc/GMT+1", -60, .no_dst);
    pub const GMTp10 = create("Etc/GMT+10", -600, .no_dst);
    pub const GMTp11 = create("Etc/GMT+11", -660, .no_dst);
    pub const GMTp12 = create("Etc/GMT+12", -720, .no_dst);
    pub const GMTp2 = create("Etc/GMT+2", -120, .no_dst);
    pub const GMTp3 = create("Etc/GMT+3", -180, .no_dst);
    pub const GMTp4 = create("Etc/GMT+4", -240, .no_dst);
    pub const GMTp5 = create("Etc/GMT+5", -300, .no_dst);
    pub const GMTp6 = create("Etc/GMT+6", -360, .no_dst);
    pub const GMTp7 = create("Etc/GMT+7", -420, .no_dst);
    pub const GMTp8 = create("Etc/GMT+8", -480, .no_dst);
    pub const GMTp9 = create("Etc/GMT+9", -540, .no_dst);
    pub const GMT0 = create("Etc/GMT0", 0, .no_dst);
    pub const GMTm0 = create("Etc/GMT-0", 0, .no_dst);
    pub const GMTm1 = create("Etc/GMT-1", 60, .no_dst);
    pub const GMTm10 = create("Etc/GMT-10", 600, .no_dst);
    pub const GMTm11 = create("Etc/GMT-11", 660, .no_dst);
    pub const GMTm12 = create("Etc/GMT-12", 720, .no_dst);
    pub const GMTm13 = create("Etc/GMT-13", 780, .no_dst);
    pub const GMTm14 = create("Etc/GMT-14", 840, .no_dst);
    pub const GMTm2 = create("Etc/GMT-2", 120, .no_dst);
    pub const GMTm3 = create("Etc/GMT-3", 180, .no_dst);
    pub const GMTm4 = create("Etc/GMT-4", 240, .no_dst);
    pub const GMTm5 = create("Etc/GMT-5", 300, .no_dst);
    pub const GMTm6 = create("Etc/GMT-6", 360, .no_dst);
    pub const GMTm7 = create("Etc/GMT-7", 420, .no_dst);
    pub const GMTm8 = create("Etc/GMT-8", 480, .no_dst);
    pub const GMTm9 = create("Etc/GMT-9", 540, .no_dst);
    pub const Greenwich = create("Etc/Greenwich", 0, .no_dst);
    pub const UCT = create("Etc/UCT", 0, .no_dst);
    pub const Universal = create("Etc/Universal", 0, .no_dst);
    pub const UTC = create("Etc/UTC", 0, .no_dst);
    pub const Zulu = create("Etc/Zulu", 0, .no_dst);
};

pub const Europe = struct {
    pub const Amsterdam = create("Europe/Amsterdam", 60, .eastern_european_summer_time);
    pub const Andorra = create("Europe/Andorra", 60, .eastern_european_summer_time);
    pub const Astrakhan = create("Europe/Astrakhan", 240, .no_dst);
    pub const Athens = create("Europe/Athens", 120, .eastern_european_summer_time);
    pub const Belfast = create("Europe/Belfast", 0, .no_dst);
    pub const Belgrade = create("Europe/Belgrade", 60, .eastern_european_summer_time);
    pub const Berlin = create("Europe/Berlin", 60, .eastern_european_summer_time);
    pub const Bratislava = create("Europe/Bratislava", 60, .eastern_european_summer_time);
    pub const Brussels = create("Europe/Brussels", 60, .eastern_european_summer_time);
    pub const Bucharest = create("Europe/Bucharest", 120, .eastern_european_summer_time);
    pub const Budapest = create("Europe/Budapest", 60, .eastern_european_summer_time);
    pub const Busingen = create("Europe/Busingen", 60, .eastern_european_summer_time);
    pub const Chisinau = create("Europe/Chisinau", 120, .eastern_european_summer_time);
    pub const Copenhagen = create("Europe/Copenhagen", 60, .eastern_european_summer_time);
    pub const Dublin = create("Europe/Dublin", 0, .eastern_european_summer_time);
    pub const Gibraltar = create("Europe/Gibraltar", 60, .eastern_european_summer_time);
    pub const Guernsey = create("Europe/Guernsey", 0, .eastern_european_summer_time);
    pub const Helsinki = create("Europe/Helsinki", 120, .eastern_european_summer_time);
    pub const Isle_of_Man = create("Europe/Isle_of_Man", 0, .eastern_european_summer_time);
    pub const Istanbul = create("Europe/Istanbul", 180, .no_dst);
    pub const Jersey = create("Europe/Jersey", 0, .eastern_european_summer_time);
    pub const Kaliningrad = create("Europe/Kaliningrad", 120, .no_dst);
    pub const Kiev = create("Europe/Kiev", 120, .no_dst);
    pub const Kirov = create("Europe/Kirov", 180, .no_dst);
    pub const Lisbon = create("Europe/Lisbon", 0, .eastern_european_summer_time);
    pub const Ljubljana = create("Europe/Ljubljana", 60, .eastern_european_summer_time);
    pub const London = create("Europe/London", 0, .eastern_european_summer_time);
    pub const Luxembourg = create("Europe/Luxembourg", 60, .eastern_european_summer_time);
    pub const Madrid = create("Europe/Madrid", 60, .eastern_european_summer_time);
    pub const Malta = create("Europe/Malta", 60, .eastern_european_summer_time);
    pub const Mariehamn = create("Europe/Mariehamn", 120, .eastern_european_summer_time);
    pub const Minsk = create("Europe/Minsk", 180, .no_dst);
    pub const Monaco = create("Europe/Monaco", 60, .eastern_european_summer_time);
    pub const Moscow = create("Europe/Moscow", 180, .no_dst);
    pub const Oslo = create("Europe/Oslo", 60, .eastern_european_summer_time);
    pub const Paris = create("Europe/Paris", 60, .eastern_european_summer_time);
    pub const Podgorica = create("Europe/Podgorica", 60, .eastern_european_summer_time);
    pub const Prague = create("Europe/Prague", 60, .eastern_european_summer_time);
    pub const Riga = create("Europe/Riga", 120, .eastern_european_summer_time);
    pub const Rome = create("Europe/Rome", 60, .eastern_european_summer_time);
    pub const Samara = create("Europe/Samara", 240, .no_dst);
    pub const San_Marino = create("Europe/San_Marino", 60, .eastern_european_summer_time);
    pub const Sarajevo = create("Europe/Sarajevo", 60, .eastern_european_summer_time);
    pub const Saratov = create("Europe/Saratov", 240, .no_dst);
    pub const Simferopol = create("Europe/Simferopol", 180, .no_dst);
    pub const Skopje = create("Europe/Skopje", 60, .eastern_european_summer_time);
    pub const Sofia = create("Europe/Sofia", 120, .eastern_european_summer_time);
    pub const Stockholm = create("Europe/Stockholm", 60, .eastern_european_summer_time);
    pub const Tallinn = create("Europe/Tallinn", 120, .eastern_european_summer_time);
    pub const Tirane = create("Europe/Tirane", 60, .eastern_european_summer_time);
    pub const Tiraspol = create("Europe/Tiraspol", 120, .no_dst);
    pub const Ulyanovsk = create("Europe/Ulyanovsk", 240, .no_dst);
    pub const Uzhgorod = create("Europe/Uzhgorod", 120, .no_dst);
    pub const Vaduz = create("Europe/Vaduz", 60, .eastern_european_summer_time);
    pub const Vatican = create("Europe/Vatican", 60, .eastern_european_summer_time);
    pub const Vienna = create("Europe/Vienna", 60, .eastern_european_summer_time);
    pub const Vilnius = create("Europe/Vilnius", 120, .eastern_european_summer_time);
    pub const Volgograd = create("Europe/Volgograd", 240, .no_dst);
    pub const Warsaw = create("Europe/Warsaw", 60, .eastern_european_summer_time);
    pub const Zagreb = create("Europe/Zagreb", 60, .eastern_european_summer_time);
    pub const Zaporozhye = create("Europe/Zaporozhye", 120, .no_dst);
    pub const Zurich = create("Europe/Zurich", 60, .eastern_european_summer_time);
};
pub const GB = create("GB", 0, .no_dst);
pub const GB_Eire = create("GB-Eire", 0, .no_dst);
pub const GMT = create("GMT", 0, .no_dst);
pub const GMTp0 = create("GMT+0", 0, .no_dst);
pub const GMT0 = create("GMT0", 0, .no_dst);
pub const GMTm0 = create("GMT-0", 0, .no_dst);
pub const Greenwich = create("Greenwich", 0, .no_dst);
pub const Hongkong = create("Hongkong", 480, .no_dst);
pub const HST = create("HST", -600, .no_dst);
pub const Iceland = create("Iceland", 0, .no_dst);

pub const Indian = struct {
    pub const Antananarivo = create("Indian/Antananarivo", 180, .no_dst);
    pub const Chagos = create("Indian/Chagos", 360, .no_dst);
    pub const Christmas = create("Indian/Christmas", 420, .no_dst);
    pub const Cocos = create("Indian/Cocos", 390, .no_dst);
    pub const Comoro = create("Indian/Comoro", 180, .no_dst);
    pub const Kerguelen = create("Indian/Kerguelen", 300, .no_dst);
    pub const Mahe = create("Indian/Mahe", 240, .no_dst);
    pub const Maldives = create("Indian/Maldives", 300, .no_dst);
    pub const Mauritius = create("Indian/Mauritius", 240, .no_dst);
    pub const Mayotte = create("Indian/Mayotte", 180, .no_dst);
    pub const Reunion = create("Indian/Reunion", 240, .no_dst);
};
pub const Iran = create("Iran", 210, .no_dst);
pub const Israel = create("Israel", 120, .isreal_daylight_time);
pub const Jamaica = create("Jamaica", -300, .no_dst);
pub const Japan = create("Japan", 540, .no_dst);
pub const Kwajalein = create("Kwajalein", 720, .no_dst);
pub const Libya = create("Libya", 120, .no_dst);
pub const MET = create("MET", 60, .no_dst);

pub const Mexico = struct {
    pub const BajaNorte = create("Mexico/BajaNorte", -480, .no_dst);
    pub const BajaSur = create("Mexico/BajaSur", -420, .no_dst);
    pub const General = create("Mexico/General", -360, .no_dst);
};
pub const MST = create("MST", -420, .no_dst);
pub const MST7MDT = create("MST7MDT", -420, .no_dst);
pub const Navajo = create("Navajo", -420, .no_dst);
pub const NZ = create("NZ", 720, .no_dst);
pub const NZ_CHAT = create("NZ-CHAT", 765, .no_dst);

pub const Pacific = struct {
    pub const Apia = create("Pacific/Apia", 780, .no_dst);
    pub const Auckland = create("Pacific/Auckland", 720, .new_zealand_daylight_time);
    pub const Bougainville = create("Pacific/Bougainville", 660, .no_dst);
    pub const Chatham = create("Pacific/Chatham", 765, .new_zealand_daylight_time);
    pub const Chuuk = create("Pacific/Chuuk", 600, .no_dst);
    pub const Easter = create("Pacific/Easter", -360, .eastern_island_summer_time);
    pub const Efate = create("Pacific/Efate", 660, .no_dst);
    pub const Enderbury = create("Pacific/Enderbury", 780, .no_dst);
    pub const Fakaofo = create("Pacific/Fakaofo", 780, .no_dst);
    pub const Fiji = create("Pacific/Fiji", 720, .no_dst);
    pub const Funafuti = create("Pacific/Funafuti", 720, .no_dst);
    pub const Galapagos = create("Pacific/Galapagos", -360, .no_dst);
    pub const Gambier = create("Pacific/Gambier", -540, .no_dst);
    pub const Guadalcanal = create("Pacific/Guadalcanal", 660, .no_dst);
    pub const Guam = create("Pacific/Guam", 600, .no_dst);
    pub const Honolulu = create("Pacific/Honolulu", -600, .no_dst);
    pub const Johnston = create("Pacific/Johnston", -600, .no_dst);
    pub const Kiritimati = create("Pacific/Kiritimati", 840, .no_dst);
    pub const Kosrae = create("Pacific/Kosrae", 660, .no_dst);
    pub const Kwajalein = create("Pacific/Kwajalein", 720, .no_dst);
    pub const Majuro = create("Pacific/Majuro", 720, .no_dst);
    pub const Marquesas = create("Pacific/Marquesas", -570, .no_dst);
    pub const Midway = create("Pacific/Midway", -660, .no_dst);
    pub const Nauru = create("Pacific/Nauru", 720, .no_dst);
    pub const Niue = create("Pacific/Niue", -660, .no_dst);
    pub const Norfolk = create("Pacific/Norfolk", 660, .australian_central_daylight_time);
    pub const Noumea = create("Pacific/Noumea", 660, .no_dst);
    pub const Pago_Pago = create("Pacific/Pago_Pago", -660, .no_dst);
    pub const Palau = create("Pacific/Palau", 540, .no_dst);
    pub const Pitcairn = create("Pacific/Pitcairn", -480, .no_dst);
    pub const Pohnpei = create("Pacific/Pohnpei", 660, .no_dst);
    pub const Ponape = create("Pacific/Ponape", 660, .no_dst);
    pub const Port_Moresby = create("Pacific/Port_Moresby", 600, .no_dst);
    pub const Rarotonga = create("Pacific/Rarotonga", -600, .no_dst);
    pub const Saipan = create("Pacific/Saipan", 600, .no_dst);
    pub const Samoa = create("Pacific/Samoa", -660, .no_dst);
    pub const Tahiti = create("Pacific/Tahiti", -600, .no_dst);
    pub const Tarawa = create("Pacific/Tarawa", 720, .no_dst);
    pub const Tongatapu = create("Pacific/Tongatapu", 780, .no_dst);
    pub const Truk = create("Pacific/Truk", 600, .no_dst);
    pub const Wake = create("Pacific/Wake", 720, .no_dst);
    pub const Wallis = create("Pacific/Wallis", 720, .no_dst);
    pub const Yap = create("Pacific/Yap", 600, .no_dst);
};
pub const Poland = create("Poland", 60, .no_dst);
pub const Portugal = create("Portugal", 0, .no_dst);
pub const PRC = create("PRC", 480, .no_dst);
pub const PST8PDT = create("PST8PDT", -480, .no_dst);
pub const ROC = create("ROC", 480, .no_dst);
pub const ROK = create("ROK", 540, .no_dst);
pub const Singapore = create("Singapore", 480, .no_dst);
pub const Turkey = create("Turkey", 180, .no_dst);
pub const UCT = create("UCT", 0, .no_dst);
pub const Universal = create("Universal", 0, .no_dst);

pub const US = struct {
    pub const Alaska = create("US/Alaska", -540, .no_dst);
    pub const Aleutian = create("US/Aleutian", -600, .no_dst);
    pub const Arizona = create("US/Arizona", -420, .no_dst);
    pub const Central = create("US/Central", -360, .no_dst);
    pub const Eastern = create("US/Eastern", -300, .no_dst);
    pub const East_Indiana = create("US/East-Indiana", -300, .no_dst);
    pub const Hawaii = create("US/Hawaii", -600, .no_dst);
    pub const Indiana_Starke = create("US/Indiana-Starke", -360, .no_dst);
    pub const Michigan = create("US/Michigan", -300, .no_dst);
    pub const Mountain = create("US/Mountain", -420, .no_dst);
    pub const Pacific = create("US/Pacific", -480, .no_dst);
    pub const Pacific_New = create("US/Pacific-New", -480, .no_dst);
    pub const Samoa = create("US/Samoa", -660, .no_dst);
};
pub const UTC = create("UTC", 0, .no_dst);
pub const WET = create("WET", 0, .eastern_european_summer_time);
pub const W_SU = create("W-SU", 180, .no_dst);
pub const Zulu = create("Zulu", 0, .no_dst);

inline fn findWithinTimezones(comptime Type: type, timezone: []const u8) ?Timezone {
    const info = @typeInfo(Type);
    switch (info) {
        .@"enum" => |enum_info| {
            inline for (enum_info.decls) |T| {
                const it = @field(Type, T.name);
                if (@TypeOf(it) == Timezone and std.mem.eql(u8, it.name, timezone)) {
                    return it;
                }
                if (@TypeOf(it) == type) {
                    const found = findWithinTimezones(it, timezone);
                    if (found != null)
                        return found;
                }
            }
        },
        else => {},
    }
    return null;
}

pub fn getByName(timezone: []const u8) !Timezone {
    return findWithinTimezones(@This(), timezone) orelse
        error.InvalidTimeZone;
}

test "timezone-get" {
    //try testing.expect(get("America/New_York").? == America.New_York);
    try testing.expect(America.New_York.offset == -300);
}
