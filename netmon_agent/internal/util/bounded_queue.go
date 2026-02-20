package util

type BoundedQueue[T any] struct {
  ch chan T
}

func NewBoundedQueue[T any](size int) *BoundedQueue[T] {
  return &BoundedQueue[T]{ch: make(chan T, size)}
}

func (q *BoundedQueue[T]) TryEnqueue(v T) bool {
  select {
  case q.ch <- v:
    return true
  default:
    return false
  }
}

func (q *BoundedQueue[T]) Channel() <-chan T {
  return q.ch
}

func (q *BoundedQueue[T]) Depth() int {
  return len(q.ch)
}
