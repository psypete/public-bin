
#include "etherdump.h"


int process_tcp_packet( struct ip_packet *ip, struct tcp_hdr *tcp, struct tcp_packet *packet ) {

    packet->source = ntohs( tcp->source );
    packet->destination = ntohs( tcp->dest );

    packet->flags.urg = (tcp->flags & (1<<5)) ? 1 : 0;
    packet->flags.ack = (tcp->flags & (1<<4)) ? 1 : 0;
    packet->flags.psh = (tcp->flags & (1<<3)) ? 1 : 0;
    packet->flags.rst = (tcp->flags & (1<<2)) ? 1 : 0;
    packet->flags.syn = (tcp->flags & (1<<1)) ? 1 : 0;
    packet->flags.fin = (tcp->flags & (1<<0)) ? 1 : 0;
    packet->header_length = ( ( ( ( ntohs(tcp->unused) >> 12 ) & 15 ) * 32 ) / 8 ); // size multiplier times 32 bits divided by 8 becomes bytes
    packet->seq = ntohl(tcp->seq);
    packet->ack = ntohl(tcp->ack_seq);
    packet->window = ntohs(tcp->window);            
    packet->packet_length = ( ip->packet_length - ip->header_length - packet->header_length );

    packet->start = tcp;
    packet->end = ((void *) tcp + packet->packet_length);

    return( 0 );
}


