// The first C++ throw on x86_64-aros GCC 13.4. Without the libgcc fix in
// patches/0001 this aborts; with it, it prints "caught 7" and returns 0.
#include <cstdio>

int main()
{
    try {
        throw 7;
    } catch (int x) {
        std::printf("caught %d\n", x);
        return 0;
    }
    return 1;
}
