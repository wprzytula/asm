#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
#include <assert.h>

#include "err.h"

#ifndef N
#define N 3
#endif

pthread_t threads[N];

char const *const instructions[] = {
    "N1YgWYg1W1n-+W",
    "n0YgWYg0W1n-+W",
    "1=2XZ"
};

uint64_t const results[] = {
    1,
    N,
    2
};

size_t const TEST_NUM = sizeof(instructions) / sizeof(char*);


extern uint64_t notec(uint32_t n, char const *calc);

int64_t debug(uint32_t n, uint64_t *stack_pointer) {
    /*printf("Notec %u, [rsp - 8 = %p] contains %lu.\n",
           n, stack_pointer - 1, *(stack_pointer - 1));*/
    printf("Notec %u, [rsp = %p] contains %lu.\n",
           n, stack_pointer, *stack_pointer);
    printf("Notec %u, [rsp + 8 = %p] contains %lu.\n\n",
           n, stack_pointer + 1, *(stack_pointer + 1));
    return 1;
}

volatile int wait = 1;

void* run_notec(void *arg) {
#pragma GCC diagnostic ignored "-Wpointer-to-int-cast"
    uint32_t const n = (uint32_t) arg;

    while(wait);

    uint64_t result = notec(n, instructions[n]);

    if (results[n] != result) {
        printf("Notec %u failed! Expected %lu\t, got %lu\t:(\n",
                n, results[n], result);
    } else {
        printf("Notec %u passed.\n", n);
    }

//    printf("Notec %u returned: %lu\n", n, result);
    return NULL;
}

int main() {
    int err;

    assert(TEST_NUM == sizeof(results) / sizeof(uint64_t));

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
