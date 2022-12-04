#!/bin/bash
if [[ "$1" == "clean" ]]; then
    rm -f busy_loop print_loop mem
else
    g++ busy_loop.cpp -o busy_loop -std=c++11 -lpthread &
    g++ print_loop.cpp -o print_loop -std=c++11 -lpthread &
    g++ mem.cpp -o mem -std=c++11 -lpthread &
    wait
fi

