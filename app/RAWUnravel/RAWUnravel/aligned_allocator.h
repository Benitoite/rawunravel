//
//  T.swift
//  RAWUnravel
//
//  Created by Richard Barber on 8/7/25.
//


// aligned_allocator.h
#pragma once
#include <cstdlib>
#include <new>

inline void* rt_aligned_malloc(std::size_t size, std::size_t align) {
#if defined(_MSC_VER)
  return _aligned_malloc(size, align);
#else
  void* p = nullptr;
  if (posix_memalign(&p, align, size) != 0) return nullptr;
  return p;
#endif
}
inline void rt_aligned_free(void* p) {
#if defined(_MSC_VER)
  _aligned_free(p);
#else
  std::free(p);
#endif
}

template<class T, std::size_t Align>
struct AlignedAllocator {
  using value_type = T;
  T* allocate(std::size_t n) {
    if (auto* p = static_cast<T*>(rt_aligned_malloc(n * sizeof(T), Align))) return p;
    throw std::bad_alloc();
  }
  void deallocate(T* p, std::size_t) noexcept { rt_aligned_free(p); }
  template<class U> struct rebind { using other = AlignedAllocator<U, Align>; };
};
