TEMPFILES = *.o *.out
PROGS = raspberry-split

all:
	gcc -o ${PROGS} ${PROGS}.c
	sudo mv ${PROGS} /usr/local/bin/${PROGS}

clean:
	-rm -f ${PROGS} ${TEMPFILES}
