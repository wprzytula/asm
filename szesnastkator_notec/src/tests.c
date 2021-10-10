#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
#include <assert.h>
#include <stdlib.h>

#include "err.h"

#ifndef N
#define N 1
#endif

#ifndef T
#define T 1
#endif

extern uint64_t notec(uint32_t n, char const *calc);
extern int64_t debug(uint32_t n, uint64_t *stack_pointer);

/*int64_t debug(uint32_t n, uint64_t *stack_pointer) {
    for (unsigned i = 0; i < 5; ++i, ++stack_pointer) {
        printf("[rsp + %u], contains %lu.\n", i, *stack_pointer);
    }
    return 1;
}*/

#if N == 1
char const *const tests[] = {
        "0",        // test 0
        "1=",
        "a",
        "F",
        "aF1=",
        "4a36aF34dY-+", // test 5
        "E-f+~~1|1&2^",
        "a--B--c--D--eZZXZYZ",
        "af=fa*",
        "N",
        "n",            // test 10
        "1=2=3=4=5gZ",          // 8 mod 16 aligned
        "1=2=3=4g",             // not aligned

};

uint64_t const results[] = {
        0,      // test 0
        1,
        10,
        15,
        2801,
        0,      // test 5
        3,
        0xC,
        0xaf * 0xfa,
        N,
        0,      // test 10
        3,
        3,

};

size_t const TEST_NUM = sizeof(tests) / sizeof(char*);

int main() {
    assert(TEST_NUM == sizeof(results) / sizeof(uint64_t));

    uint64_t result;
    for (unsigned i = 0; i < TEST_NUM; ++i) {
        result = notec(0, tests[i]);
        if (results[i] != result) {
            printf("Test %u failed! Expected %lu\t, got %lu\t:(\n",
                    i, results[i], result);
        } else {
            printf("Test %u passed.\n", i);
        }
    }

    return 0;
}
#endif
#if N == 3

pthread_t threads[N];
volatile unsigned wait = 1;

char const *const instructions[][N] = {
        {"N1YgWYg1W1n-+W", "n0YgWYg0W1n-+W", "1=2XZ"},
        {"nn0=1XXXXXXXXXXXXXXXXWWW", "n2=0WW", "1--1*0W"},
};

uint64_t const results[][N] = {
        {1, N, 2},
        {1, 0, 0}
};

#pragma GCC diagnostic ignored "-Wpointer-to-int-cast"
void* run_notec(void *arg) {
    uint32_t const n = (uint32_t) arg;

    while (wait);

    uint64_t result = notec(n, instructions[T][n]);
    if (results[T][n] != result) {
        printf("Notec %u failed! Expected %lu\t, got %lu\t:(\n",
                    n, results[T][n], result);
        abort();
        } else {
            printf("Notec %u succeeded.\n", n);
        }
    return NULL;
}

size_t const TEST_NUM = sizeof(instructions) / sizeof(char*);
size_t const RES_NUM = sizeof(results) / sizeof(uint64_t);

int main() {
    int err;

    assert(TEST_NUM == RES_NUM);

#pragma GCC diagnostic ignored "-Wint-to-pointer-cast"
    for (uint32_t i = 0; i < N; ++i) {
        pthread_create(threads + i, NULL,
                       (void *(*)(void *)) run_notec, (void *)i);
    }

    wait = 0;

    for (uint32_t i = 0; i < N; ++i) {
        verify(pthread_join(threads[i], NULL), "Error in join");
    }

    return 0;
}

#endif