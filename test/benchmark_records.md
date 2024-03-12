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

# Version 1.2:

Version 1.2 creates a new hash version (3) that abandones `@generated` functions and the
goal of perfectly hashing type names and type parameters. It also redesigns the API for
customizing hashes to leverage `StructTypes`. The goal of these changes is to have more
stable and predictable hash behavior.

A relatively naive implementation of this API, where parts of the hash that are a function
of the type are computed every time an object of that type is hashed leads to `trait`
columns in the table below on order of x100-200 slower than the `base` columns. Caching
those parts of the hash that are a function of only the type brings this down to about
x10-60 times slower (depending on the row). It appears that the calls to `get!` on the
cached type hashes are not much faster than the the cost of re-hashing the type each
time.

The implementation used in 1.2 reduces the times in this table beyond what caching can
accomplish alone by hoisting type hashes outside of loops where possible (and still caching
their results for future use). For example when hashing `Vector{Int}` the hash of the type
`Int` is computed only when hashing the array type, not when hashing the individual
elements.

This implementation makes two additional, smaller improvements:

1. Objects that are large enough are hashed recursively and their results cached; this
   should help in cases where there are large repeated objects, and does not seem to have
   noticebly affected the benchmarks below.

2. Type-hoisting has a special case for arrays of small unions, so that e.g.
   Vector{Union{Missing, Int}} hashes quickly in the below benchmarks.

Note that, while the benchmarks here are quite good, this implementation is likely slower
than Version 1.1 for deeply nested, type-unstable data structures (e.g. nested `Dict{Any,
Any}`), as this use case will hit the `get!` calls that seem to be fairly slow, while the
older implementation would hit the `@generated` function calls. However, such structures
are presumably already quite slow to hash because of their type-instability.

```
28×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼─────────────────────────────────────────────────────────────────────
   1 │ structs     crc        2          70.208 μs   898.041 μs  12.7911
   2 │ tuples      crc        2          71.416 μs   734.708 μs  10.2877
   3 │ missings    crc        2          37.458 μs   162.000 μs   4.32484
   4 │ dataframes  crc        2          71.417 μs   207.125 μs   2.90022
   5 │ numbers     crc        2          35.208 μs   102.083 μs   2.89943
   6 │ strings     crc        2          625.875 μs  500.084 μs   0.799016
   7 │ symbols     crc        2          662.500 μs  519.583 μs   0.784276
   8 │ structs     sha256     2          541.667 μs  2.856 ms     5.27307
   9 │ tuples      sha256     2          541.625 μs  2.425 ms     4.47704
  10 │ missings    sha256     2          281.875 μs  482.958 μs   1.71338
  11 │ symbols     sha256     2          1.438 ms    2.103 ms     1.46229
  12 │ strings     sha256     2          1.439 ms    2.079 ms     1.44493
  13 │ dataframes  sha256     2          531.625 μs  681.959 μs   1.28278
  14 │ numbers     sha256     2          270.250 μs  345.291 μs   1.27767
  15 │ structs     crc        3          71.458 μs   608.250 μs   8.51199
  16 │ missings    crc        3          37.375 μs   200.667 μs   5.36902
  17 │ tuples      crc        3          70.041 μs   367.375 μs   5.24514
  18 │ dataframes  crc        3          70.042 μs   223.833 μs   3.1957
  19 │ numbers     crc        3          35.125 μs   101.959 μs   2.90275
  20 │ symbols     crc        3          635.416 μs  1.448 ms     2.27856
  21 │ strings     crc        3          614.500 μs  304.542 μs   0.495593
  22 │ structs     sha256     3          541.791 μs  1.549 ms     2.85965
  23 │ tuples      sha256     3          531.666 μs  1.306 ms     2.45557
  24 │ symbols     sha256     3          1.464 ms    2.969 ms     2.02752
  25 │ missings    sha256     3          287.166 μs  487.000 μs   1.69588
  26 │ dataframes  sha256     3          531.667 μs  717.000 μs   1.34859
  27 │ numbers     sha256     3          270.291 μs  349.042 μs   1.29136
  28 │ strings     sha256     3          1.440 ms    1.644 ms     1.14187
```
