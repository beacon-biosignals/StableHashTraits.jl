# Benchmark Records

A record of benchmarks from various versions of `stable_hash`

# Version 1.0

```
 Row │ benchmark   hash       base        trait       ratio      
     │ SubStrin…   SubStrin…  String      String      Float64    
─────┼───────────────────────────────────────────────────────────
   1 │ structs     crc        78.958 μs   98.674 ms   1249.7
   2 │ dataframes  crc        78.959 μs   4.290 ms      54.3383
   3 │ numbers     crc        39.708 μs   2.097 ms      52.8115
   4 │ symbols     crc        597.791 μs  15.910 ms     26.6143
   5 │ strings     crc        597.583 μs  10.400 ms     17.4036
   6 │ tuples      crc        4.204 ms    24.588 ms      5.84912
   7 │ structs     sha256     545.458 μs  168.409 ms   308.747
   8 │ dataframes  sha256     544.750 μs  9.425 ms      17.3024
   9 │ numbers     sha256     271.500 μs  4.652 ms      17.1356
  10 │ symbols     sha256     4.083 ms    28.409 ms      6.9572
  11 │ strings     sha256     4.084 ms    19.677 ms      4.81845
  12 │ tuples      sha256     9.307 ms    41.904 ms      4.50222
```
