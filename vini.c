#include <stdio.h>
#include <stddef.h>
#include <stdbool.h>

typedef unsigned long long ull;

__always_inline inline const bool collatzFor(const ull n, const bool print)
{
    for (ull x = n; x > 1;)
    {
        if (print)
        {
            printf("%llu, ", x);
        }
        if (x & 1)
        {
            x = 3 * x + 1;
            continue;
        }
        x /= 2;
    }

    if (print)
    {
        printf("1\n");
    }

    return true;
}

const bool collatzFromOneTo(const ull n)
{
    for (ull i = 1; i <= n; i++)
    {
        collatzFor(n, false);
    }
    return true;
}

int main()
{
    ull x;
    printf("ull size: %ubytes\n", sizeof(ull));
    printf("Digite um numero ");
    scanf("%llu", &x);

    if (collatzFromOneTo(x))
    {
        printf("The collatz conjecture was proofed from 1 to %llu successfully!\n", x);
    }
    collatzFor(x, true);
    return 0;
}