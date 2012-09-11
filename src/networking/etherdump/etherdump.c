/*
 *  EtherDump 2.11
 *  IPv4 packet sniffer using raw sockets
 *
 *  Copyright (C) 2004  Christophe Devine
 *  Copyright (C) 2004-2012  Peter Willis <peterwwillis@yahoo.com>
 *  Copyright (C) 2004  Erik Andersen <andersen@codepoet.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * Some Windows code stolen shamelessly from http://www.binarytides.com/packet-sniffer-code-in-c-using-winsock/
 */

#ifdef __CYGWIN__
#include <winsock2.h>
#include <ws2tcpip.h> //IP_HDRINCL is here
//#include <mstcpip.h>
#define SIO_RCVALL            _WSAIOW(IOC_VENDOR,1)
#define PACKET_OUTGOING          4
#pragma comment(lib,"ws2_32.lib") //winsock 2.2 library
#else
#include <netpacket/packet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <net/if.h>
#endif

#include <sys/ioctl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/time.h>
#include <ctype.h>
#include <getopt.h>
#include <stdlib.h>

#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>

#include "etherdump.h"

int logfd = 1; /* default to stdout */

/*struct protoent * my_getproto(unsigned char *name);
struct protoent * my_getprotobynumber(int proto);
struct protoent * my_getprotobyname(unsigned char *name);*/

struct protoent fake_proto = { "unknown", NULL, 0 };

static const struct option etherdump_long_options[] = {

    { "output",    1, NULL, 'o' },
    { "filter",    1, NULL, 'f' },
    { "interface", 1, NULL, 'i' },
    { "raw",    0, NULL, 'r' },
    { "help",   0, NULL, 'h' },
    { "Hex",    0, NULL, 'H' },
    { "debug",     0, NULL, 'd' },
    { 0, 0, 0, 0 }
};


int show_usage(const char *extra) {
    if ( strlen(extra) > 0 )
        fprintf(stderr, "error: %s\n\n", extra);
    fprintf(stderr, "usage: etherdump [options]\n"
    "   options:\n"
    "    -h,--help\t\tthis screen\n"
    "    -o,--output\t\toutput to a file instead of stdout\n"
    "    -r,--raw\t\toutput raw frames in binary\n"
    "    -H,--Hex\t\toutput raw frames in ASCII hex\n"
    "    -f,--filter\t\tfilter printed packets based on some rules\n"
    "    -d,--debug\t\tprint debugging information\n"
    "    -i,--interface\tinterface to listen for traffic on\n"
    );
    exit(1);
}


// yep, i stole this from the internets, then fixed it.
// takes a 4-byte unsigned char array in netwrk-byte order and returns a 32-bit integer
// in network-byte order.
uint32_t unsignedIntToLong(unsigned char *b) 
{
    uint32_t l = 0;
    l = ( (b[3] << 24) | (b[2] << 16) | (b[1] << 8) | (b[0]) );
    return l;
}

// given a char array, search for the first non-whitespace characters following some
// whitespace. this allows you to skip any word you might be at now, skip over
// the whitespace after it, and stop at the next word so you can process it.
// returns NULL if no next word found
unsigned char * nextword(unsigned char *string) {
    int i, ws=0;
    for (i=0; string[i] != '\0'; i++) {
        if ( string[i] == 9 || string[i] == 10 || string[i] == 12 || string[i] == 13 || string[i] == 32 ) {
            if ( ws == 0 )
                ws=1;
        } else if ( ws == 1 ) {
            return (string+i);
        }
    }
    return (NULL);
}

void * safe_malloc(size_t size) {
    void *ptr;
    errno = 0;
    if ( (ptr=malloc(size)) == NULL ) {
        perror("error allocating memory");
        exit(1);
    }
    return ptr;
}


struct protoent * my_getprotobynumber(int proto) {
    int i;
    struct protoent *foobar;

    fake_proto.p_proto = proto;

    for ( i=0; my_protocols[i].p_name != NULL; i++ ) {
        if ( my_protocols[i].p_proto == proto ) {
            foobar = (struct protoent *) &my_protocols[i];
            return foobar;
        }
    }
    return (struct protoent *) &fake_proto;
}


struct protoent * my_getprotobyname(unsigned char *name) {
    int i;
    struct protoent *foobar;

    fake_proto.p_proto = 0;
    fake_proto.p_name = name;

    for ( i=0; my_protocols[i].p_name != NULL; i++ ) {
        if ( strncmp(my_protocols[i].p_name, name, strlen(my_protocols[i].p_name)) == 0 ) {
            foobar = (struct protoent *) &my_protocols[i];
            return foobar;
        }
    }
    return (struct protoent *) &fake_proto;
}


struct protoent * my_getproto(unsigned char *name) {
    struct protoent *foo;
    if ( ( foo = my_getprotobyname(name) ) == NULL ) {
        if ( ( foo = my_getprotobynumber(atoi(name)) ) == NULL ) { /* bad protocol */
            show_usage("no such protocol found");
        }
    }

    return(foo);
}


int main( int argc, char *argv[] )
{
    unsigned char buffer[RAW_SOCK_BUFSIZ];
    int n, optval;
#ifdef __CYGWIN__
    SOCKET raw_sock;
    WSADATA wsock;
    struct sockaddr_in intfaceAddr; /* Multicast Address */
    int j=0, in=0;
    char hostname[100];
    struct hostent *localhn;
    struct in_addr addr;
#else
    int raw_sock;
    struct packet_mreq mr;
    struct ifreq ifr;
#endif

    struct my_sockaddr_ll sll;
    int socktype = SOCK_DGRAM;

    int i;
    char *outputfile = NULL;
    int dumptype = 0; // 0 for disabled, 1 for ASCII hex, 2 for raw binary
    char intface[16];

    struct my_sockaddr_ll from;
    unsigned int fromlen;

    int p_filter_idx = 0;
    int max_p_filters = 32;
    struct packet_filter_rule p_filters[max_p_filters];

    debug = 0;

    /* set default filter struct entries */
    for (i=0;i<max_p_filters;i++) {
        p_filters[i].match_type = 0;
        p_filters[i].proto = 0;
        p_filters[i].buff = NULL;
    }


    // default intface: eth0
    strncpy(intface, "eth0", sizeof(intface));

    while ((i = getopt_long (argc, argv, "hHtro:ei:f:d",
            etherdump_long_options, NULL)) > 0)
    {
     switch (i) {
        /* for some reason, "case 't'" causes a seg fault if it's not above the 'i' or 'e' part... strange huh? */
        case 'h':
            show_usage("");
            return(1);
        case 'H':
            socktype = SOCK_RAW;
            dumptype = 1;
            break;
        case 'r':
            socktype = SOCK_RAW;
            dumptype = 2;
            break;
        case 'o':
            outputfile = optarg;
            break;
        case 'i':
            memset(intface, '\0', sizeof(intface));
            strncpy(intface, optarg /*argv[optind]*/, sizeof(intface));
            break;
        case 'f':
            if ( (p_filter_idx = parse_filter(argc, argv, optind-1, p_filters)) == -1) {
                return(1);
            }
            break;
        case 'd':
            debug++;
     }
    }

    if (strlen(intface) < 1) {
        show_usage("no interface specified");
        return(1);
    }

#ifdef __CYGWIN__
    printf("\nInitialising Winsock...");
    if (WSAStartup(MAKEWORD(2,2),&wsock) != 0) {
        fprintf(stderr,"WSAStartup() failed");
        exit(EXIT_FAILURE);
    }
    printf("Winsock Initialised successfully.\n");
#endif

    /* create the raw socket */
#ifdef __CYGWIN__
    if ( ( raw_sock = socket( AF_INET, SOCK_RAW, IPPROTO_IP ) ) == SOCKET_ERROR ) {
#else
    if ( ( raw_sock = socket( PF_PACKET, socktype, htons( ETH_P_ALL ) ) ) < 0 ) {
#endif
        perror( "socket" );
        return( 1 );
    }

#ifdef __CYGWIN__
    /*if (gethostname(hostname, sizeof(hostname)) == SOCKET_ERROR) {
        printf("Error : %d",WSAGetLastError());
        return 1;
    }
    printf("\nHost name : %s \n",hostname);
    localhn = gethostbyname(hostname);*/

    memset(&intfaceAddr, 0, sizeof(intfaceAddr));
    intfaceAddr.sin_family = AF_INET;
    intfaceAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    intfaceAddr.sin_port = 0;

    //memcpy( &addr, localhn->h_addr_list[0], sizeof(struct in_addr) );
    //memcpy( &intfaceAddr.sin_addr.s_addr, &addr, sizeof(intfaceAddr.sin_addr.s_addr) );

    //printf("Interface Number : %d Address : %s\n", 0, inet_ntoa(addr) );

    if ( bind( raw_sock, (struct sockaddr *) &intfaceAddr, sizeof( intfaceAddr ) ) == SOCKET_ERROR ) {
#else
    /* find the intface index */
    memset( &ifr, 0, sizeof( ifr ) );
    strncpy( ifr.ifr_name, intface, sizeof( ifr.ifr_name ) );
    if( ioctl( raw_sock, SIOCGIFINDEX, &ifr ) < 0 ) {
        perror( "ioctl(SIOCGIFINDEX)" );
        return( 1 );
    }

    /* bind the raw socket to the intface */
    memset( &sll, 0, sizeof( sll ) );
    sll.sll_family   = AF_PACKET;
    sll.sll_ifindex  = ifr.ifr_ifindex;
    sll.sll_protocol = htons( ETH_P_ALL );

    if ( bind( raw_sock, (struct sockaddr *) &sll, sizeof( sll ) ) < 0 ) {
#endif
        perror( "bind" );
        return( 1 );
    }

    /* enable promiscuous mode */
#ifdef __CYGWIN__
    printf("\nSetting socket to sniff...");
    if ( WSAIoctl(raw_sock, SIO_RCVALL, &j, sizeof(j), 0, 0, (LPDWORD) &in , 0 , 0) == SOCKET_ERROR ) {
        printf("WSAIoctl() failed.\n");
        return 1;
    }
    printf("Socket set.\n");
#else
    memset( &mr, 0, sizeof( mr ) );
    mr.mr_ifindex = ifr.ifr_ifindex;
    mr.mr_type    = PACKET_MR_PROMISC;
    if( setsockopt( raw_sock, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &mr, sizeof( mr ) ) < 0 ) {
        perror( "setsockopt" );
        return( 1 );
    }
#endif

    F_logfd = stdout;

    /* (optionally) open a log file */
    if (outputfile != NULL) {
        if ( (logfd = open(outputfile, O_WRONLY|O_CREAT|O_TRUNC, S_IRUSR|S_IWUSR )) == -1) {
            perror ( "open" );
            return( 1 );
        }
        if ( (F_logfd = fdopen(logfd, "w")) == NULL ) {
            perror ( "fdopen" );
            return( 1 );
        }
    }

    while ( 1 ) {

        fprintf(stderr, "looping\n");

        memset(buffer, 0, sizeof(buffer));

        /* wait for packets */
        fromlen = sizeof( from );
        /* handle error from recvfrom */
#ifdef __CYGWIN__
        if ( ( n = recvfrom( raw_sock, buffer, RAW_SOCK_BUFSIZ, 0, NULL, 0 ) ) < 0 ) {
#else
        if ( ( n = recvfrom( raw_sock, buffer, RAW_SOCK_BUFSIZ, 0, (struct sockaddr *) &from, &fromlen ) ) < 0 ) {
#endif
            if( errno == ENETDOWN ) {
                if (debug) fprintf(stderr, "sleeping for 30 secs\n");
                sleep( 30 );
                continue;
            } else {
                perror( "recvfrom" );
                return( 1 );
            }
        }

        fprintf(stderr, "woohoo!!\n");

        /* skip duplicate packets on the loopback intface */
        if( from.sll_pkttype == PACKET_OUTGOING && ! strcmp( intface, "lo" ) ) {
            if (debug)
                fprintf(stderr, "skipping loopback duplicate packet\n");
            continue;
        }

        if (dumptype == 1) { /* dump ASCII hex of raw frames in 16 byte lines */
    
            for (i=0; i<=n; i++) {
                if ( (i % 16) == 0 ) {
                    fprintf(F_logfd, i == 0 ? "%.4x" : "\n%.4x", i);
                    fflush(NULL);
                }
                fprintf(F_logfd, " %.2X", buffer[i]);
                fflush(NULL);
            }
            fprintf(F_logfd, "\n");
            fflush(NULL);
    
        } else if (dumptype == 2) { /* dump raw frames in binary */
    
            write(logfd, buffer, n);
    
        } else { /* display certain packet types all nifty-like */

            uint16_t proto_num = ntohs(from.sll_protocol);

            if ( proto_num == ETH_P_IP ) {
                process_ip(&buffer, n, &from, p_filters, p_filter_idx);

            } else if ( proto_num == ETH_P_ARP ) {
                process_arp(&buffer, n, &from, p_filters, p_filter_idx);

            } else {
                if (debug) fprintf(stderr, "unsupported link layer protocol 0x%04x\n", proto_num);
                continue;

            }

        }

    }

    return( 0 );
}

