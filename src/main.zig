const std = @import("std");

const Field = std.builtin.Type.StructField;

const GAP = 2;
const COLS = 8;
const padding = &[_]u8{' '} ** GAP;
const Widths = [COLS]u64;

pub const BenchmarkOptions = struct {
    warmup: u32,
    runs: u32,
};

pub const BenchmarkResult = struct {
    name: []const u8,
    options: BenchmarkOptions,
    median: u64,
    mean: u64,
    min: u64,
    max: u64,
    total: u64,
};

pub fn benchmarks(opts: anytype) !void {
    const T = @TypeOf(opts);
    const typeInfo = @typeInfo(T);
    if (typeInfo != .Struct) @compileError("struct required");
    const info = typeInfo.Struct;
    const warmup = if (@hasField(T, "warmup")) opts.warmup else 100;
    const runs = if (@hasField(T, "runs")) opts.runs else 10_000;
    const args = if (@hasField(T, "args")) opts.args else [_]std.meta.Tuple(&[_]type{}){.{}};
    const lbls = if (@hasField(T, "arg_labels")) opts.arg_labels else .{};
    const writer = if (@hasField(T, "writer")) opts.writer else std.io.getStdOut().writer();

    var labels: [lbls.len][]const u8 = undefined;

    inline for (lbls) |lbl, i| {
        labels[i] = lbl;
    }

    const functions = comptime blk: {
        var res: []const Field = &[_]Field{};
        for (info.fields) |field| {
            if (@typeInfo(field.type) != .Fn)
                continue;
            res = res ++ [_]Field{field};
        }

        break :blk res;
    };
    if (functions.len == 0) @compileError("No benchmarks to run.");
    if (args.len == 0) @compileError("At least 1 args to run.");

    var samples: [functions.len * args.len]BenchmarkResult = undefined;

    const bench_opts = @as(BenchmarkOptions, .{ .warmup = warmup, .runs = runs });
    var i: usize = 0;
    inline for (functions) |field| {
        const func = @field(opts, field.name);
        inline for (args) |arg| {
            samples[i] = try benchmark(field.name, func, arg, bench_opts);
            i += 1;
        }
    }

    const min_widths = try printResults(std.io.null_writer, args.len, [_]u64{0} ** COLS, &samples, labels);
    _ = try printResults(writer, args.len, min_widths, &samples, labels);
}

pub fn benchmark(
    name: []const u8,
    comptime func: anytype,
    args: std.meta.ArgsTuple(@TypeOf(func)),
    options: BenchmarkOptions,
) !BenchmarkResult {
    var count: usize = 0;
    while (count < options.warmup) : (count += 1) {
        invoke(func, args);
    }
    var total: usize = 0;
    var min: u64 = if (options.runs > 0) std.math.maxInt(u64) else 0;
    var max: u64 = 0;
    var timer = try std.time.Timer.start();
    var median: u64 = 0;
    const half = options.runs / 2;
    count = 0;
    while (count < options.runs) : (count += 1) {
        const start = timer.read();
        invoke(func, args);
        const time = timer.read() - start;
        total += time;
        if (time > max) max = time;
        if (time < min) min = time;
        if (count == half) median = time;
    }
    const mean = @divFloor(total, options.runs);
    return .{
        .name = name,
        .mean = mean,
        .min = min,
        .max = max,
        .median = median,
        .total = total,
        .options = options,
    };
}

fn printResultDivider(writer: anytype, min_widths: Widths) !void {
    for (min_widths) |w|
        try writer.writeByteNTimes('-', w);
    try writer.writeByteNTimes('-', (min_widths.len - 1) * @as(u32, GAP));
    try writer.writeAll("\n");
}

fn printResultHeader(writer: anytype, min_widths: Widths) !Widths {
    const name_len = try printCell(writer, "{s}", .{"Benchmark"}, .{ .dir = .left, .width = min_widths[0] });
    const warmup_len = try printCell(writer, "{s}", .{"Warmup"}, .{ .width = min_widths[1] });
    const runs_len = try printCell(writer, "{s}", .{"Runs"}, .{ .width = min_widths[2] });
    const min_len = try printCell(writer, "{s}", .{"Min(ns)"}, .{ .width = min_widths[3] });
    const max_len = try printCell(writer, "{s}", .{"Max(ns)"}, .{ .width = min_widths[4] });
    const mean_len = try printCell(writer, "{s}", .{"Mean(ns)"}, .{ .width = min_widths[5] });
    const median_len = try printCell(writer, "{s}", .{"Median(ns)"}, .{ .width = min_widths[6] });
    const total_len = try printCell(writer, "{s}", .{"Total"}, .{ .width = min_widths[7], .last = true });
    try writer.writeAll("\n");
    return Widths{
        name_len,
        warmup_len,
        runs_len,
        min_len,
        max_len,
        mean_len,
        median_len,
        total_len,
    };
}

fn printResult(
    writer: anytype,
    min_widths: Widths,
    label: []const u8,
    result: BenchmarkResult,
) !Widths {
    const name_len = try printCell(writer, "{s}{s}{s}{s}", .{
        result.name,
        "("[0..@boolToInt(label.len != 0)],
        label,
        ")"[0..@boolToInt(label.len != 0)],
    }, .{ .dir = .left, .width = min_widths[0] });

    const warmup_len = try printCell(writer, "{}", .{result.options.warmup}, .{ .width = min_widths[1] });
    const runs_len = try printCell(writer, "{}", .{result.options.runs}, .{ .width = min_widths[2] });
    const min_len = try printCell(writer, "{}", .{result.min}, .{ .width = min_widths[3] });
    const max_len = try printCell(writer, "{}", .{result.max}, .{ .width = min_widths[4] });
    const mean_len = try printCell(writer, "{}", .{result.mean}, .{ .width = min_widths[5] });
    const median_len = try printCell(writer, "{}", .{result.median}, .{ .width = min_widths[6] });

    // Workaroud for fmtDuration only write to fixedBufferStream error
    var buf: [24]u8 = undefined;
    const slice = try std.fmt.bufPrint(&buf, "{}", .{std.fmt.fmtDuration(result.total)});
    const total_len = try printCell(writer, "{s}", .{slice}, .{ .width = min_widths[7], .last = true });

    try writer.writeAll("\n");

    return Widths{
        name_len,
        warmup_len,
        runs_len,
        min_len,
        max_len,
        mean_len,
        median_len,
        total_len,
    };
}

fn printResults(writer: anytype, args_len: usize, min_widths: Widths, samples: []BenchmarkResult, labels: anytype) !Widths {
    var actual_widths = try printResultHeader(writer, min_widths);
    var buf: [20]u8 = undefined; // "{d}", maxInt(usize)
    for (samples) |s, i| {
        const arg_index = i % args_len;
        if (arg_index == 0) try printResultDivider(writer, min_widths);
        const label = blk: {
            if (arg_index < labels.len or (labels.len == 0 or args_len == 1)) {
                break :blk if (labels.len == 0 or args_len == 1) "" else labels[arg_index];
            } else {
                break :blk std.fmt.bufPrint(&buf, "{d}", .{arg_index}) catch @panic("buffer overflow");
            }
        };
        const row = try printResult(writer, min_widths, label, s);
        inline for (.{ 0, 1, 2, 3, 4, 5, 6, 7 }) |idx| {
            if (actual_widths[idx] < row[idx]) actual_widths[idx] = row[idx];
        }
    }

    return actual_widths;
}

const CellOptions = struct {
    dir: enum { left, right } = .right,
    width: u64,
    last: bool = false,
};

fn printCell(writer: anytype, comptime fmt: []const u8, args: anytype, options: CellOptions) !u64 {
    const value_len = std.fmt.count(fmt, args);

    var cow = std.io.countingWriter(writer);
    if (options.dir == .right)
        try cow.writer().writeByteNTimes(' ', std.math.sub(u64, options.width, value_len) catch 0);
    try cow.writer().print(fmt, args);
    if (options.dir == .left)
        try cow.writer().writeByteNTimes(' ', std.math.sub(u64, options.width, value_len) catch 0);
    if (!options.last) try writer.writeAll(padding);
    return cow.bytes_written;
}

fn invoke(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) void {
    const ReturnType = @typeInfo(@TypeOf(func)).Fn.return_type.?;
    switch (@typeInfo(ReturnType)) {
        .ErrorUnion => {
            _ = @call(.never_inline, func, args) catch {};
        },
        else => _ = @call(.never_inline, func, args),
    }
}

fn add(a: u64, b: u64) u64 {
    return a + b;
}

fn test_no_params() void {}

test "internal" {
    try benchmarks(.{
        //.warmup = 10
        //.runs = 100
        //.writer = std.io.null_writer,
        // Args contains a tuple of argstuple, will pass to benchmark function to runs
        .args = .{
            .{ 1, 2 },
            .{ 10, 3 },
        },
        // Label add after benchmark name (default: index-based order)
        // if arg_labels.len < args.len, the remaining using continuos index-based order
        //
        .arg_labels = .{},

        // The functions to bench
        .add = add,
        // .@"Add 2 numbers" = sum_slice
    });

    var args = [_]std.meta.ArgsTuple(@TypeOf(add)){
        .{ 1, 2 },
        .{ 10, 3 },
    };
    try benchmarks(.{
        .args = &args,
        .add = add,
    });

    try benchmarks(.{ .test_no_params = test_no_params });

    var cases = .{ .test_no_params = test_no_params };
    try benchmarks(cases);
}
