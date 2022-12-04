#include <bits/stdc++.h>

int main(int argc, char *argv[])
{
    int i = 1;
    if (argc > 1)
    {
        i = atoi(argv[1]) > 0 ? atoi(argv[1]) : 1;
    }

    char *buff = new char[i];
    memset(buff, 0, i);
    memcpy(buff, "hello world", 12);
    printf("%s\n", buff);
    delete[] buff;
    return 0;
}