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

There are a number of hash quantities that are, strictly speaking,
a function of the type of objects, not their content. These hashes can be optimized
using `@generated` functions to guarantee that their hashes are computed at compile time.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio    
     │ SubStrin…   SubStrin…  String      String      Float64  
─────┼─────────────────────────────────────────────────────────
   1 │ structs     crc        70.209 μs   1.095 ms    15.5993
   2 │ tuples      crc        71.792 μs   887.083 μs  12.3563
   3 │ dataframes  crc        71.542 μs   221.666 μs   3.0984
   4 │ numbers     crc        35.166 μs   107.834 μs   3.06643
   5 │ symbols     crc        551.750 μs  673.708 μs   1.22104
   6 │ strings     crc        551.209 μs  595.833 μs   1.08096
   7 │ structs     sha256     549.291 μs  3.066 ms     5.5825
   8 │ tuples      sha256     543.459 μs  2.602 ms     4.78777
   9 │ symbols     sha256     1.375 ms    2.275 ms     1.65423
  10 │ strings     sha256     1.388 ms    2.239 ms     1.61243
  11 │ dataframes  sha256     533.500 μs  716.209 μs   1.34247
  12 │ numbers     sha256     271.125 μs  355.625 μs   1.31166

# Version 1.2

Version 1.2 introduces `HashVersion{3}`. This reduces the number of hash collisions by
hashing the type of all primitive types. To avoid substantial slow-downs it elides these
types in cases where the struct type or element type is concrete. (so `Any[1, 2]` would
encode the type of each element but `[1, 2]` would only encode the type of the array). 

```
28×6 DataFrame
 Row │ version    benchmark   hash       base        trait       ratio     
     │ SubStrin…  SubStrin…   SubStrin…  String      String      Float64   
─────┼─────────────────────────────────────────────────────────────────────
   1 │ 2          structs     crc        71.500 μs   1.133 ms    15.8415
   2 │ 2          tuples      crc        71.416 μs   914.125 μs  12.8
   3 │ 2          dataframes  crc        71.417 μs   270.375 μs   3.78586
   4 │ 2          vnumbers    crc        35.875 μs   134.541 μs   3.75027
   5 │ 2          numbers     crc        35.875 μs   134.458 μs   3.74796
   6 │ 2          symbols     crc        537.375 μs  690.542 μs   1.28503
   7 │ 2          strings     crc        537.208 μs  608.291 μs   1.13232
   8 │ 2          structs     sha256     543.500 μs  3.112 ms     5.72539
   9 │ 2          tuples      sha256     543.500 μs  2.647 ms     4.87036
  10 │ 2          dataframes  sha256     543.500 μs  771.209 μs   1.41897
  11 │ 2          vnumbers    sha256     271.292 μs  383.417 μs   1.4133
  12 │ 2          numbers     sha256     271.291 μs  383.166 μs   1.41238
  13 │ 2          symbols     sha256     4.078 ms    2.355 ms     0.577401
  14 │ 2          strings     sha256     4.078 ms    2.269 ms     0.556482
  15 │ 3          structs     crc        71.583 μs   1.039 ms    14.5105
  16 │ 3          tuples      crc        71.416 μs   648.167 μs   9.07594
  17 │ 3          vnumbers    crc        35.833 μs   136.000 μs   3.79538
  18 │ 3          dataframes  crc        71.459 μs   271.167 μs   3.79472
  19 │ 3          numbers     crc        35.375 μs   134.083 μs   3.79033
  20 │ 3          symbols     crc        537.375 μs  695.916 μs   1.29503
  21 │ 3          strings     crc        537.417 μs  179.041 μs   0.333151
  22 │ 3          structs     sha256     543.375 μs  2.274 ms     4.18519
  23 │ 3          tuples      sha256     543.542 μs  1.641 ms     3.01847
  24 │ 3          dataframes  sha256     543.459 μs  771.917 μs   1.42038
  25 │ 3          vnumbers    sha256     271.292 μs  385.167 μs   1.41975
  26 │ 3          numbers     sha256     271.250 μs  383.291 μs   1.41305
  27 │ 3          symbols     sha256     4.078 ms    2.356 ms     0.577769
  28 │ 3          strings     sha256     4.078 ms    1.101 ms     0.27008
```
