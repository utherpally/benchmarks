# benchmarks

A fork of https://github.com/Hejsil/zig-bench has been created with a simpler API, achieved by using anonymous struct literals.


## Usage


```zig
fn run_benchmark() !void {
    try benchmarks(.{
        // Number of warmup runs before starting the benchmark.
        // The purpose of warmup is to let the program/system warm up to a steady state, so that the actual benchmark results will be more accurate.
        // Default: 100
        //.warmup = 10

        // Number of actual benchmark runs to be performed.
        // The larger the number, the more accurate the benchmark results will be, but it will also take longer to run.
        // Default: 10_000
        //.runs = 100

        // Output writer for the benchmark results.
        // Default: std.io.getStdOut().writer()
        //.writer = std.io.null_writer,

        // A set of ArgsTuple that will be passed to the benchmark function for each run.
        // In this case, it contains two sets of arguments: { 1, 2 } and { 10, 3 }.
        .args = .{
            .{ 1, 2 },
            .{ 10, 3 },
        },
        // Contains the labels for each set of arguments in the "args" field.
        // It is used to provide descriptive names for each set of arguments in the benchmark results,
        // making it easier to understand the results of the benchmark.
        // If ".arg_labels" is not specified, the benchmark will use an index-based labeling system to identify each set of arguments.
        // Note: the remaining argument tuples (len(arg_labels) < len(args)) will be labeled using a continuous index-based approach
        // .arg_labels = .{},

        // The functions to bench 
        .add = add,
        .@"Add 2 numbers" = add
    });
}
```


Note: This `build.zig` uses Zig version `0.11.0-dev.1586+2d017f37` for building.