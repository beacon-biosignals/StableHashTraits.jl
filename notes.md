- Should I expand use of `nameof` (without module) to cover e.g. Function (maybe discucss with Eric)
- I think I found a bug during test cleanup: you can convert an `Any` type to
  something concrete (e.g. via NamedTuple) and this will cause the
  type to be hoisted when it shouldn't be
    - this can be fixed by requiring concrete fields in the pre-transformed
      object
    - we could add a flag for saying even if the pre-transformed object
      is unstable the transform still works
