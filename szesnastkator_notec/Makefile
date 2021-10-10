all: bin/tests bin/example bin/main

bin/main: obj/notec.o obj/main.o obj/err.o
	gcc -g obj/err.o obj/notec.o obj/main.o -lpthread -o bin/main
bin/tests: obj/notec.o obj/tests.o obj/debug.o obj/err.o
	gcc -g obj/err.o obj/notec.o obj/tests.o obj/debug.o -lpthread -o bin/tests
bin/example: obj/notec.o obj/example.o
	gcc -g obj/notec.o obj/example.o -lpthread -o bin/example
obj/debug.o: src/debug.asm
	nasm -g -DN=$N -f elf64 -w+all -w+error -o obj/debug.o src/debug.asm
obj/err.o: src/err.h src/err.c
	gcc -c -Wall -Wextra -O2 -std=c11 -o obj/err.o src/err.c
obj/main.o: src/main.c
	gcc -g -DN=$N -c -Wall -Wextra -O2 -std=c11 -o obj/main.o src/main.c
obj/notec.o: src/notec.asm
	nasm -g -DN=$N -f elf64 -w+all -w+error -o obj/notec.o src/notec.asm
obj/example.o: src/example.c
	gcc -g -DN=$N -c -Wall -Wextra -O2 -std=c11 -o obj/example.o src/example.c
obj/tests.o: src/tests.c
	gcc -g -DN=$N -DT=$T -c -Wall -Wextra -O2 -std=c11 -o obj/tests.o src/tests.c
clean:
	rm -f obj/* bin/*
