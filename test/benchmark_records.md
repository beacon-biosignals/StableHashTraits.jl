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
   1 │ 2          structs     crc        75.833 μs   1.199 ms    15.8133
   2 │ 2          tuples      crc        75.667 μs   973.292 μs  12.8628
   3 │ 2          dataframes  crc        81.459 μs   249.625 μs   3.06443
   4 │ 2          vnumbers    crc        38.084 μs   115.000 μs   3.01964
   5 │ 2          numbers     crc        41.166 μs   123.834 μs   3.00816
   6 │ 2          symbols     crc        636.250 μs  716.250 μs   1.12574
   7 │ 2          strings     crc        644.416 μs  640.500 μs   0.993923
   8 │ 2          structs     sha256     571.542 μs  3.349 ms     5.85995
   9 │ 2          tuples      sha256     571.541 μs  2.740 ms     4.79333
  10 │ 2          symbols     sha256     1.519 ms    2.433 ms     1.60152
  11 │ 2          strings     sha256     1.531 ms    2.357 ms     1.53977
  12 │ 2          dataframes  sha256     570.542 μs  751.708 μs   1.31753
  13 │ 2          numbers     sha256     285.291 μs  375.500 μs   1.3162
  14 │ 2          vnumbers    sha256     283.875 μs  373.541 μs   1.31586
  15 │ 3          structs     crc        76.666 μs   1.086 ms    14.1615
  16 │ 3          tuples      crc        75.541 μs   655.667 μs   8.67962
  17 │ 3          vnumbers    crc        38.125 μs   116.792 μs   3.0634
  18 │ 3          dataframes  crc        75.709 μs   231.416 μs   3.05665
  19 │ 3          numbers     crc        38.292 μs   114.916 μs   3.00104
  20 │ 3          symbols     crc        639.583 μs  775.959 μs   1.21323
  21 │ 3          strings     crc        637.709 μs  166.750 μs   0.261483
  22 │ 3          structs     sha256     571.708 μs  2.406 ms     4.20793
  23 │ 3          tuples      sha256     571.583 μs  1.993 ms     3.48673
  24 │ 3          symbols     sha256     1.517 ms    2.434 ms     1.60471
  25 │ 3          vnumbers    sha256     285.166 μs  376.292 μs   1.31955
  26 │ 3          dataframes  sha256     570.625 μs  750.625 μs   1.31544
  27 │ 3          numbers     sha256     285.250 μs  375.167 μs   1.31522
  28 │ 3          strings     sha256     1.517 ms    1.135 ms     0.748146
```
