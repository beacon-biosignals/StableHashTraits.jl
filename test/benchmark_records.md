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

# Hash APi Refactoring (`dfl/refactor-hash-api`)

Introduces some modest performance improvements, but this refactoring
is mainly to pave the way for larger performance imporvements in future PRs.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio     
     │ SubStrin…   SubStrin…  String      String      Float64   
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        78.833 μs   75.692 ms   960.161
   2 │ dataframes  crc        79.000 μs   2.688 ms     34.0287
   3 │ numbers     crc        39.667 μs   1.316 ms     33.1836
   4 │ symbols     crc        593.770 μs  11.563 ms    19.4739
   5 │ strings     crc        597.250 μs  8.225 ms     13.7708
   6 │ tuples      crc        2.653 ms    19.625 ms     7.39684
   7 │ structs     sha256     545.916 μs  172.651 ms  316.259
   8 │ dataframes  sha256     546.542 μs  9.768 ms     17.8729
   9 │ numbers     sha256     271.875 μs  4.810 ms     17.6921
  10 │ symbols     sha256     4.081 ms    27.740 ms     6.7982
  11 │ strings     sha256     4.090 ms    19.599 ms     4.79158
  12 │ tuples      sha256     9.652 ms    42.305 ms     4.38311
```
