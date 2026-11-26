package main

// Release builds override this value while staging a new VERSION file.
BUILD_VERSION :: #config(TUKAN_VERSION, #load("../VERSION", string))
