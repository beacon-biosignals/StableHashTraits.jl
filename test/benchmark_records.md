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
   1 │ 2          structs     crc        71.541 μs   1.289 ms    18.0124
   2 │ 2          tuples      crc        70.125 μs   908.791 μs  12.9596
   3 │ 2          dataframes  crc        71.333 μs   256.000 μs   3.5888
   4 │ 2          numbers     crc        35.875 μs   126.834 μs   3.53544
   5 │ 2          vnumbers    crc        35.208 μs   105.875 μs   3.00713
   6 │ 2          symbols     crc        548.375 μs  660.500 μs   1.20447
   7 │ 2          strings     crc        558.125 μs  649.041 μs   1.1629
   8 │ 2          structs     sha256     542.916 μs  3.186 ms     5.86877
   9 │ 2          tuples      sha256     543.042 μs  2.714 ms     4.99693
  10 │ 2          symbols     sha256     1.394 ms    2.294 ms     1.64581
  11 │ 2          strings     sha256     1.396 ms    2.287 ms     1.63805
  12 │ 2          vnumbers    sha256     271.041 μs  372.459 μs   1.37418
  13 │ 2          dataframes  sha256     533.125 μs  712.750 μs   1.33693
  14 │ 2          numbers     sha256     271.042 μs  353.333 μs   1.30361
  15 │ 3          structs     crc        71.583 μs   1.133 ms    15.8254
  16 │ 3          tuples      crc        71.292 μs   679.708 μs   9.53414
  17 │ 3          vnumbers    crc        35.166 μs   109.375 μs   3.11025
  18 │ 3          dataframes  crc        71.250 μs   214.792 μs   3.01462
  19 │ 3          numbers     crc        35.208 μs   105.959 μs   3.00951
  20 │ 3          symbols     crc        554.292 μs  660.209 μs   1.19109
  21 │ 3          strings     crc        555.583 μs  156.958 μs   0.28251
  22 │ 3          structs     sha256     542.959 μs  2.361 ms     4.34763
  23 │ 3          tuples      sha256     542.917 μs  1.636 ms     3.01374
  24 │ 3          symbols     sha256     1.393 ms    2.343 ms     1.68243
  25 │ 3          dataframes  sha256     542.958 μs  751.333 μs   1.38378
  26 │ 3          vnumbers    sha256     271.042 μs  375.042 μs   1.3837
  27 │ 3          numbers     sha256     271.000 μs  372.458 μs   1.37438
  28 │ 3          strings     sha256     1.397 ms    1.076 ms     0.770684
```
