
// #include <stdio.h>
// #include <string.h>
// #include <time.h>
// #include <sys/socket.h>
// #include <netinet/in.h>
// #include <netpacket/packet.h>

#ifndef __CYGWIN__
#include <arpa/inet.h>
#endif

#include "etherdump.h"


int process_udp_packet( struct ip_packet *ip, struct udp_hdr *udp, struct udp_packet *packet ) {

    packet->source = ntohs(udp->source);
    packet->destination = ntohs(udp->dest);
    packet->length = ntohs(udp->len);
    packet->checksum = ntohs(udp->check);
    packet->packet_length = ( ip->packet_length - 8 ); // 8 = size of UDP header

    packet->start = udp;
    packet->end = ((void *) udp + packet->packet_length);

    return( 0 );
}


