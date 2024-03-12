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

Version 1.2 abandones `@generated` functions and the goal of perfectly hashing type names
and type parameters and it redesigns the API for customizing hashes. The hope is that this
will lead to more stable and predictable hash behavior.

A relatively naive implementation of this API, where parts of the hash that are a function
of the type are copmuted every time  an object of that type is hashed leads to `trait`
columns in the table below on order of x100-200 slower than the `base` columns. Caching
those parts of the hash that are a function of only the type brings this down to about
x20-60 times slower (depending on the row). It appears that the calls to `get!` on the
cached type hashes are very slow in comparison to the cost for re-hashing the type each
time.

The implementation used in 1.2 reduces the times in this table above what caching can
accomplish alone by hoisting type hashes outside of loops where possible (and still caching
their results for future use). For example when hashing `Vector{Int}` the hash of the type
`Int` is computed only when hashing the array type, not when hashing the individual
elements.

Note that, while the benchmarks here are quite good, this implementation is likely slower than Version 1.1 for deeply nested, type-unstable data structures (e.g. nested `Dict{Any, Any}`), as this use case will hit the `get!` calls that seem to be fairly slow. That said, such structures are presumably already quite slow to hash because of their type-instability.

This release also seems to have somewhat slowed down the version 2 hashes, but given that
these hashes are deprecated, and are still reasonably fast, no effort has been made to track
down what changes slowed down the older implementation. (And this could easily be the result of variance that can occur *across* runs of the benchmarks)

```
28×6 DataFrame
 Row │ benchmark   hash       version    base        trait       ratio
     │ SubStrin…   SubStrin…  SubStrin…  String      String      Float64
─────┼─────────────────────────────────────────────────────────────────────
   1 │ structs     crc        2          76.125 μs   1.854 ms    24.3509
   2 │ tuples      crc        2          75.458 μs   1.366 ms    18.1067
   3 │ missings    crc        2          43.208 μs   224.791 μs   5.20253
   4 │ dataframes  crc        2          81.458 μs   242.792 μs   2.98058
   5 │ numbers     crc        2          40.750 μs   117.625 μs   2.8865
   6 │ symbols     crc        2          851.250 μs  992.125 μs   1.16549
   7 │ strings     crc        2          892.959 μs  842.416 μs   0.943398
   8 │ structs     sha256     2          570.500 μs  4.114 ms     7.21202
   9 │ tuples      sha256     2          614.042 μs  3.112 ms     5.06833
  10 │ missings    sha256     2          302.417 μs  557.833 μs   1.84458
  11 │ symbols     sha256     2          1.768 ms    2.697 ms     1.52594
  12 │ strings     sha256     2          1.771 ms    2.560 ms     1.44572
  13 │ dataframes  sha256     2          570.417 μs  738.041 μs   1.29386
  14 │ numbers     sha256     2          284.833 μs  365.959 μs   1.28482
  15 │ structs     crc        3          76.250 μs   1.135 ms    14.8891
  16 │ tuples      crc        3          75.542 μs   696.709 μs   9.2228
  17 │ missings    crc        3          40.083 μs   251.250 μs   6.26824
  18 │ dataframes  crc        3          75.708 μs   272.583 μs   3.60045
  19 │ numbers     crc        3          37.833 μs   112.334 μs   2.96921
  20 │ symbols     crc        3          887.417 μs  2.266 ms     2.55296
  21 │ strings     crc        3          870.417 μs  485.792 μs   0.558114
  22 │ structs     sha256     3          571.292 μs  2.136 ms     3.73817
  23 │ tuples      sha256     3          570.541 μs  1.690 ms     2.96152
  24 │ missings    sha256     3          302.667 μs  766.125 μs   2.53125
  25 │ symbols     sha256     3          1.739 ms    3.525 ms     2.02671
  26 │ numbers     sha256     3          284.709 μs  398.792 μs   1.4007
  27 │ dataframes  sha256     3          570.375 μs  774.875 μs   1.35854
  28 │ strings     sha256     3          1.739 ms    1.927 ms     1.10787
```
