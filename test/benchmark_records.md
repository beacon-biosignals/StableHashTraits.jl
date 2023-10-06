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
   1 │ structs     crc        70.334 μs   57.265 ms   814.193
   2 │ tuples      crc        71.625 μs   10.640 ms   148.551
   3 │ dataframes  crc        71.541 μs   589.375 μs    8.23828
   4 │ symbols     crc        781.166 μs  6.235 ms      7.98128
   5 │ numbers     crc        35.958 μs   282.583 μs    7.8587
   6 │ strings     crc        775.916 μs  5.038 ms      6.49356
   7 │ structs     sha256     575.083 μs  67.766 ms   117.836
   8 │ tuples      sha256     575.042 μs  13.383 ms    23.273
   9 │ symbols     sha256     1.588 ms    8.491 ms      5.34789
  10 │ strings     sha256     1.624 ms    6.798 ms      4.18542
  11 │ dataframes  sha256     574.958 μs  1.092 ms      1.89883
  12 │ numbers     sha256     286.666 μs  528.500 μs    1.84361
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
   1 │ 2          structs     crc        87.250 μs   1.377 ms    15.7799
   2 │ 2          tuples      crc        81.792 μs   1.063 ms    12.9933
   3 │ 2          dataframes  crc        87.250 μs   312.375 μs   3.58023
   4 │ 2          numbers     crc        44.334 μs   156.166 μs   3.52249
   5 │ 2          vnumbers    crc        41.166 μs   137.750 μs   3.34621
   6 │ 2          symbols     crc        747.709 μs  717.584 μs   0.95971
   7 │ 2          strings     crc        820.083 μs  697.167 μs   0.850118
   8 │ 2          structs     sha256     615.792 μs  3.660 ms     5.94384
   9 │ 2          tuples      sha256     658.167 μs  3.131 ms     4.75785
  10 │ 2          symbols     sha256     1.727 ms    2.570 ms     1.48794
  11 │ 2          numbers     sha256     307.375 μs  453.166 μs   1.47431
  12 │ 2          strings     sha256     1.751 ms    2.493 ms     1.4237
  13 │ 2          dataframes  sha256     615.292 μs  852.542 μs   1.38559
  14 │ 2          vnumbers    sha256     307.416 μs  424.291 μs   1.38019
  15 │ 3          structs     crc        87.500 μs   1.256 ms    14.3491
  16 │ 3          tuples      crc        81.750 μs   733.041 μs   8.96686
  17 │ 3          dataframes  crc        82.542 μs   293.792 μs   3.5593
  18 │ 3          vnumbers    crc        41.083 μs   137.833 μs   3.35499
  19 │ 3          numbers     crc        40.875 μs   135.791 μs   3.3221
  20 │ 3          symbols     crc        825.000 μs  771.250 μs   0.934848
  21 │ 3          strings     crc        846.833 μs  191.541 μs   0.226185
  22 │ 3          structs     sha256     616.083 μs  2.812 ms     4.565
  23 │ 3          tuples      sha256     615.875 μs  1.936 ms     3.14322
  24 │ 3          symbols     sha256     1.833 ms    2.748 ms     1.49934
  25 │ 3          vnumbers    sha256     307.416 μs  455.959 μs   1.4832
  26 │ 3          dataframes  sha256     615.958 μs  854.375 μs   1.38707
  27 │ 3          numbers     sha256     328.750 μs  453.125 μs   1.37833
  28 │ 3          strings     sha256     1.866 ms    1.223 ms     0.655403
```
