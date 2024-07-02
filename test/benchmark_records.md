# Benchmark Records

A record of benchmarks from various versions of `stable_hash`

# Version 1.0

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio
     │ SubStrin…   SubStrin…  String      String      Float64
─────┼───────────────────────────────────────────────────────────
    1 │ structs     crc        78.667 μs   125.481 ms  1595.09
    2 │ tuples      crc        79.250 μs   31.102 ms    392.453
    3 │ dataframes  crc        79.417 μs   6.382 ms      80.3635
    4 │ numbers     crc        39.875 μs   3.102 ms      77.7842
    5 │ symbols     crc        597.166 μs  21.122 ms     35.3705
    6 │ strings     crc        597.625 μs  13.749 ms     23.0063
    7 │ structs     sha256     545.916 μs  190.883 ms   349.656
    8 │ tuples      sha256     545.917 μs  47.118 ms     86.3101
    9 │ dataframes  sha256     547.500 μs  11.283 ms     20.6081
   10 │ numbers     sha256     271.708 μs  5.433 ms      19.9951
   11 │ symbols     sha256     4.086 ms    32.191 ms      7.87788
   12 │ strings     sha256     4.085 ms    21.856 ms      5.34987
```

# With Buffering

In `dfl/hash-buffer` hash computations are delayed and data is stored in an intermediate
buffer and only hashed when enough data has been written to the buffer. This addresses
many of the issues when hashing low-level objects like numbers and strings. Anything
where the type of the objects is represented as a string for each value in an array
remains quite slow.

```
 12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio
     │ SubStrin…   SubStrin…  String      String      Float64
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        70.250 μs   49.386 ms   703.011
   2 │ symbols     crc        12.166 μs   5.328 ms    437.928
   3 │ strings     crc        12.166 μs   4.777 ms    392.686
   4 │ tuples      crc        71.417 μs   10.082 ms   141.177
   5 │ dataframes  crc        70.208 μs   290.167 μs    4.13296
   6 │ numbers     crc        35.167 μs   126.375 μs    3.59357
   7 │ structs     sha256     532.833 μs  60.885 ms   114.266
   8 │ tuples      sha256     533.000 μs  12.937 ms    24.2711
   9 │ symbols     sha256     833.208 μs  7.607 ms      9.13022
  10 │ strings     sha256     833.417 μs  6.600 ms      7.9192
  11 │ dataframes  sha256     532.833 μs  775.917 μs    1.45621
  12 │ numbers     sha256     270.916 μs  374.417 μs    1.38204
```

# Version 1.1:

With the addition of `dfl/compiled-type-labels` we compute more quantities at compile time:

There are a number of hash quantities that are, strictly speaking, a function of the type of
objects, not their content. These hashes can be optimized using `@generated` functions and
macros to guarantee that their hashes are computed at compile time.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio
     │ SubStrin…   SubStrin…  String      String      Float64
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        71.542 μs   1.116 ms    15.6027
   2 │ tuples      crc        71.459 μs   918.917 μs  12.8594
   3 │ dataframes  crc        71.458 μs   257.166 μs   3.59884
   4 │ numbers     crc        35.916 μs   126.666 μs   3.52673
   5 │ symbols     crc        635.875 μs  629.000 μs   0.989188
   6 │ strings     crc        655.500 μs  561.292 μs   0.856281
   7 │ structs     sha256     543.166 μs  3.045 ms     5.60525
   8 │ tuples      sha256     543.125 μs  2.594 ms     4.77668
   9 │ symbols     sha256     1.494 ms    2.264 ms     1.51544
  10 │ strings     sha256     1.484 ms    2.196 ms     1.47992
  11 │ dataframes  sha256     543.125 μs  749.125 μs   1.37929
  12 │ numbers     sha256     270.958 μs  371.833 μs   1.37229
```

# Version 1.3:

Version 1.3 creates a new hash version (4) that abandons `@generated` functions and the
goal of perfectly hashing type names and type parameters. It also redesigns the API for
customizing hashes to leverage `StructTypes`. The goal of these changes is to have more
stable and predictable hash behavior.

A relatively naive implementation of this API, where parts of the hash that are a function
of the type are computed every time an object of that type is hashed leads to `trait`
columns in the table similar to version 1.0. Caching those parts of the hash that are a
function of only the type brings this down to about x10-60 times slower (depending on the
row). It appears that the calls to `get!` on the cached type hashes are a quite a bit slower
than the cost of hashing the content of the object.

The implementation used in 1.3 reduces the times in the benchmarks beyond what caching can
accomplish alone by hoisting type hashes outside of loops (and still caching their results
for future use). For example when hashing `Vector{Int}` the hash of the type `Int` is
computed only when hashing the array type, not when hashing the individual elements.

This implementation makes two additional, smaller improvements:

1. Objects that are large enough are hashed recursively and their results cached; this
   should help in cases where there are large repeated objects, and does not seem to have
   noticebly affected the benchmarks below. This use-case is tested in the `repeated`
   benchmark.

2. Type-hoisting has a special case for arrays of small unions, so that e.g.
   `Vector{Union{Missing, Int}}` hashes quickly in the below benchmarks.

Note that, while the benchmarks here are quite good, this implementation is likely slower
than Version 1.1 for deeply nested, type-unstable data structures
(e.g. nested `Dict{Any, Any}`), as this use case will hit the `get!` calls that seem to be fairly slow, while the older implementation would hit the `@generated` function calls.
However, such structures are presumably already quite slow to hash because of their
type-instability.

```
36×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼──────────────────────────────────────────────────────────────────────
   1 │ types       crc        3          143.375 μs  23.484 ms   163.794
   2 │ structs     crc        3          70.791 μs   1.752 ms     24.7471
   3 │ tuples      crc        3          70.666 μs   1.292 ms     18.2773
   4 │ repeated    crc        3          35.291 μs   421.041 μs   11.9305
   5 │ missings    crc        3          37.417 μs   201.209 μs    5.37748
   6 │ dataframes  crc        3          70.208 μs   216.375 μs    3.08191
   7 │ numbers     crc        3          35.125 μs   104.667 μs    2.97984
   8 │ symbols     crc        3          770.500 μs  977.500 μs    1.26866
   9 │ strings     crc        3          764.875 μs  827.459 μs    1.08182
  10 │ types       sha256     3          1.148 ms    24.244 ms    21.1189
  11 │ structs     sha256     3          573.959 μs  3.756 ms      6.54337
  12 │ tuples      sha256     3          574.042 μs  3.035 ms      5.28663
  13 │ repeated    sha256     3          286.583 μs  1.468 ms      5.12141
  14 │ missings    sha256     3          304.584 μs  558.750 μs    1.83447
  15 │ symbols     sha256     3          1.661 ms    2.685 ms      1.61662
  16 │ strings     sha256     3          1.673 ms    2.553 ms      1.52644
  17 │ dataframes  sha256     3          573.833 μs  740.334 μs    1.29016
  18 │ numbers     sha256     3          286.667 μs  367.375 μs    1.28154
  19 │ structs     crc        4          70.250 μs   1.080 ms     15.3742
  20 │ tuples      crc        4          70.166 μs   661.792 μs    9.4318
  21 │ missings    crc        4          37.458 μs   213.958 μs    5.71194
  22 │ dataframes  crc        4          70.167 μs   264.792 μs    3.77374
  23 │ repeated    crc        4          35.250 μs   115.000 μs    3.26241
  24 │ numbers     crc        4          35.250 μs   111.875 μs    3.17376
  25 │ symbols     crc        4          764.583 μs  1.990 ms      2.60322
  26 │ types       crc        4          141.042 μs  177.875 μs    1.26115
  27 │ strings     crc        4          764.125 μs  503.500 μs    0.658924
  28 │ structs     sha256     4          573.834 μs  2.105 ms      3.66758
  29 │ types       sha256     4          1.147 ms    3.875 ms      3.37752
  30 │ tuples      sha256     4          573.708 μs  1.672 ms      2.91423
  31 │ symbols     sha256     4          1.659 ms    3.478 ms      2.09653
  32 │ missings    sha256     4          304.500 μs  517.750 μs    1.70033
  33 │ dataframes  sha256     4          573.875 μs  787.125 μs    1.3716
  34 │ repeated    sha256     4          286.667 μs  379.083 μs    1.32238
  35 │ numbers     sha256     4          286.750 μs  375.000 μs    1.30776
  36 │ strings     sha256     4          1.663 ms    1.988 ms      1.19518
```

Note that neither the `type` nor `repeated` benchmarks existed in prior versions.

### Without Caching

If `get!` is so slow, is it worth caching types at all? What does performance look like when you disable caching? The new `types` benchmark hashes an array of random types selected from four possible options to determine what is gained by pre-computing the hash for data where the type must be hashed many times.

With caching disabled, the `types` benchmark, degrades as follows:

```
36×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼──────────────────────────────────────────────────────────────────────
   1 │ types       crc        3          143.083 μs  23.857 ms   166.736
  10 │ types       sha256     3          1.169 ms    24.367 ms    20.836
  19 │ types       crc        4          143.041 μs  9.123 ms     63.7772
  28 │ types       sha256     4          1.170 ms    8.773 ms      7.49915
```

Indicating that while `get!` is slow enough to be worth eliding when possible, it remains faster than hashing type values directly.
