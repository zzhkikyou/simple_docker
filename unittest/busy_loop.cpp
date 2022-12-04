#include <bits/stdc++.h>

int main(int argc, char *argv[])
{
    int i = 1;
    if (argc > 1)
    {
        i = atoi(argv[1]) > 0 ? atoi(argv[1]): 1;
    }

    std::vector<std::thread> threads;
    threads.resize(i);

    auto loop = []()
    {
        while(1)
            ;
    };

    for (auto &t : threads)
    {
        t = std::thread(loop);
    }

    for (auto &t : threads)
    {
        if (t.joinable())
        {
            t.join();
        }
    }
    return 0;
}