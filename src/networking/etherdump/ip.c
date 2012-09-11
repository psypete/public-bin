#include <stdio.h>
#include <string.h>
#include <time.h>
#ifndef __CYGWIN__
//#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netpacket/packet.h>
#endif
#include "etherdump.h"


int process_ip_packet( struct ip_hdr *ip, struct ip_packet *packet ) {

    struct in_addr src;
    struct in_addr dst;
    int ihl=0;
    
    packet->version = ( ntohs(ip->hlv) >> 12 ); // since it's a uint16_t, move an extra 8 bits
    ihl = ( (ntohs(ip->hlv) >> 8) & 15 ); // since it's a uint16_t, move it 8 bits before masking off
    packet->header_length = ( (ihl * 32) / 8); // header length multiplier times 32 (32bit words) divided by 8 [bits] = total ip header bytes
    packet->packet_length = ntohs(ip->tot_len);
    packet->protocol = ( ntohs(ip->protocol) >> 8 );
    packet->hlv = ip->hlv;

    src.s_addr = ip->saddr;
    dst.s_addr = ip->daddr;

    memset(packet->source_a, '\0', sizeof(packet->source_a));
    memset(packet->destination_a, '\0', sizeof(packet->destination_a));
    strncpy(packet->source_a, inet_ntoa(src), sizeof(packet->source_a));
    strncpy(packet->destination_a, inet_ntoa(dst), sizeof(packet->destination_a));

    packet->start = ip;
    packet->end = ((void *) ip + packet->header_length);

    return( 0 );
}

int process_ip(unsigned char *buffer, int n, struct my_sockaddr_ll *from, struct packet_filter_rule *filters, int filter_idx) {

    struct ip_packet packet_ip;
#ifdef USE_TCP
    struct tcp_packet packet_tcp;
#endif
#ifdef USE_UDP
    struct udp_packet packet_udp;
#endif
#ifdef USE_ICMP
    struct icmp_packet packet_icmp;
#endif

    struct ip_hdr *ip;

    int next_packet=0;

    gettimeofday(&tv, NULL);
    lt = localtime( &tv.tv_sec );

    ip = (struct ip_hdr *) buffer;
    process_ip_packet( ip, &packet_ip );

    switch( packet_ip.protocol )
    {
    case SOL_TCP: /* SOL_TCP */
#ifdef USE_TCP
        process_tcp_packet( &packet_ip, (struct tcp_hdr *) ((unsigned char *) ip + packet_ip.header_length), &packet_tcp );
        next_packet = filter_packet( from, &packet_ip, &packet_tcp, filters, filter_idx );
#endif
        goto common;

    case SOL_UDP: /* SOL_UDP */
#ifdef USE_UDP
        process_udp_packet( &packet_ip, (struct udp_hdr *) ((unsigned char *) ip + packet_ip.header_length), &packet_udp );
        next_packet = filter_packet( from, &packet_ip, &packet_udp, filters, filter_idx );
#endif
        goto common;

    case SOL_ICMP: /* SOL_ICMP */
#ifdef USE_ICMP
        process_icmp_packet( &packet_ip, (struct icmp_hdr *) ((unsigned char *) ip + packet_ip.header_length), &packet_icmp );
        next_packet = filter_packet( from, &packet_ip, &packet_icmp, filters, filter_idx );
#endif
        goto common;

    common:

        break;

    default:
        if ( debug ) fprintf(stderr, "unsupported IP protocol %d from %s to %s\n", packet_ip.protocol, packet_ip.source_a, packet_ip.destination_a);
        next_packet=1;
        break;
    }

    if (next_packet)
        return(0);

#ifdef USE_TCP
    if (packet_ip.protocol == SOL_TCP) { /* tcp-specific printing */

        fprintf(F_logfd, "%02d:%02d:%02d.%d IP %s.%d > %s.%d: Flags [", lt->tm_hour, lt->tm_min, lt->tm_sec, (int)tv.tv_usec, packet_ip.source_a, packet_tcp.source, packet_ip.destination_a, packet_tcp.destination);

        if ( packet_tcp.flags.syn )
            fprintf(F_logfd, "S");
        if ( packet_tcp.flags.fin )
            fprintf(F_logfd, "F");
        if ( packet_tcp.flags.psh )
            fprintf(F_logfd, "P");
        if ( packet_tcp.flags.rst )
            fprintf(F_logfd, "R");
        if ( ! ( packet_tcp.flags.syn || packet_tcp.flags.fin || packet_tcp.flags.psh || packet_tcp.flags.rst ) )
            fprintf(F_logfd, ".");

        fprintf(F_logfd, "]");

        if ( packet_tcp.flags.syn || packet_tcp.flags.fin )
            fprintf(F_logfd, ", seq %lu", (long unsigned int) packet_tcp.seq);

        if ( packet_tcp.ack )
            fprintf(F_logfd, ", ack %lu", (long unsigned int) packet_tcp.ack);

        if ( packet_tcp.window )
            fprintf(F_logfd, ", win %u", packet_tcp.window);

        //if ( packet_tcp.packet_length )
            fprintf(F_logfd, ", length %u", packet_tcp.packet_length);

    }
#endif
#ifdef USE_UDP
    if (packet_ip.protocol == SOL_UDP) { /* udp-specific printing */

        fprintf(F_logfd, "%02d:%02d:%02d.%d IP %s.%d > %s.%d: UDP, length %u", lt->tm_hour, lt->tm_min, lt->tm_sec, (int)tv.tv_usec, packet_ip.source_a, packet_udp.source, packet_ip.destination_a, packet_udp.destination, packet_udp.packet_length);

    }
#endif
#ifdef USE_ICMP
    if (packet_ip.protocol == SOL_ICMP) { /* icmp-specific printing */
        tcpdump_print_icmp(&packet_ip, &packet_icmp);
    }
#endif

    fprintf(F_logfd, "\n");
    fflush(NULL);

    return(0);
}


