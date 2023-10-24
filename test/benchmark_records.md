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
   1 │ 2          structs     crc        70.166 μs   1.190 ms    16.9633
   2 │ 2          tuples      crc        70.250 μs   932.459 μs  13.2734
   3 │ 2          dataframes  crc        71.458 μs   262.708 μs   3.6764
   4 │ 2          vnumbers    crc        35.167 μs   128.750 μs   3.6611
   5 │ 2          numbers     crc        35.917 μs   128.417 μs   3.57538
   6 │ 2          symbols     crc        616.459 μs  666.208 μs   1.0807
   7 │ 2          strings     crc        647.208 μs  603.042 μs   0.931759
   8 │ 2          structs     sha256     543.084 μs  3.040 ms     5.59743
   9 │ 2          tuples      sha256     543.125 μs  2.583 ms     4.75589
  10 │ 2          symbols     sha256     1.484 ms    2.238 ms     1.50779
  11 │ 2          strings     sha256     1.464 ms    2.176 ms     1.48634
  12 │ 2          numbers     sha256     266.083 μs  375.542 μs   1.41137
  13 │ 2          vnumbers    sha256     265.875 μs  370.625 μs   1.39398
  14 │ 2          dataframes  sha256     532.958 μs  740.708 μs   1.38981
  15 │ 3          structs     crc        70.917 μs   1.068 ms    15.0563
  16 │ 3          tuples      crc        70.292 μs   644.917 μs   9.17483
  17 │ 3          vnumbers    crc        35.167 μs   130.167 μs   3.7014
  18 │ 3          dataframes  crc        70.083 μs   258.750 μs   3.69205
  19 │ 3          numbers     crc        35.208 μs   127.792 μs   3.62963
  20 │ 3          symbols     crc        648.000 μs  666.208 μs   1.0281
  21 │ 3          strings     crc        619.167 μs  156.333 μs   0.252489
  22 │ 3          structs     sha256     543.125 μs  2.232 ms     4.11024
  23 │ 3          tuples      sha256     533.041 μs  1.711 ms     3.21027
  24 │ 3          symbols     sha256     1.491 ms    2.255 ms     1.51312
  25 │ 3          numbers     sha256     266.041 μs  373.084 μs   1.40236
  26 │ 3          vnumbers    sha256     265.917 μs  370.792 μs   1.39439
  27 │ 3          dataframes  sha256     533.000 μs  741.958 μs   1.39204
  28 │ 3          strings     sha256     1.475 ms    1.059 ms     0.718063
```
