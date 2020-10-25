#!/bin/bash

cd ../src

nim c -d:ssl -r auth.nim | sed 's/^/AUTH: /' &
nim c -d:ssl -r mm.nim | sed 's/^/MM: /' &
nim c -d:ssl -r gamei.nim | sed 's/^/GI1: /'
