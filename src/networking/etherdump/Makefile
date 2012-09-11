PROG=etherdump

CFLAGS=-Os -W
#-Wall

# For gdb debugging, does not change ethereal '-d' option
DEBUG=0

USE_IP=1
USE_TCP=1
USE_UDP=1
USE_ICMP=1
USE_ARP=1
USE_FILTERING=1

FLAGS=$(CFLAGS)
OBJECTS=

ifeq ($(DEBUG),1)
	FLAGS = -Wall -g -ggdb3
endif

ifeq ($(USE_TCP),1)
	OBJECTS += tcp.o
	FLAGS += -DUSE_TCP
endif

ifeq ($(USE_UDP),1)
	OBJECTS += udp.o
	FLAGS += -DUSE_UDP
endif

ifeq ($(USE_IP),1)
	OBJECTS += ip.o
	FLAGS += -DUSE_IP
endif

ifeq ($(USE_ARP),1)
	OBJECTS += arp.o
	FLAGS += -DUSE_ARP
endif

ifeq ($(USE_ICMP),1)
	OBJECTS += icmp.o
	FLAGS += -DUSE_ICMP
endif

ifeq ($(USE_FILTERING),1)
	OBJECTS += filtering.o
	FLAGS += -DUSE_FILTERING
endif

#ifeq ($(OSTYPE),cygwin)
#	OBJECTS += -lws2_32
#endif

all: ethereal

tcp.o: tcp.c
	$(CC) $(FLAGS) -c tcp.c

udp.o: udp.c
	$(CC) $(FLAGS) -c udp.c

icmp.o: icmp.c
	$(CC) $(FLAGS) -c icmp.c

ip.o: ip.c
	$(CC) $(FLAGS) -c ip.c

arp.o: arp.c
	$(CC) $(FLAGS) -c arp.c

filtering.o: filtering.c
	$(CC) $(FLAGS) -c filtering.c

ethereal: $(OBJECTS)
	if [ "$$OSTYPE" = "cygwin" ] ; then $(CC) $(FLAGS) ${PROG}.c -o ${PROG} $(OBJECTS) -lws2_32 ; else $(CC) $(FLAGS) ${PROG}.c -o ${PROG} $(OBJECTS) ; fi
	[ $(DEBUG) -eq 1 ] || strip ${PROG}

clean:
	rm -f etherdump *~ *.o
