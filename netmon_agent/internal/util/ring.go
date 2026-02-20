package util

type Ring[T any] struct {
  values []T
  size   int
  idx    int
  filled bool
}

func NewRing[T any](size int) *Ring[T] {
  return &Ring[T]{values: make([]T, size), size: size}
}

func (r *Ring[T]) Add(v T) {
  if r.size == 0 {
    return
  }
  r.values[r.idx] = v
  r.idx = (r.idx + 1) % r.size
  if r.idx == 0 {
    r.filled = true
  }
}

func (r *Ring[T]) Values() []T {
  if !r.filled {
    return append([]T{}, r.values[:r.idx]...)
  }
  out := make([]T, 0, r.size)
  out = append(out, r.values[r.idx:]...)
  out = append(out, r.values[:r.idx]...)
  return out
}

func (r *Ring[T]) Len() int {
  if r.filled {
    return r.size
  }
  return r.idx
}
