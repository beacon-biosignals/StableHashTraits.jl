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

The implementation used in 1.3 reduces the times in this table beyond what caching can
accomplish alone by hoisting type hashes outside of loops (and still caching their results
for future use). For example when hashing `Vector{Int}` the hash of the type `Int` is
computed only when hashing the array type, not when hashing the individual elements.

This implementation makes two additional, smaller improvements:

1. Objects that are large enough are hashed recursively and their results cached; this
   should help in cases where there are large repeated objects, and does not seem to have
   noticebly affected the benchmarks below.

2. Type-hoisting has a special case for arrays of small unions, so that e.g.
   Vector{Union{Missing, Int}} hashes quickly in the below benchmarks.

Note that, while the benchmarks here are quite good, this implementation is likely slower
than Version 1.1 for deeply nested, type-unstable data structures
(e.g. nested `Dict{Any, Any}`), as this use case will hit the `get!` calls that seem to be fairly slow, while the
older implementation would hit the `@generated` function calls. However, such structures
are presumably already quite slow to hash because of their type-instability.

```
28×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼─────────────────────────────────────────────────────────────────────
   1 │ structs     crc        2          71.459 μs   895.083 μs  12.5258
   2 │ tuples      crc        2          71.417 μs   740.875 μs  10.3739
   3 │ missings    crc        2          38.167 μs   156.541 μs   4.10148
   4 │ dataframes  crc        2          71.417 μs   207.459 μs   2.9049
   5 │ numbers     crc        2          35.834 μs   102.209 μs   2.85229
   6 │ symbols     crc        2          564.500 μs  517.333 μs   0.916445
   7 │ strings     crc        2          572.375 μs  503.250 μs   0.879231
   8 │ structs     sha256     2          549.041 μs  2.890 ms     5.26312
   9 │ tuples      sha256     2          549.125 μs  2.445 ms     4.45277
  10 │ missings    sha256     2          291.167 μs  487.333 μs   1.67372
  11 │ symbols     sha256     2          1.422 ms    2.125 ms     1.49392
  12 │ strings     sha256     2          1.407 ms    2.075 ms     1.47465
  13 │ dataframes  sha256     2          549.375 μs  697.625 μs   1.26985
  14 │ numbers     sha256     2          274.042 μs  345.625 μs   1.26121
  15 │ structs     crc        3          71.500 μs   633.250 μs   8.85664
  16 │ missings    crc        3          37.708 μs   204.708 μs   5.42877
  17 │ tuples      crc        3          71.375 μs   373.875 μs   5.23818
  18 │ dataframes  crc        3          73.417 μs   228.917 μs   3.11804
  19 │ numbers     crc        3          35.792 μs   103.958 μs   2.9045
  20 │ symbols     crc        3          586.625 μs  1.438 ms     2.45138
  21 │ strings     crc        3          567.959 μs  309.417 μs   0.544788
  22 │ structs     sha256     3          549.083 μs  1.572 ms     2.86371
  23 │ tuples      sha256     3          549.042 μs  1.352 ms     2.46186
  24 │ symbols     sha256     3          1.425 ms    2.791 ms     1.95831
  25 │ missings    sha256     3          291.250 μs  486.708 μs   1.6711
  26 │ dataframes  sha256     3          549.125 μs  723.709 μs   1.31793
  27 │ numbers     sha256     3          274.042 μs  348.959 μs   1.27338
  28 │ strings     sha256     3          1.410 ms    1.675 ms     1.18809
```

# Version 1.3.1

This version implemnts a more uniform baseline test, and adds a new benchmark for deeply nested, type-unstable data. If caching of e.g. type hashes is ever added in the future
the dict benchmark will probably be a good one to pay attention to.

```
32×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼─────────────────────────────────────────────────────────────────────
   1 │ structs     crc        3          59.209 μs   1.177 ms    19.8759
   2 │ tuples      crc        3          59.083 μs   934.791 μs  15.8217
   3 │ numbers     crc        3          30.750 μs   140.459 μs   4.56777
   4 │ dataframes  crc        3          71.625 μs   290.375 μs   4.0541
   5 │ dicts       crc        3          1.809 ms    7.216 ms     3.98913
   6 │ missings    crc        3          324.250 μs  206.083 μs   0.635568
   7 │ strings     crc        3          1.103 ms    645.875 μs   0.585717
   8 │ symbols     crc        3          1.315 ms    728.042 μs   0.553626
   9 │ structs     sha256     3          505.666 μs  3.122 ms     6.17321
  10 │ tuples      sha256     3          505.750 μs  2.604 ms     5.14904
  11 │ dicts       sha256     3          2.301 ms    9.977 ms     4.33518
  12 │ numbers     sha256     3          253.083 μs  364.375 μs   1.43975
  13 │ dataframes  sha256     3          520.209 μs  743.042 μs   1.42835
  14 │ strings     sha256     3          2.050 ms    2.222 ms     1.08379
  15 │ symbols     sha256     3          2.232 ms    2.211 ms     0.99061
  16 │ missings    sha256     3          591.708 μs  521.666 μs   0.881627
  17 │ dicts       crc        4          1.831 ms    106.825 ms  58.3413
  18 │ structs     crc        4          59.041 μs   723.416 μs  12.2528
  19 │ tuples      crc        4          59.000 μs   490.334 μs   8.31075
  20 │ numbers     crc        4          30.750 μs   143.792 μs   4.67616
  21 │ dataframes  crc        4          72.208 μs   327.542 μs   4.53609
  22 │ symbols     crc        4          1.315 ms    1.478 ms     1.12386
  23 │ missings    crc        4          336.916 μs  254.833 μs   0.75637
  24 │ strings     crc        4          1.096 ms    398.208 μs   0.363384
  25 │ dicts       sha256     4          2.306 ms    113.127 ms  49.0602
  26 │ structs     sha256     4          505.625 μs  1.673 ms     3.3096
  27 │ tuples      sha256     4          505.667 μs  1.461 ms     2.88876
  28 │ dataframes  sha256     4          518.875 μs  784.833 μs   1.51257
  29 │ numbers     sha256     4          252.875 μs  369.709 μs   1.46202
  30 │ symbols     sha256     4          2.253 ms    2.793 ms     1.23962
  31 │ missings    sha256     4          582.250 μs  504.375 μs   0.866252
  32 │ strings     sha256     4          2.058 ms    1.696 ms     0.824243
```

# Version 2.0

This version deprecates all but hash version 4. As expected this has little impact
on the performance of benchmarks for hash version 4.

```
16×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼─────────────────────────────────────────────────────────────────────
   1 │ dicts       crc        4          1.533 ms    88.197 ms   57.5258
   2 │ structs     crc        4          57.417 μs   500.375 μs   8.71475
   3 │ tuples      crc        4          57.542 μs   344.500 μs   5.98693
   4 │ numbers     crc        4          28.875 μs   122.042 μs   4.22656
   5 │ dataframes  crc        4          73.042 μs   277.958 μs   3.80545
   6 │ symbols     crc        4          1.155 ms    1.371 ms     1.18639
   7 │ missings    crc        4          240.917 μs  207.083 μs   0.859562
   8 │ strings     crc        4          879.208 μs  289.083 μs   0.328799
   9 │ dicts       sha256     4          1.948 ms    81.803 ms   41.9871
  10 │ tuples      sha256     4          484.250 μs  1.599 ms     3.30201
  11 │ structs     sha256     4          475.292 μs  1.348 ms     2.83615
  12 │ symbols     sha256     4          2.009 ms    3.023 ms     1.50492
  13 │ dataframes  sha256     4          497.667 μs  702.000 μs   1.41058
  14 │ numbers     sha256     4          246.000 μs  336.750 μs   1.3689
  15 │ strings     sha256     4          1.753 ms    1.707 ms     0.973521
  16 │ missings    sha256     4          477.875 μs  443.042 μs   0.927109
```
